/// FHIRToGDT - A library for converting FHIR Observations to GDT format
///
/// This module provides the conversion logic between FHIR R4 Observation
/// resources and GDT (Gerätedatentransfer) files.
///
/// ## Overview
///
/// Use `FHIRToGDTConverter` to convert FHIR observations:
///
/// ```swift
/// import FHIRToGDT
/// import ModelsR4
///
/// // Create converter with custom configuration
/// let config = FHIRToGDTConfiguration(
///     outputDirectory: URL(fileURLWithPath: "/path/to/gdt"),
///     senderID: "MY_APP",
///     receiverID: "MEDISTAR"
/// )
/// let converter = FHIRToGDTConverter(configuration: config)
///
/// // Parse FHIR Observation
/// let observation = try JSONDecoder().decode(Observation.self, from: jsonData)
///
/// // Convert to GDT
/// let result = try converter.convert(observation)
/// print(result.document.format())
///
/// // Or convert and write to file
/// let result = try converter.convertAndWrite(observation)
/// print("Written to: \(result.filePath!)")
/// ```

@_exported import GDTKit
@_exported import ModelsR4
