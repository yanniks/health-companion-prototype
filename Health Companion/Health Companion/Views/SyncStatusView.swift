//
//  SyncStatusView.swift
//  Health Companion
//
//  Displays a user-friendly synchronization overview.
//  Maps to: DR4 (Status tracking and transparency)
//

import SpeziHealthKit
import SwiftUI


/// A user-friendly synchronization overview.
///
/// Shows a simple "Everything OK" / warning / error state to the user.
/// Technical details are available on a separate sheet for advanced users.
struct SyncStatusView: View {
    @Environment(ServerSyncModule.self) private var syncModule
    @Environment(ServerAuthModule.self) private var authModule

    @State private var showingDetails = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer()
                    .frame(height: 24)

                // Large status indicator
                statusIcon
                    .font(.system(size: 72))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(overallColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: isSyncing)

                // Status headline
                Text(overallHeadline)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                // Status subtitle
                Text(overallSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Quick stats cards
                HStack(spacing: 16) {
                    StatCard(
                        title: "Synced",
                        value: "\(syncedCount)",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    StatCard(
                        title: "Pending",
                        value: "\(syncModule.pendingCount)",
                        icon: "arrow.up.circle.fill",
                        color: syncModule.pendingCount > 0 ? .orange : .secondary
                    )
                }
                .padding(.horizontal, 24)

                if let lastSync = syncModule.lastSuccessfulSync {
                    Label {
                        Text("Last sync: ") +
                        Text(lastSync, style: .relative) +
                        Text(" ago")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Details button
                Button {
                    showingDetails = true
                } label: {
                    Label("Show Details", systemImage: "info.circle")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)

                Spacer()
                    .frame(height: 16)
            }
        }
        .navigationTitle("Sync")
        .sheet(isPresented: $showingDetails) {
            SyncDetailView()
        }
    }

    // MARK: - Overall Status Logic

    private var overallStatus: OverallStatus {
        if !authModule.isAuthenticated {
            return .warning
        }
        if case .error = syncModule.syncStatus {
            return .error
        }
        if isSyncing {
            return .syncing
        }
        if syncModule.pendingCount > 0 {
            return .pending
        }
        return .ok
    }

    private var isSyncing: Bool {
        if case .syncing = syncModule.syncStatus { return true }
        return false
    }

    private var syncedCount: Int {
        let total = syncModule.pendingCount
        let allCount = (syncModule.transferStatus?.pendingCount ?? 0)
        // Use last successful transfer as a proxy
        if syncModule.lastSuccessfulSync != nil {
            return max(0, allCount)
        }
        return max(0, allCount - total)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch overallStatus {
        case .ok:
            Image(systemName: "checkmark.circle.fill")
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
        case .pending:
            Image(systemName: "arrow.up.circle.fill")
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
        case .error:
            Image(systemName: "xmark.circle.fill")
        }
    }

    private var overallColor: Color {
        switch overallStatus {
        case .ok: .green
        case .syncing: .blue
        case .pending: .orange
        case .warning: .yellow
        case .error: .red
        }
    }

    private var overallHeadline: String {
        switch overallStatus {
        case .ok: "Everything OK"
        case .syncing: "Syncing…"
        case .pending: "Sync Pending"
        case .warning: "Not Connected"
        case .error: "Sync Error"
        }
    }

    private var overallSubtitle: String {
        switch overallStatus {
        case .ok:
            "Your health data is up to date."
        case .syncing:
            if case .syncing(let count) = syncModule.syncStatus {
                "Uploading \(count) item\(count == 1 ? "" : "s")…"
            } else {
                "Upload in progress…"
            }
        case .pending:
            "\(syncModule.pendingCount) item\(syncModule.pendingCount == 1 ? "" : "s") waiting to sync."
        case .warning:
            "Please sign in to start syncing your data."
        case .error:
            syncModule.lastError ?? "An error occurred during synchronization."
        }
    }

    private enum OverallStatus {
        case ok, syncing, pending, warning, error
    }
}


// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}


// MARK: - Detail Sheet

/// Technical detail view shown on a separate sheet.
struct SyncDetailView: View {
    @Environment(ServerSyncModule.self) private var syncModule
    @Environment(ServerAuthModule.self) private var authModule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Connection
                Section("Connection") {
                    row(label: "Authenticated",
                        systemImage: authModule.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill",
                        value: authModule.isAuthenticated ? "Yes" : "No",
                        color: authModule.isAuthenticated ? .green : .red)

                    if let patientId = authModule.patientId {
                        row(label: "Patient ID", systemImage: "person.fill",
                            value: patientId, color: .secondary)
                    }

                    if let url = authModule.clientFacingBaseURL {
                        row(label: "Server", systemImage: "server.rack",
                            value: url.host() ?? url.absoluteString, color: .secondary)
                    }
                }

                // Synchronization
                Section("Synchronization") {
                    row(label: "Status", systemImage: syncIcon,
                        value: syncStatusText, color: syncColor)

                    row(label: "Pending Items", systemImage: "arrow.up.circle",
                        value: "\(syncModule.pendingCount)", color: .secondary)

                    if let lastSync = syncModule.lastSuccessfulSync {
                        HStack {
                            Label("Last Success", systemImage: "clock")
                            Spacer()
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = syncModule.lastError {
                        row(label: "Last Error", systemImage: "exclamationmark.triangle.fill",
                            value: error, color: .red)
                    }
                }

                // Server-side
                if let status = syncModule.transferStatus {
                    Section("Server Status") {
                        row(label: "Successful Transfer",
                            systemImage: status.hasSuccessfulTransfer ? "checkmark.circle.fill" : "xmark.circle",
                            value: status.hasSuccessfulTransfer ? "Yes" : "No",
                            color: status.hasSuccessfulTransfer ? .green : .secondary)

                        if let lastTransfer = status.lastSuccessfulTransfer {
                            HStack {
                                Label("Last Transfer", systemImage: "checkmark.circle")
                                Spacer()
                                Text(lastTransfer, style: .relative)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let pending = status.pendingCount {
                            row(label: "Server Pending", systemImage: "hourglass",
                                value: "\(pending)", color: .secondary)
                        }

                        if let serverError = status.lastError {
                            row(label: "Server Error", systemImage: "exclamationmark.triangle",
                                value: serverError, color: .red)
                        }
                    }
                }

                // Manual Actions
                Section {
                    Button {
                        Task { await syncModule.syncNow() }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!authModule.isAuthenticated || isSyncing)
                }
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Helpers

    private func row(label: String, systemImage: String, value: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer()
            Text(value)
                .foregroundStyle(color)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = syncModule.syncStatus { return true }
        return false
    }

    private var syncIcon: String {
        switch syncModule.syncStatus {
        case .idle: "circle"
        case .syncing: "arrow.triangle.2.circlepath.circle.fill"
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var syncStatusText: String {
        switch syncModule.syncStatus {
        case .idle: "Idle"
        case .syncing(let count): "Syncing \(count) items…"
        case .success: "Success"
        case .error(let msg): msg
        }
    }

    private var syncColor: Color {
        switch syncModule.syncStatus {
        case .idle: .secondary
        case .syncing: .blue
        case .success: .green
        case .error: .red
        }
    }
}
