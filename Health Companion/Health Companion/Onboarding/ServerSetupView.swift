//
//  ServerSetupView.swift
//  Health Companion
//
//  Onboarding step for configuring the IAM and Client-Facing server URLs.
//  Maps to: DR4 (Status tracking), DO1 (Minimal configuration effort)
//

import SpeziOnboarding
import SpeziViews
import SwiftUI


/// An onboarding view that collects the server URLs from the user.
///
/// The user enters:
/// - IAM Server URL (e.g. `http://localhost:8081`)
/// - Client-Facing Server URL (e.g. `http://localhost:8082`)
struct ServerSetupView: View {
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath

    @AppStorage(StorageKeys.iamServerURL) private var iamServerURL = ServerAuthModule.defaultIamServerURL
    @AppStorage(StorageKeys.clientFacingServerURL) private var clientFacingServerURL = ServerAuthModule.defaultClientFacingServerURL

    @State private var isValidating = false
    @State private var validationError: String?

    var body: some View {
        OnboardingView(
            content: {
                VStack(spacing: 16) {
                    OnboardingTitleView(
                        title: "Server Configuration",
                        subtitle: "Connect to your health data server"
                    )

                    Spacer()

                    Image(systemName: "server.rack")
                        .font(.system(size: 80))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("IAM Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("http://localhost:8081", text: $iamServerURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)

                        Text("Client-Facing Server URL")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("http://localhost:8082", text: $clientFacingServerURL)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    }
                    .padding(.horizontal)

                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
            },
            footer: {
                OnboardingActionsView(
                    "Continue",
                    action: {
                        guard validateInputs() else { return }
                        managedNavigationPath.nextStep()
                    }
                )
            }
        )
        .navigationTitle(Text(verbatim: ""))
        .toolbar(.visible)
    }

    private func validateInputs() -> Bool {
        validationError = nil

        guard URL(string: iamServerURL) != nil, !iamServerURL.isEmpty else {
            validationError = "Please enter a valid IAM server URL"
            return false
        }
        guard URL(string: clientFacingServerURL) != nil, !clientFacingServerURL.isEmpty else {
            validationError = "Please enter a valid Client-Facing server URL"
            return false
        }
        return true
    }
}
