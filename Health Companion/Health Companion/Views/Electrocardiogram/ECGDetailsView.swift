//
//  ECGDetailsView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import HealthKit
import SwiftUI

/// A view displaying detailed information about an ECG recording.
struct ECGDetailsView: View {
    let electrocardiogram: HKElectrocardiogram

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, verticalSpacing: 12) {
                GridRow {
                    Text("Classification")
                        .foregroundStyle(.secondary)
                    Text(classificationTitle)
                        .fontWeight(.medium)
                        .foregroundStyle(classificationColor)
                }

                Divider()

                GridRow {
                    Text("Date")
                        .foregroundStyle(.secondary)
                    Text(electrocardiogram.startDate.formatted(date: .long, time: .shortened))
                }

                Divider()

                if let heartRate = electrocardiogram.averageHeartRate {
                    GridRow {
                        Text("Average Heart Rate")
                            .foregroundStyle(.secondary)
                        Text("\(Int(heartRate.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))) BPM")
                    }

                    Divider()
                }

                if let frequency = electrocardiogram.samplingFrequency {
                    GridRow {
                        Text("Sampling Frequency")
                            .foregroundStyle(.secondary)
                        Text("\(Int(frequency.doubleValue(for: .hertz()))) Hz")
                    }

                    Divider()
                }

                GridRow {
                    Text("Voltage Measurements")
                        .foregroundStyle(.secondary)
                    Text("\(electrocardiogram.numberOfVoltageMeasurements)")
                }

                if electrocardiogram.symptomsStatus != .notSet {
                    Divider()

                    GridRow {
                        Text("Symptoms")
                            .foregroundStyle(.secondary)
                        Text(electrocardiogram.symptomsStatus == .present ? "Recorded" : "None")
                    }
                }
            }
        } label: {
            Label("Recording Details", systemImage: "info.circle")
        }
    }
}

// MARK: - Computed Properties

extension ECGDetailsView {
    private var classificationTitle: String {
        switch electrocardiogram.classification {
        case .sinusRhythm:
            "Sinus Rhythm"
        case .atrialFibrillation:
            "Atrial Fibrillation"
        case .inconclusiveHighHeartRate:
            "Inconclusive – High Heart Rate"
        case .inconclusiveLowHeartRate:
            "Inconclusive – Low Heart Rate"
        case .inconclusivePoorReading:
            "Inconclusive – Poor Reading"
        case .inconclusiveOther:
            "Inconclusive"
        case .unrecognized:
            "Unrecognized"
        case .notSet:
            "Not Classified"
        @unknown default:
            "Unknown"
        }
    }

    private var classificationColor: Color {
        switch electrocardiogram.classification {
        case .sinusRhythm:
            .green
        case .atrialFibrillation:
            .red
        case .inconclusiveHighHeartRate, .inconclusiveLowHeartRate, .inconclusivePoorReading, .inconclusiveOther:
            .orange
        case .unrecognized, .notSet:
            .secondary
        @unknown default:
            .secondary
        }
    }
}
