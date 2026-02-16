//
//  ChartView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import SpeziHealthKit
import SpeziHealthKitUI
import SwiftUI


/// Main view displaying a list of ECG recordings.
struct ChartView: View {
    @HealthKitQuery(.electrocardiogram, timeRange: .last(years: 3)) private var electrocardiograms

    var body: some View {
        List(electrocardiograms) { ecg in
            NavigationLink {
                ElectrocardiogramDetailView(electrocardiogram: ecg)
            } label: {
                ElectrocardiogramCellView(electrocardiogram: ecg)
            }
        }
        .listStyle(.insetGrouped)
    }
}
