//
//  ElectrocardiogramCellView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import HealthKit
import SwiftUI

/// A list cell view displaying summary information about an ECG recording.
struct ElectrocardiogramCellView: View {
    let electrocardiogram: HKElectrocardiogram

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with classification
            Label {
                VStack(alignment: .leading) {
                    Text(classificationTitle)
                        .font(.headline)
                    Text(formattedDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                classificationIcon
                    .foregroundStyle(classificationColor)
            }

            // Details grid
            Grid(alignment: .leading, verticalSpacing: 4) {
                GridRow {
                    Label("Heart Rate", systemImage: "heart.fill")
                        .foregroundStyle(.red)

                    if let heartRate = averageHeartRateBPM {
                        Text("\(Int(heartRate)) BPM")
                            .fontWeight(.medium)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }

                if electrocardiogram.symptomsStatus != .notSet {
                    GridRow {
                        Label("Symptoms", systemImage: "note.text")
                            .foregroundStyle(.orange)

                        Text(symptomsText)
                    }
                }

                GridRow {
                    Label("Samples", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.green)

                    Text("\(electrocardiogram.numberOfVoltageMeasurements)")
                }
            }
            .font(.subheadline)
        }
    }
}

// MARK: - Computed Properties

extension ElectrocardiogramCellView {
    private var averageHeartRateBPM: Double? {
        electrocardiogram.averageHeartRate?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    }

    private var formattedDate: String {
        electrocardiogram.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    private var classificationIcon: Image {
        switch electrocardiogram.classification {
        case .sinusRhythm:
            Image(systemName: "checkmark.circle.fill")
        case .atrialFibrillation:
            Image(systemName: "exclamationmark.triangle.fill")
        case .inconclusiveHighHeartRate, .inconclusiveLowHeartRate:
            Image(systemName: "heart.slash.fill")
        case .inconclusivePoorReading:
            Image(systemName: "waveform.slash")
        case .inconclusiveOther, .unrecognized, .notSet:
            Image(systemName: "questionmark.circle.fill")
        @unknown default:
            Image(systemName: "questionmark.circle.fill")
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
            "Unknown Classification"
        }
    }

    private var symptomsText: String {
        switch electrocardiogram.symptomsStatus {
        case .present:
            "Recorded"
        case .none:
            "None"
        case .notSet:
            "—"
        @unknown default:
            "—"
        }
    }
}
