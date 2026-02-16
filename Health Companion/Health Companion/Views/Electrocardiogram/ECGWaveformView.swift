//
//  ECGWaveformView.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import Charts
import HealthKit
import SpeziHealthKit
import SpeziViews
import SwiftUI


/// A view displaying the ECG waveform chart.
struct ECGWaveformView: View {
    let measurements: [HKElectrocardiogram.Measurement]
    let isLoading: Bool

    var body: some View {
        GroupBox {
            if isLoading {
                ProgressView("Loading ECG data...")
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else if measurements.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "waveform.path.ecg")
                } description: {
                    Text("No voltage measurements available")
                }
                .frame(height: 200)
            } else {
                ecgChart
            }
        } label: {
            Label("ECG Waveform", systemImage: "waveform.path.ecg")
        }
    }

    @ViewBuilder
    private var ecgChart: some View {
        Chart(measurements, id: \.timeOffset) { measurement in
            LineMark(
                x: .value("Time", measurement.timeOffset),
                y: .value("Voltage", measurement.voltage.doubleValue(for: .volt()))
            )
            .foregroundStyle(.red)
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(seconds, specifier: "%.1f")s")
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let voltage = value.as(Double.self) {
                        Text("\(Int(voltage * 1_000_000))µV")
                    }
                }
            }
        }
        .chartYScale(domain: voltageRange)
        .frame(height: 250)
    }

    private var voltageRange: ClosedRange<Double> {
        guard !measurements.isEmpty else { return -0.001...0.001 }
        let voltages = measurements.map { $0.voltage.doubleValue(for: .volt()) }
        let minV = voltages.min() ?? -0.001
        let maxV = voltages.max() ?? 0.001
        let padding = (maxV - minV) * 0.1
        return (minV - padding)...(maxV + padding)
    }
}
