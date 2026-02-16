import Foundation
import ModelsR4
import GDTKit

/// Configuration for the FHIR to GDT converter
public struct FHIRToGDTConfiguration: Sendable {
    /// The GDT version to use
    public let gdtVersion: String
    
    /// The character encoding for GDT files
    public let encoding: GDTEncoding
    
    /// Sender ID for GDT files
    public let senderID: String
    
    /// Receiver ID for GDT files
    public let receiverID: String
    
    /// Output directory for GDT files
    public let outputDirectory: URL
    
    /// File name prefix for generated GDT files
    public let fileNamePrefix: String
    
    /// Default configuration
    public static let `default` = FHIRToGDTConfiguration(
        gdtVersion: "02.10",
        encoding: .latin1,
        senderID: "HEALTH_SERVER",
        receiverID: "PVS",
        outputDirectory: URL(fileURLWithPath: "/tmp/gdt"),
        fileNamePrefix: "obs"
    )
    
    public init(
        gdtVersion: String = "02.10",
        encoding: GDTEncoding = .latin1,
        senderID: String = "HEALTH_SERVER",
        receiverID: String = "PVS",
        outputDirectory: URL,
        fileNamePrefix: String = "obs"
    ) {
        self.gdtVersion = gdtVersion
        self.encoding = encoding
        self.senderID = senderID
        self.receiverID = receiverID
        self.outputDirectory = outputDirectory
        self.fileNamePrefix = fileNamePrefix
    }
}

/// Result of a FHIR to GDT conversion
public struct ConversionResult: Sendable {
    /// The generated GDT document
    public let document: GDTDocument
    
    /// The file path where the document was written (if applicable)
    public let filePath: URL?
    
    /// Any warnings generated during conversion
    public let warnings: [String]
    
    /// The original FHIR observation ID
    public let observationId: String?
}

/// Converts FHIR Observations to GDT documents
public struct FHIRToGDTConverter: Sendable {
    /// The configuration for this converter
    public let configuration: FHIRToGDTConfiguration
    
    /// Initialize a new converter
    /// - Parameter configuration: The conversion configuration
    public init(configuration: FHIRToGDTConfiguration = .default) {
        self.configuration = configuration
    }
    
    /// Convert a FHIR Observation to a GDT document
    /// - Parameter observation: The FHIR Observation to convert
    /// - Returns: The conversion result
    /// - Throws: ConversionError if conversion fails
    public func convert(_ observation: Observation) throws -> ConversionResult {
        var warnings: [String] = []
        
        // Create new GDT document
        var doc = GDTDocument(
            recordType: .newExaminationData,
            encoding: configuration.encoding,
            gdtVersion: configuration.gdtVersion
        )
        
        doc.senderID = configuration.senderID
        doc.receiverID = configuration.receiverID
        
        // Extract observation ID
        let observationId = observation.id?.value?.string
        
        // Add patient data if available
        if let subjectRef = observation.subject {
            addPatientData(from: subjectRef, to: &doc, warnings: &warnings)
        }
        
        // Add examination date/time
        addEffectiveDateTime(from: observation, to: &doc, warnings: &warnings)
        
        // Add test identification
        addTestIdentification(from: observation, to: &doc, warnings: &warnings)
        
        // Add result value
        addResultValue(from: observation, to: &doc, warnings: &warnings)
        
        // Add ECG-specific components if this is an ECG observation
        if isECGObservation(observation) {
            addECGComponents(from: observation, to: &doc, warnings: &warnings)
        }
        
        // Add reference range if available
        addReferenceRange(from: observation, to: &doc, warnings: &warnings)
        
        // Add interpretation/status
        addInterpretation(from: observation, to: &doc, warnings: &warnings)
        
        return ConversionResult(
            document: doc,
            filePath: nil,
            warnings: warnings,
            observationId: observationId
        )
    }
    
