//
//  ServerSyncModule.swift
//  Health Companion
//
//  Spezi Module for synchronizing FHIR observations to the Client-Facing Server.
//  Uses swift-openapi-generator client for type-safe API communication (DP3).
//
//  Maps to:
//  - DR1 (Standardized health data collection and transmission)
//  - DR2 (Patient-initiated data transfer)
//  - DR4 (Status tracking and transparency)
//  - DP1 (FHIR as canonical data format)
//  - DP3 (Loose coupling through standard interfaces)
//  - DO2 (Reliable transmission of ECG data)
//

import Foundation
import HTTPTypes
import OSLog
import OpenAPIRuntime
import OpenAPIURLSession
import Spezi
import SpeziFHIR
import SpeziFoundation
import SwiftUI


/// Synchronization status for the UI.
enum SyncStatus: Sendable, Equatable {
    case idle
    case syncing(count: Int)
    case success(Date)
    case error(String)
}


/// A Spezi `Module` that synchronizes FHIR resources to the Client-Facing Server.
///
/// Depends on `ServerAuthModule` for bearer token access and `FHIRStore` for
/// FHIR resource data. Uses background URL sessions (DR2) and idempotency keys
/// to ensure reliable, at-most-once delivery (DO2).
///
/// Usage in `Configuration`:
/// ```swift
/// Configuration(standard: HealthCompanionStandard()) {
///     ServerAuthModule()
///     ServerSyncModule()
///     // ...
/// }
/// ```
@Observable
final class ServerSyncModule: Module, EnvironmentAccessible, @unchecked Sendable {
    private let logger = Logger(subsystem: "HealthCompanion", category: "ServerSync")

    @ObservationIgnored @Dependency(ServerAuthModule.self) private var authModule
    @ObservationIgnored @Dependency(FHIRStore.self) private var fhirStore

    // MARK: - Observable State

    /// The current synchronization status.
    private(set) var syncStatus: SyncStatus = .idle

    /// Timestamp of the last successful sync.
    private(set) var lastSuccessfulSync: Date?

    /// Number of pending (unsynced) resources.
    private(set) var pendingCount: Int = 0

    /// Last error encountered during sync.
    private(set) var lastError: String?

    /// Server-side transfer status, refreshed periodically.
    private(set) var transferStatus: TransferStatusInfo?

    // MARK: - Internal

    /// Set of FHIR resource IDs that have already been synced (idempotency).
    private var syncedResourceIds: Set<String> = []

    /// Tracks the last known number of observations to detect new arrivals.
    private var lastKnownObservationCount: Int = 0

    /// Task that monitors the FHIRStore for new resources.
    @ObservationIgnored private var monitorTask: Task<Void, Never>?

    /// Path to the file tracking synced resource IDs.
    private var syncedIdsFileURL: URL {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDir.appendingPathComponent("synced_resource_ids.txt")
    }

    // MARK: - Module Lifecycle

    func configure() {
        loadSyncedIds()
        startAutoSync()
    }

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Auto-Sync

