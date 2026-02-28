//
//  LoginView.swift
//  Health Companion
//
//  Onboarding step that initiates the OAuth 2.0 + PKCE login flow.
//  Maps to: DR5 (Standards-based authentication), DP4 (Security by design)
//

import SpeziOnboarding
import SpeziViews
import SwiftUI

/// An onboarding view that initiates OAuth login via the IAM server.
///
/// Uses `ServerAuthModule` to perform the authorization code + PKCE flow
/// through `ASWebAuthenticationSession`.
struct LoginView: View {
    @Environment(ServerAuthModule.self) private var authModule
    @Environment(ManagedNavigationStack.Path.self) private var managedNavigationPath

    @State private var loginError: String?
    @State private var isLoggingIn = false

    var body: some View {
        OnboardingView(
            content: {
                VStack(spacing: 16) {
                    OnboardingTitleView(
                        title: "Sign In",
                        subtitle: "Authenticate with your health data server"
                    )

                    Spacer()

                    Image(systemName: "person.badge.key.fill")
                        .font(.system(size: 100))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)

                    Text("Sign in to securely transmit your ECG data to your healthcare provider.")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let error = loginError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Spacer()
                }
            },
            footer: {
                OnboardingActionsView(
                    "Sign In",
                    action: {
                        await performLogin()
                    }
                )
                .disabled(isLoggingIn)
                .overlay {
                    if isLoggingIn {
                        ProgressView()
                    }
                }
            }
        )
        .navigationTitle(Text(verbatim: ""))
        .toolbar(.visible)
    }

    private func performLogin() async {
        isLoggingIn = true
        loginError = nil

        do {
            try await authModule.login()
            managedNavigationPath.nextStep()
        } catch {
            loginError = error.localizedDescription
        }

        isLoggingIn = false
    }
}