    /// Convert and write a FHIR Observation to a GDT file
    /// - Parameter observation: The FHIR Observation to convert
    /// - Returns: The conversion result including the file path
    /// - Throws: ConversionError or file write errors
    public func convertAndWrite(_ observation: Observation) throws -> ConversionResult {
        let result = try convert(observation)
        
        // Generate file name
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let fileName = "\(configuration.fileNamePrefix)_\(timestamp).gdt"
        let filePath = configuration.outputDirectory.appendingPathComponent(fileName)
        
        // Ensure output directory exists
        try FileManager.default.createDirectory(
            at: configuration.outputDirectory,
            withIntermediateDirectories: true
        )
        
        // Write the document
        try result.document.write(to: filePath)
        
        return ConversionResult(
            document: result.document,
            filePath: filePath,
            warnings: result.warnings,
            observationId: result.observationId
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func addPatientData(from reference: Reference, to doc: inout GDTDocument, warnings: inout [String]) {
        // Extract patient ID from reference
        if let refString = reference.reference?.value?.string {
            // Reference format might be "Patient/12345" or just "12345"
            let patientId = refString.components(separatedBy: "/").last ?? refString
            doc.addField(.patientID, content: patientId)
        }
        
        // If display name is available, try to parse it
        if let display = reference.display?.value?.string {
            // Try to parse "LastName, FirstName" format
            let components = display.components(separatedBy: ", ")
            if components.count >= 2 {
                doc.addField(.lastName, content: components[0])
                doc.addField(.firstName, content: components[1])
            } else {
                // Just use the whole display as last name
                doc.addField(.lastName, content: display)
            }
        }
    }
    
    private func addEffectiveDateTime(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        // Handle different effective[x] types
        switch observation.effective {
        case .dateTime(let fhirDateTime):
            if let date = try? fhirDateTime.value?.asNSDate() as? Date {
                doc.addField(.examinationDate, date: date)
                doc.addTimeField(.examinationTime, time: date)
            }
        case .period(let period):
            // Use start of period
            if let date = try? period.start?.value?.asNSDate() as? Date {
                doc.addField(.examinationDate, date: date)
                doc.addTimeField(.examinationTime, time: date)
            }
        case .instant(let instant):
            if let date = try? instant.value?.asNSDate() as? Date {
                doc.addField(.examinationDate, date: date)
                doc.addTimeField(.examinationTime, time: date)
            }
        case .timing(_):
            warnings.append("Timing effective type not fully supported")
        case .none:
            // Use current date/time as fallback
            let now = Date()
            doc.addField(.examinationDate, date: now)
            doc.addTimeField(.examinationTime, time: now)
            warnings.append("No effective date/time in observation, using current time")
        }
    }
    
    private func addTestIdentification(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        let code = observation.code
        
        // Get coding(s) from the code
        if let codings = code.coding {
            for coding in codings {
                // Add test identifier (code)
                if let codeValue = coding.code?.value?.string {
                    doc.addField(.testIdentifier, content: codeValue)
                }
                
                // Add test name (display)
                if let display = coding.display?.value?.string {
                    // Use short form if under 20 chars, otherwise truncate for short name
                    if display.count <= 20 {
                        doc.addField(.testNameShort, content: display)
                    } else {
                        doc.addField(.testNameShort, content: String(display.prefix(20)))
                    }
                    // Always add full name as long name
                    doc.addField(.testNameLong, content: display)
                }
                
                // Only use first coding
                break
            }
        }
        
        // Also add text if available
        if let text = code.text?.value?.string {
            doc.addField(.testNameLong, content: text)
        }
    }
    
    private func addResultValue(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        guard let value = observation.value else {
            warnings.append("Observation has no value")
            return
        }
        
        switch value {
        case .quantity(let quantity):
            // Numeric value with unit
            if let numValue = quantity.value?.value?.decimal {
                let doubleValue = NSDecimalNumber(decimal: numValue).doubleValue
                doc.addField(.resultValue, decimalValue: doubleValue)
            }
            if let unit = quantity.unit?.value?.string {
                doc.addField(.unit, content: unit)
            } else if let code = quantity.code?.value?.string {
                doc.addField(.unit, content: code)
            }
            
        case .codeableConcept(let cc):
            // Coded value
            if let text = cc.text?.value?.string {
                doc.addField(.resultText, content: text)
            } else if let coding = cc.coding?.first, let display = coding.display?.value?.string {
                doc.addField(.resultText, content: display)
            }
            
        case .string(let str):
            if let value = str.value?.string {
                doc.addField(.resultText, content: value)
            }
            
        case .boolean(let bool):
            if let value = bool.value?.bool {
                doc.addField(.resultText, content: value ? "Positiv" : "Negativ")
            }
            
        case .integer(let int):
            if let value = int.value?.integer {
                doc.addField(.resultValue, intValue: Int(value))
            }
            
        case .range(let range):
            var rangeText = ""
            if let low = range.low?.value?.value?.decimal {
                rangeText += "\(low)"
            }
            rangeText += " - "
            if let high = range.high?.value?.value?.decimal {
                rangeText += "\(high)"
            }
            doc.addField(.resultText, content: rangeText)
            
        case .ratio(let ratio):
            var ratioText = ""
            if let num = ratio.numerator?.value?.value?.decimal {
                ratioText += "\(num)"
            }
            ratioText += "/"
            if let denom = ratio.denominator?.value?.value?.decimal {
                ratioText += "\(denom)"
            }
            doc.addField(.resultText, content: ratioText)
            
        case .sampledData(_):
            warnings.append("SampledData value type not supported for GDT conversion")
            
        case .time(let time):
            if let value = time.value?.description {
                doc.addField(.resultText, content: value)
            }
            
        case .dateTime(let dt):
            if let date = try? dt.value?.asNSDate() as? Date {
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM.yyyy HH:mm"
                doc.addField(.resultText, content: formatter.string(from: date))
            }
            
        case .period(let period):
            var periodText = ""
            if let start = period.start?.value?.description {
                periodText += start
            }
            periodText += " - "
            if let end = period.end?.value?.description {
                periodText += end
            }
            doc.addField(.resultText, content: periodText)
        }
    }
    
    private func addReferenceRange(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        guard let ranges = observation.referenceRange, !ranges.isEmpty else {
            return
        }
        
        // Use the first reference range
        let range = ranges[0]
        
        // Add lower bound
        if let low = range.low?.value?.value?.decimal {
            doc.addField(.normalRangeLower, content: "\(low)")
        }
        
        // Add upper bound
        if let high = range.high?.value?.value?.decimal {
            doc.addField(.normalRangeUpper, content: "\(high)")
        }
        
        // Add text if available
        if let text = range.text?.value?.string {
            doc.addField(.normalRangeText, content: text)
        } else {
            // Generate text from low-high
            var rangeText = ""
            if let low = range.low?.value?.value?.decimal {
                rangeText += "\(low)"
            }
            rangeText += " - "
            if let high = range.high?.value?.value?.decimal {
                rangeText += "\(high)"
            }
            if !rangeText.trimmingCharacters(in: .whitespaces).isEmpty && rangeText != " - " {
                doc.addField(.normalRangeText, content: rangeText)
            }
        }
    }
    
    private func addInterpretation(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        // Add observation status
        let status = observation.status.value?.rawValue ?? "unknown"
        doc.addField(.testStatus, content: status)
        
        // Add interpretation if available
        if let interpretations = observation.interpretation, !interpretations.isEmpty {
            let interpretation = interpretations[0]
            
            if let text = interpretation.text?.value?.string {
                doc.addField(.resultStatus, content: text)
            } else if let coding = interpretation.coding?.first {
                // Map common interpretation codes to GDT status
                if let code = coding.code?.value?.string {
                    let gdtStatus = mapInterpretationCode(code)
                    doc.addField(.resultStatus, content: gdtStatus)
                }
            }
        }
    }
    
    private func mapInterpretationCode(_ code: String) -> String {
        // Map HL7 v2 interpretation codes to German text
        switch code.uppercased() {
        case "N":
            return "Normal"
        case "H":
            return "Erhöht"
        case "L":
            return "Erniedrigt"
        case "HH", "HU":
            return "Stark erhöht"
        case "LL", "LU":
            return "Stark erniedrigt"
        case "A":
            return "Abnormal"
        case "AA":
            return "Stark abnormal"
        case "U":
            return "Erhöht"
        case "D":
            return "Erniedrigt"
        case "B":
            return "Besser"
        case "W":
            return "Schlechter"
        case "S":
            return "Empfindlich"
        case "R":
            return "Resistent"
        case "I":
            return "Intermediär"
        case "POS":
            return "Positiv"
        case "NEG":
            return "Negativ"
        default:
            return code
        }
    }
    
    // MARK: - ECG Support
    
    /// Known LOINC / MDC codes for ECG observations
    private static let ecgLoincCodes: Set<String> = [
        "11524-6",  // ECG study
        "34534-8",  // 12 lead ECG
        "131328",   // MDC code for ECG
        "8867-4",   // Heart rate
        "76282-3",  // Heart rate by ECG
        "8625-6",   // P-R interval
        "8633-0",   // QRS duration
        "8634-8",   // QT interval
        "8636-3",   // QTc interval
        "76513-1",  // R-R interval
        "8626-4",   // P wave duration
        "131329",   // MDC ECG lead data
        "18844-5",  // ECG impression
        "67925",    // Number of voltage measurements (MDC)
        "68220",    // Sampling frequency (MDC)
    ]

    /// HealthKit-specific codes that also indicate ECG data (backward compat)
    private static let healthKitECGCodes: Set<String> = [
        "HKElectrocardiogram",
        "HKElectrocardiogram.Classification",
        "HKElectrocardiogram.NumberOfVoltageMeasurements",
        "HKElectrocardiogram.SamplingFrequency",
        "HKElectrocardiogram.SymptomsStatus",
    ]
    
    /// Check if the observation is an ECG observation
    private func isECGObservation(_ observation: Observation) -> Bool {
        guard let codings = observation.code.coding else {
            return false
        }
        
        for coding in codings {
            if let code = coding.code?.value?.string {
                if Self.ecgLoincCodes.contains(code) || Self.healthKitECGCodes.contains(code) {
                    return true
                }
            }
            
            // Check display text for ECG keywords
            if let displayValue = coding.display?.value?.string {
                let display = displayValue.lowercased()
                if display.contains("ecg") || display.contains("ekg") ||
                   display.contains("electrocardiogram") || display.contains("elektrokardiogramm") {
                    return true
                }
            }
        }
        
        // Check code text
        if let textValue = observation.code.text?.value?.string {
            let text = textValue.lowercased()
            if text.contains("ecg") || text.contains("ekg") ||
               text.contains("electrocardiogram") || text.contains("elektrokardiogramm") {
                return true
            }
        }
        
        // Check if any components are ECG-related
        if let components = observation.component {
            for component in components {
                if let codings = component.code.coding {
                    for coding in codings {
                        if let code = coding.code?.value?.string,
                           Self.ecgLoincCodes.contains(code) || Self.healthKitECGCodes.contains(code) {
                            return true
                        }
                    }
                }
            }
        }
        
        return false
    }
    
    /// Add ECG-specific component values to the GDT document
    private func addECGComponents(from observation: Observation, to doc: inout GDTDocument, warnings: inout [String]) {
        guard let components = observation.component else {
            return
        }
        
        for component in components {
            addECGComponent(component, to: &doc, warnings: &warnings)
        }
        
        // Add ECG interpretation if available in the main observation
        if let interpretations = observation.interpretation, !interpretations.isEmpty {
            if let text = interpretations.first?.text?.value?.string {
                doc.addField(.ecgInterpretation, content: text)
            }
        }
        
        // Add any note as ECG interpretation
        if let notes = observation.note {
            for note in notes {
                if let text = note.text.value?.string {
                    doc.addField(.ecgInterpretation, content: text)
                    break // Only add first note
                }
            }
        }
    }
    
    /// Add a single ECG component value
    private func addECGComponent(_ component: ObservationComponent, to doc: inout GDTDocument, warnings: inout [String]) {
        // Get the component coding
        guard let coding = component.code.coding?.first else {
            return
        }
        
        // Get code if available (may be nil for display-only components)
        let code = coding.code?.value?.string ?? ""
        
        // Map LOINC / MDC / HealthKit codes to GDT fields
        // Only verified GDT 2.1 field identifiers are used; everything else → freeText (6228)
        let fieldMapping: [String: GDTFieldIdentifier] = [
            "8867-4": .ecgHeartRate,       // Heart rate (LOINC)
            "76282-3": .ecgHeartRate,      // Heart rate by ECG (LOINC)
            "8626-4": .freeText,           // P wave duration
            "8625-6": .freeText,           // P-R interval (PQ)
            "8633-0": .freeText,           // QRS duration
            "8634-8": .freeText,           // QT interval
            "8636-3": .freeText,           // QTc interval
            "76513-1": .freeText,          // R-R interval
            "18844-5": .ecgInterpretation, // ECG impression / classification (LOINC)
            "67925": .freeText,            // Number of voltage measurements (MDC)
            "68220": .freeText,            // Sampling frequency (MDC)
            // HealthKit-specific codes (backward compatibility)
            "HKElectrocardiogram.Classification": .ecgInterpretation,
            "HKElectrocardiogram.NumberOfVoltageMeasurements": .freeText,
            "HKElectrocardiogram.SamplingFrequency": .freeText,
            "HKElectrocardiogram.SymptomsStatus": .freeText,
        ]
        
        // Check display text for additional mappings
        let displayLower = (coding.display?.value?.string ?? "").lowercased()
        
        // Determine the appropriate GDT field
        var gdtField: GDTFieldIdentifier?
        
        if let mappedField = fieldMapping[code] {
            gdtField = mappedField
        } else if displayLower.contains("heart rate") || displayLower.contains("herzfrequenz") {
            gdtField = .ecgHeartRate
        } else if displayLower.contains("impression") || displayLower.contains("classification")
                    || displayLower.contains("befund") {
            gdtField = .ecgInterpretation
        } else if displayLower.contains("p wave") || displayLower.contains("p-dauer")
                    || displayLower.contains("pr interval") || displayLower.contains("pq")
                    || displayLower.contains("qrs") || displayLower.contains("qtc")
                    || displayLower.contains("qt interval") || displayLower.contains("qt-")
                    || displayLower.contains("rr interval") || displayLower.contains("r-r")
                    || displayLower.contains("axis") || displayLower.contains("achse")
                    || displayLower.contains("rhythm") || displayLower.contains("rhythmus")
                    || displayLower.contains("sampling") || displayLower.contains("abtastrate")
                    || displayLower.contains("number of") || displayLower.contains("anzahl")
                    || displayLower.contains("symptom") {
            gdtField = .freeText
        }
        
        // If we found a matching field, add the value
        if let field = gdtField {
            if let value = component.value {
                let displayName = coding.display?.value?.string ?? code
                switch value {
                case .quantity(let quantity):
                    if let numValue = quantity.value?.value?.decimal {
                        let doubleValue = NSDecimalNumber(decimal: numValue).doubleValue
                        let unitStr = quantity.unit?.value?.string ?? quantity.code?.value?.string
                        if field == .ecgHeartRate {
                            doc.addField(field, intValue: Int(doubleValue))
                        } else if field == .freeText {
                            // Metadata fields: include label, value and unit
                            let unitSuffix = unitStr.map { " \($0)" } ?? ""
                            doc.addField(field, content: "\(displayName): \(Int(doubleValue))\(unitSuffix)")
                        } else {
                            doc.addField(field, decimalValue: doubleValue, precision: 1)
                        }
                        // Add unit for non-freetext numeric fields
                        if field != .freeText && field != .ecgHeartRate, let unit = unitStr {
                            doc.addField(.unit, content: unit)
                        }
                    }
                case .string(let str):
                    if let stringValue = str.value?.string {
                        // Map ECG classification values to German-language labels
                        let mapped = field == .ecgInterpretation
                            ? Self.mapClassificationToGerman(stringValue)
                            : stringValue
                        doc.addField(field, content: mapped)
                    }
                case .codeableConcept(let cc):
                    if let text = cc.text?.value?.string {
                        doc.addField(field, content: text)
                    } else if let display = cc.coding?.first?.display?.value?.string {
                        doc.addField(field, content: display)
                    }
                case .integer(let int):
                    if let intValue = int.value?.integer {
                        if field == .freeText {
                            doc.addField(field, content: "\(displayName): \(intValue)")
                        } else {
                            doc.addField(field, intValue: Int(intValue))
                        }
                    }
                default:
                    warnings.append("Unsupported ECG component value type for \(code)")
                }
            }
        } else {
            // Log unrecognized ECG component
            let displayName = coding.display?.value?.string ?? code
            warnings.append("Unrecognized ECG component: \(displayName)")
        }
    }

    /// Maps ECG classification raw values (from HealthKit or normalised labels)
    /// to German-language descriptions suitable for GDT output.
    private static func mapClassificationToGerman(_ value: String) -> String {
        let mapping: [String: String] = [
            // Raw HealthKit enum values (backward compatibility)
            "sinusRhythm": "Sinusrhythmus",
            "atrialFibrillation": "Vorhofflimmern",
            "inconclusiveHighHeartRate": "Nicht eindeutig – hohe Herzfrequenz",
            "inconclusiveLowHeartRate": "Nicht eindeutig – niedrige Herzfrequenz",
            "inconclusivePoorReading": "Nicht eindeutig – schlechte Ablesung",
            "inconclusiveOther": "Nicht eindeutig",
            "unrecognized": "Nicht erkannt",
            "notSet": "Nicht gesetzt",
            // Normalised English labels (from FHIRBundleBuilder)
            "Sinus Rhythm": "Sinusrhythmus",
            "Atrial Fibrillation": "Vorhofflimmern",
            "Inconclusive – High Heart Rate": "Nicht eindeutig – hohe Herzfrequenz",
            "Inconclusive – Low Heart Rate": "Nicht eindeutig – niedrige Herzfrequenz",
            "Inconclusive – Poor Reading": "Nicht eindeutig – schlechte Ablesung",
            "Inconclusive": "Nicht eindeutig",
            "Unrecognized": "Nicht erkannt",
            "Not Set": "Nicht gesetzt",
        ]
        return mapping[value] ?? value
    }
}

// MARK: - Conversion Errors

public enum ConversionError: Error, Sendable {
    case missingRequiredField(String)
    case invalidValue(String)
    case unsupportedValueType(String)
    case patientResolutionFailed
}

extension ConversionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidValue(let message):
            return "Invalid value: \(message)"
        case .unsupportedValueType(let type):
            return "Unsupported value type: \(type)"
        case .patientResolutionFailed:
            return "Failed to resolve patient reference"
        }
    }
}