    /// Starts a background task that watches for new FHIR resources and syncs automatically.
    private func startAutoSync() {
        monitorTask = Task { [weak self] in
            guard let self else { return }
            // Brief startup delay to let FHIRStore populate
            try? await Task.sleep(nanoseconds: 3_000_000_000)

            while !Task.isCancelled {
                await self.autoSyncIfNeeded()
                // Poll every 10 seconds for new observations
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    /// Checks whether new observations have appeared and triggers a sync if so.
    private func autoSyncIfNeeded() async {
        let currentCount = await fhirStore.observations.count
        let unsynced = await fhirStore.observations.filter { resource in
            guard let fhirId = resource.fhirId else { return false }
            return !syncedResourceIds.contains(fhirId)
        }
        pendingCount = unsynced.count

        // Trigger sync when there are unsynced resources and auth is available
        if !unsynced.isEmpty && authModule.isAuthenticated {
            logger.info("Auto-sync: detected \(unsynced.count) unsynced resources, starting sync")
            await syncNow()
        }

        // Refresh server-side transfer status periodically
        if authModule.isAuthenticated {
            transferStatus = await fetchTransferStatus()
        }

        lastKnownObservationCount = currentCount
    }

    // MARK: - Public API

    /// Maximum number of retry attempts for failed uploads.
    private static let maxRetries = 3

    /// Base delay between retries in seconds (exponential backoff: 2s, 4s, 8s).
    private static let retryBaseDelay: TimeInterval = 2.0

    /// Triggers a synchronization of all unsynced FHIR resources.
    ///
    /// Collects observations from the `FHIRStore`, filters out already-synced ones,
    /// wraps them in a FHIR Bundle, and POSTs to the Client-Facing Server.
    /// Implements exponential backoff retry for transient failures (DP4, §5.5.1).
    func syncNow() async {
        guard authModule.isAuthenticated else {
            syncStatus = .error("Not authenticated")
            return
        }

        guard let serverURL = authModule.clientFacingBaseURL else {
            syncStatus = .error("Server URL not configured")
            return
        }

        let allResources = await fhirStore.observations
        let unsyncedResources = allResources.filter { resource in
            guard let fhirId = resource.fhirId else { return false }
            return !syncedResourceIds.contains(fhirId)
        }
        pendingCount = unsyncedResources.count

        guard !unsyncedResources.isEmpty else {
            logger.info("No unsynced resources to send")
            syncStatus = .idle
            return
        }

        syncStatus = .syncing(count: unsyncedResources.count)
        logger.info("Starting sync of \(unsyncedResources.count) resources")

        // Build FHIR Bundle and idempotency key once (reused across retries)
        let bundle = FHIRBundleBuilder.buildBundle(from: Array(unsyncedResources))
        let resourceIds = unsyncedResources.compactMap { $0.fhirId }.sorted()
        let idempotencyString = resourceIds.joined(separator: ",")
        let idempotencyData = Data(idempotencyString.utf8)
        let idempotencyKey = String(idempotencyData.base64EncodedString().prefix(64))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bodyData: Data
        do {
            bodyData = try encoder.encode(bundle)
        } catch {
            syncStatus = .error("Failed to encode bundle: \(error.localizedDescription)")
            return
        }

        // Retry loop with exponential backoff (DP4, §5.5.1)
        var lastError: Error?
        for attempt in 0...Self.maxRetries {
            if attempt > 0 {
                let delay = Self.retryBaseDelay * pow(2.0, Double(attempt - 1))
                logger.info("Retry attempt \(attempt)/\(Self.maxRetries) after \(delay)s delay")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            do {
                let result = try await performUpload(
                    serverURL: serverURL,
                    bodyData: bodyData,
                    idempotencyKey: idempotencyKey,
                    entries: Array(unsyncedResources)
                )

                if result {
                    // Success — mark resources as synced
                    for resource in unsyncedResources {
                        if let fhirId = resource.fhirId {
                            syncedResourceIds.insert(fhirId)
                        }
                    }
                    saveSyncedIds()
                    pendingCount = 0
                    lastSuccessfulSync = Date()
                    lastError = nil
                    self.lastError = nil
                    syncStatus = .success(Date())
                    logger.info("Sync completed: \(unsyncedResources.count) resources uploaded")
                    return
                }
            } catch SyncError.unauthorized {
                // Token expired — refresh and retry
                logger.warning("Received 401, attempting token refresh before retry")
                do {
                    _ = try await authModule.validAccessToken()
                    // Token refreshed — loop will retry
                } catch {
                    let errorMsg = "Authentication failed: \(error.localizedDescription)"
                    self.lastError = errorMsg
                    syncStatus = .error(errorMsg)
                    return
                }
            } catch {
                lastError = error
                logger.warning("Upload attempt \(attempt) failed: \(error.localizedDescription)")
                // Continue to next retry unless it's a non-retriable error
                if case SyncError.nonRetriable(let msg) = error {
                    self.lastError = msg
                    syncStatus = .error(msg)
                    return
                }
            }
        }

        // All retries exhausted
        let errorMsg = lastError?.localizedDescription ?? "Upload failed after \(Self.maxRetries) retries"
        self.lastError = errorMsg
        syncStatus = .error(errorMsg)
        logger.error("Sync failed after \(Self.maxRetries) retries: \(errorMsg)")
    }

    /// Performs a single upload attempt using the generated OpenAPI client.
    /// Returns `true` on success.
    /// Throws `SyncError.unauthorized` on 401, `SyncError.nonRetriable` on 4xx,
    /// or a generic error on network/server failures for retry.
    private func performUpload(
        serverURL: URL,
        bodyData: Data,
        idempotencyKey: String,
        entries: [FHIRResource]
    ) async throws -> Bool {
        let client = makeOpenAPIClient(serverURL: serverURL)

        // Decode the ModelsR4.Bundle JSON as the generated FHIRBundle type
        let fhirBundle = try JSONDecoder().decode(Components.Schemas.FHIRBundle.self, from: bodyData)

        let response = try await client.submitObservations(
            headers: .init(Idempotency_hyphen_Key: idempotencyKey),
            body: .json(fhirBundle)
        )

        switch response {
        case .created:
            return true
        case .ok:
            // Duplicate submission — already processed (idempotency)
            return true
        case .badRequest(let error):
            let body = try? error.body.json
            throw SyncError.nonRetriable("Bad request: \(body?.message ?? "unknown")")
        case .unauthorized:
            throw SyncError.unauthorized
        case .forbidden(let error):
            let body = try? error.body.json
            throw SyncError.nonRetriable("Forbidden: \(body?.message ?? "unknown")")
        case .tooManyRequests:
            throw SyncError.rateLimited
        case .undocumented(statusCode: let statusCode, _):
            if statusCode >= 500 {
                throw SyncError.serverError(statusCode)
            }
            throw SyncError.nonRetriable("Unexpected status: \(statusCode)")
        }
    }

    /// Fetches the current transfer status from the Client-Facing Server
    /// using the generated OpenAPI client.
    func fetchTransferStatus() async -> TransferStatusInfo? {
        guard authModule.isAuthenticated,
              let serverURL = authModule.clientFacingBaseURL
        else {
            return nil
        }

        do {
            let client = makeOpenAPIClient(serverURL: serverURL)
            let response = try await client.getTransferStatus()

            switch response {
            case .ok(let payload):
                let body = try payload.body.json
                return TransferStatusInfo(
                    hasSuccessfulTransfer: body.hasSuccessfulTransfer,
                    lastSuccessfulTransfer: body.lastSuccessfulTransfer,
                    lastAttempt: body.lastAttempt,
                    lastError: body.lastError?.rawValue,
                    pendingCount: body.pendingCount
                )
            case .unauthorized:
                logger.warning("Transfer status: unauthorized")
                return nil
            case .undocumented(statusCode: let statusCode, _):
                logger.warning("Transfer status: unexpected status \(statusCode)")
                return nil
            }
        } catch {
            logger.warning("Failed to fetch transfer status: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OpenAPI Client

    /// Creates a generated OpenAPI client configured with the server URL and bearer auth middleware.
    private func makeOpenAPIClient(serverURL: URL) -> Client {
        Client(
            serverURL: serverURL.appending(path: "api/v1"),
            transport: URLSessionTransport(),
            middlewares: [BearerAuthMiddleware(authModule: authModule)]
        )
    }

    // MARK: - Private: Synced IDs Persistence

    private func loadSyncedIds() {
        guard let data = try? Data(contentsOf: syncedIdsFileURL),
              let content = String(data: data, encoding: .utf8)
        else {
            return
        }
        syncedResourceIds = Set(content.components(separatedBy: "\n").filter { !$0.isEmpty })
        logger.debug("Loaded \(self.syncedResourceIds.count) synced resource IDs")
    }

    private func saveSyncedIds() {
        let content = syncedResourceIds.joined(separator: "\n")
        try? content.data(using: .utf8)?.write(to: syncedIdsFileURL, options: .atomic)
    }
}


// MARK: - Transfer Status DTO

/// Transfer status as reported by the Client-Facing Server.
struct TransferStatusInfo: Codable, Sendable {
    let hasSuccessfulTransfer: Bool
    let lastSuccessfulTransfer: Date?
    let lastAttempt: Date?
    let lastError: String?
    let pendingCount: Int?
}

// MARK: - Sync Errors

enum SyncError: LocalizedError {
    case unauthorized
    case rateLimited
    case serverError(Int)
    case nonRetriable(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Unauthorized — please log in again"
        case .rateLimited:
            "Rate limited — too many requests"
        case .serverError(let code):
            "Server error (\(code)) — will retry"
        case .nonRetriable(let message):
            message
        }
    }
}
