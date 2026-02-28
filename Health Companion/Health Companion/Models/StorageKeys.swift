//
//  StorageKeys.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

/// Enum of keys used for persistent storage.
enum StorageKeys {
    // MARK: - Onboarding
    /// A `Bool` flag indicating of the onboarding was completed.
    static let onboardingFlowComplete = "onboardingFlow.complete"

    // MARK: - Server Configuration
    /// The Client-Facing server base URL string (e.g. "http://localhost:8082").
    /// The IAM server is discovered automatically via the metadata endpoint.
    static let clientFacingServerURL = "server.clientFacingURL"
}
