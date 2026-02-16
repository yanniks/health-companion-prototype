//
//  SettingsView.swift
//  Health Companion
//
//  Provides settings for server configuration and account management.
//  Maps to: DR4 (Status tracking), DO1 (Minimal configuration)
//

import SwiftUI


/// Settings view for managing server connection and user account.
struct SettingsView: View {
    @Environment(ServerAuthModule.self) private var authModule

    @AppStorage(StorageKeys.iamServerURL) private var iamServerURL = ServerAuthModule.defaultIamServerURL
    @AppStorage(StorageKeys.clientFacingServerURL) private var clientFacingServerURL = ServerAuthModule.defaultClientFacingServerURL

    @State private var showLogoutConfirmation = false

    var body: some View {
        List {
            // Account Section
            Section("Account") {
                HStack {
                    Label("Status", systemImage: authModule.isAuthenticated
                          ? "person.crop.circle.badge.checkmark"
                          : "person.crop.circle.badge.xmark")
                    Spacer()
                    Text(authModule.isAuthenticated ? "Signed In" : "Signed Out")
                        .foregroundColor(authModule.isAuthenticated ? .green : .red)
                }

                if let id = authModule.patientId {
                    HStack {
                        Label("Patient ID", systemImage: "person.text.rectangle")
                        Spacer()
                        Text(id)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if authModule.isAuthenticated {
                    Button(role: .destructive) {
                        showLogoutConfirmation = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
                        Task {
                            try? await authModule.login()
                        }
                    } label: {
                        Label("Sign In", systemImage: "person.badge.key")
                    }
                }
            }

            // Server Configuration
            Section("Server Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IAM Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://localhost:8081", text: $iamServerURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Client-Facing Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("http://localhost:8082", text: $clientFacingServerURL)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign Out",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    await authModule.logout()
                }
            }
        } message: {
            Text("Are you sure you want to sign out? You will need to sign in again to sync data.")
        }
    }
}
