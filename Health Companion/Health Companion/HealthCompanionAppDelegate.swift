//
//  HealthCompanionAppDelegate.swift
//  Health Companion
//
//  Created by Ehlert, Yannik on 22.12.25.
//

import HealthKit
import OSLog
import Spezi
import SpeziFHIR
import SpeziFoundation
import SpeziHealthKit
import SwiftUI


actor HealthCompanionStandard: Standard, HealthKitConstraint, EnvironmentAccessible {
    private let logger = Logger(subsystem: "HealthCompanion", category: "Standard")
    private let ecgProcessor = ECGFHIRProcessor()
    
    @Dependency(HealthKit.self) private var healthKit
    @Dependency(FHIRStore.self) private var fhirStore

    func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async {
        logger.debug("Received \(addedSamples.count) new samples of type \(sampleType.displayTitle)")

        // Handle ECG samples specifically
        let ecgSamples = addedSamples.compactMap { $0 as? HKElectrocardiogram }
        if !ecgSamples.isEmpty {
            await processECGSamples(ecgSamples)
        }
    }
    
    func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SpeziHealthKit.SampleType<Sample>
    ) async {
        logger.debug("Received \(deletedObjects.count) deleted objects of type \(sampleType.displayTitle)")
    }
    
    private func processECGSamples(_ ecgSamples: [HKElectrocardiogram]) async {
        logger.info("Processing \(ecgSamples.count) ECG samples")
        
        do {
            let fhirResources = try await ecgProcessor.convertToFHIRResources(
                ecgSamples,
                using: healthKit
            )
            
            for resource in fhirResources {
                await fhirStore.insert(resource)
                logger.debug("Inserted FHIR resource: \(resource.displayName)")
            }
            
            logger.info("Successfully processed and stored \(fhirResources.count) ECG FHIR resources")
        } catch {
            logger.error("Failed to process ECG samples: \(error.localizedDescription)")
        }
    }

    @MainActor func configure() {
        Task {
            logger.info("Performing initial ECG data load")
            let ecgs = try await self.healthKit.query(.electrocardiogram, timeRange: .last(years: 3))
            await self.processECGSamples(ecgs)
        }
    }
}

class HealthCompanionAppDelegate: SpeziAppDelegate {
    override var configuration: Configuration {
        Configuration(standard: HealthCompanionStandard()) {
            if HKHealthStore.isHealthDataAvailable() {
                HealthKit {
                    CollectSamples(
                        .electrocardiogram,
                        start: .automatic,
                        continueInBackground: true
                    )
                }
            }
            FHIRStore()
            ServerAuthModule()
            ServerSyncModule()
        }
    }
}
