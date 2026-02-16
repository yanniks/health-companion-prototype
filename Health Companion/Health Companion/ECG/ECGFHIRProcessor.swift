//
//  ECGFHIRProcessor.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 23.12.25.
//

import Foundation
import HealthKit
import OSLog
import Spezi
import SpeziFHIR
import SpeziFHIRHealthKit
import SpeziHealthKit


/// A processor that converts ECG samples from HealthKit to FHIR resources.
///
/// This class observes ECG samples collected via SpeziHealthKit's background data collection
/// and converts them to FHIR resources including voltage measurement attachments.
@Observable
final class ECGFHIRProcessor: Sendable {
    private let logger = Logger(subsystem: "HealthCompanion", category: "ECGFHIRProcessor")
    
    /// Converts a single ECG sample to a FHIR resource.
    /// - Parameters:
    ///   - ecg: The `HKElectrocardiogram` sample to convert.
    ///   - healthKit: The `HealthKit` module instance for loading attachments.
    /// - Returns: A `FHIRResource` containing the ECG data.
    func convertToFHIRResource(
        _ ecg: HKElectrocardiogram,
        using healthKit: HealthKit
    ) async throws -> FHIRResource {
        logger.debug("Converting ECG sample \(ecg.uuid) to FHIR resource")
        
        let resource = try await FHIRResource.initialize(
            basedOn: ecg,
            using: healthKit,
            loadHealthKitAttachments: true
        )
        
        logger.info("Successfully converted ECG sample \(ecg.uuid) to FHIR resource")
        return resource
    }
    
    /// Converts multiple ECG samples to FHIR resources.
    /// - Parameters:
    ///   - ecgs: A collection of `HKElectrocardiogram` samples to convert.
    ///   - healthKit: The `HealthKit` module instance for loading attachments.
    /// - Returns: An array of `FHIRResource` instances.
    func convertToFHIRResources(
        _ ecgs: some Collection<HKElectrocardiogram> & Sendable,
        using healthKit: HealthKit
    ) async throws -> [FHIRResource] {
        logger.debug("Converting \(ecgs.count) ECG samples to FHIR resources")
        
        var resources: [FHIRResource] = []
        resources.reserveCapacity(ecgs.count)
        
        for ecg in ecgs {
            do {
                let resource = try await convertToFHIRResource(ecg, using: healthKit)
                resources.append(resource)
            } catch {
                logger.error("Failed to convert ECG sample \(ecg.uuid): \(error.localizedDescription)")
                // Continue processing other samples
            }
        }
        
        logger.info("Successfully converted \(resources.count) of \(ecgs.count) ECG samples to FHIR resources")
        return resources
    }
    
    /// Fetches all ECG samples from a given time range and converts them to FHIR resources.
    /// - Parameters:
    ///   - timeRange: The time range to query ECG samples from.
    ///   - healthKit: The `HealthKit` module instance.
    /// - Returns: An array of `FHIRResource` instances.
    func fetchAndConvertECGs(
        timeRange: HealthKitQueryTimeRange,
        using healthKit: HealthKit
    ) async throws -> [FHIRResource] {
        logger.debug("Fetching ECG samples for time range: \(String(describing: timeRange))")
        
        let ecgSamples: [HKElectrocardiogram] = try await healthKit.query(
            .electrocardiogram,
            timeRange: timeRange
        )
        
        logger.debug("Found \(ecgSamples.count) ECG samples")
        return try await convertToFHIRResources(ecgSamples, using: healthKit)
    }
}
