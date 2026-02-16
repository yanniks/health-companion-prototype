//
//  ContentView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import SpeziViews
import SwiftUI

struct ContentView: View {
    @AppStorage(StorageKeys.onboardingFlowComplete) var onboardingFlowComplete: Bool = false

    var body: some View {
        TabView {
            Tab("ECG", systemImage: "heart.text.square") {
                NavigationStack {
                    ChartView()
                        .navigationTitle("ECG Recordings")
                }
            }

            Tab("Sync", systemImage: "arrow.triangle.2.circlepath") {
                NavigationStack {
                    SyncStatusView()
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .sheet(isPresented: !$onboardingFlowComplete) {
            OnboardingFlow()
        }
    }
}

#Preview {
    ContentView()
}
