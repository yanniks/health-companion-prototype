//
//  ElectrocardiogramDetailView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import HealthKit
import SpeziHealthKit
import SpeziViews
import SwiftUI


/// A detail view showing the ECG waveform and recording details.
struct ElectrocardiogramDetailView: View {
    let electrocardiogram: HKElectrocardiogram

    @State private var voltageMeasurements: [HKElectrocardiogram.Measurement] = []
    @State private var viewState: ViewState = .processing

    @Environment(HealthKit.self) private var healthKit

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ECGWaveformView(
                    measurements: voltageMeasurements,
                    isLoading: viewState == .processing
                )

                ECGDetailsView(electrocardiogram: electrocardiogram)
            }
            .padding()
        }
        .navigationTitle("ECG Details")
        .navigationBarTitleDisplayMode(.inline)
        .viewStateAlert(state: $viewState)
        .task {
            await loadVoltageMeasurements()
        }
    }

    private func loadVoltageMeasurements() async {
        viewState = .processing

        do {
            let measurements = try await electrocardiogram.voltageMeasurements(
                from: healthKit.healthStore
            )

            // Downsample for performance if there are too many points
            let maxPoints = 2000
            if measurements.count > maxPoints {
                let stride = measurements.count / maxPoints
                voltageMeasurements = measurements.enumerated()
                    .filter { $0.offset % stride == 0 }
                    .map(\.element)
            } else {
                voltageMeasurements = measurements
            }
            viewState = .idle
        } catch {
            viewState = .error(AnyLocalizedError(error: error))
        }
    }
}
