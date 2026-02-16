//
// This source file is part of the Stanford Spezi Template Application open-source project
//
// SPDX-FileCopyrightText: 2023 Stanford University
//
// SPDX-License-Identifier: MIT
//

import SpeziHealthKit
import SpeziOnboarding
import SpeziViews
import SwiftUI
import Spezi


/// Displays a multi-step onboarding flow for Health Companion.
///
/// Steps:
/// 1. HealthKit permissions (if available and not yet authorized)
/// 2. Server configuration (IAM + Client-Facing URLs, Patient ID)
/// 3. OAuth login (Authorization Code + PKCE)
struct OnboardingFlow: View {
    @Environment(HealthKit.self) private var healthKit
    @Environment(ServerAuthModule.self) private var authModule

    @AppStorage(StorageKeys.onboardingFlowComplete) private var completedOnboardingFlow = false

    @MainActor private var healthKitAuthorization: Bool {
        // As HealthKit not available in preview simulator
        if ProcessInfo.processInfo.isPreviewSimulator {
            return false
        }
        return healthKit.isFullyAuthorized
    }

    var body: some View {
        ManagedNavigationStack(didComplete: $completedOnboardingFlow) {
            if HKHealthStore.isHealthDataAvailable() && !healthKitAuthorization {
                HealthKitPermissions()
            }

            ServerSetupView()

            if !authModule.isAuthenticated {
                LoginView()
            }
        }
        .interactiveDismissDisabled(!completedOnboardingFlow)
    }
}


#Preview {
    OnboardingFlow()
        .previewWith(standard: HealthCompanionStandard()) {
            HealthKit()
            ServerAuthModule()
        }
}
