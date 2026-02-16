//
//  Health_CompanionApp.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import Spezi
import SwiftUI

@main
struct Health_CompanionApp: App {
    @ApplicationDelegateAdaptor(HealthCompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .spezi(appDelegate)
        }
    }
}
