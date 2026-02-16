import Testing
@testable import FHIRToGDT
@testable import GDTKit
import ModelsR4
import Foundation

@Suite("FHIR to GDT Converter Tests")
struct FHIRToGDTConverterTests {
    
    @Test("Converter initialization with default config")
    func converterInitialization() {
        let converter = FHIRToGDTConverter()
        #expect(converter.configuration.gdtVersion == "02.10")
        #expect(converter.configuration.encoding == .latin1)
    }
    
    @Test("Converter initialization with custom config")
    func converterCustomConfig() {
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            senderID: "MY_APP",
            receiverID: "MEDISTAR",
            outputDirectory: URL(fileURLWithPath: "/custom/path")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        #expect(converter.configuration.gdtVersion == "02.10")
        #expect(converter.configuration.senderID == "MY_APP")
    }
    
    @Test("Convert simple observation with quantity value")
    func convertQuantityObservation() throws {
        let observation = createTestObservation(
            code: "15074-8",
            codeDisplay: "Glucose",
            value: 95.5,
            unit: "mg/dL"
        )
        
        let config = FHIRToGDTConfiguration(
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        
        #expect(result.document.recordType == .newExaminationData)
        
        let formatted = result.document.format()
        #expect(formatted.contains("Glucose"))
        #expect(formatted.contains("95.50"))
        #expect(formatted.contains("mg/dL"))
    }
    
    @Test("Convert observation with patient reference")
    func convertObservationWithPatient() throws {
        let observation = createTestObservationWithPatient(
            patientId: "12345",
            patientName: "Mustermann, Max"
        )
        
        let config = FHIRToGDTConfiguration(
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("12345"))
        #expect(formatted.contains("Mustermann"))
        #expect(formatted.contains("Max"))
    }
    
    @Test("Convert observation with reference range")
    func convertObservationWithReferenceRange() throws {
        let observation = createTestObservationWithRange(
            code: "2339-0",
            display: "Glucose",
            value: 110.0,
            unit: "mg/dL",
            lowRange: 70.0,
            highRange: 100.0
        )
        
        let config = FHIRToGDTConfiguration(
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("70"))
        #expect(formatted.contains("100"))
    }
    
    @Test("Convert observation without value generates warning")
    func convertObservationWithoutValue() throws {
        let observation = Observation(
            code: CodeableConcept(
                coding: [Coding(
                    code: FHIRPrimitive<FHIRString>(FHIRString("15074-8")),
                    display: FHIRPrimitive<FHIRString>(FHIRString("Glucose"))
                )]
            ),
            status: FHIRPrimitive<ObservationStatus>(.final)
        )
        
        let config = FHIRToGDTConfiguration(
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        
        #expect(result.warnings.contains { $0.contains("no value") })
    }
    
    // MARK: - Test Helpers
    
    func createTestObservation(code: String, codeDisplay: String, value: Double, unit: String) -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString(code)),
                        display: FHIRPrimitive<FHIRString>(FHIRString(codeDisplay)),
                        system: FHIRPrimitive<FHIRURI>(FHIRURI(stringLiteral: "http://loinc.org"))
                    )
                ]
            ),
            status: FHIRPrimitive<ObservationStatus>(.final),
            value: .quantity(Quantity(
                code: FHIRPrimitive<FHIRString>(FHIRString(unit)),
                system: FHIRPrimitive<FHIRURI>(FHIRURI(stringLiteral: "http://unitsofmeasure.org")),
                unit: FHIRPrimitive<FHIRString>(FHIRString(unit)),
                value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(value)))
            ))
        )
    }
    
    func createTestObservationWithPatient(patientId: String, patientName: String) -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString("15074-8")),
                        display: FHIRPrimitive<FHIRString>(FHIRString("Glucose"))
                    )
                ]
            ),
            status: FHIRPrimitive<ObservationStatus>(.final),
            subject: Reference(
                display: FHIRPrimitive<FHIRString>(FHIRString(patientName)),
                reference: FHIRPrimitive<FHIRString>(FHIRString("Patient/\(patientId)"))
            ),
            value: .quantity(Quantity(
                unit: FHIRPrimitive<FHIRString>(FHIRString("mg/dL")),
                value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(100.0)))
            ))
        )
    }
    
    func createTestObservationWithRange(code: String, display: String, value: Double, unit: String, lowRange: Double, highRange: Double) -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString(code)),
                        display: FHIRPrimitive<FHIRString>(FHIRString(display))
                    )
                ]
            ),
            referenceRange: [
                ObservationReferenceRange(
                    high: Quantity(value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(highRange)))),
                    low: Quantity(value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(lowRange))))
                )
            ],
            status: FHIRPrimitive<ObservationStatus>(.final),
            value: .quantity(Quantity(
                unit: FHIRPrimitive<FHIRString>(FHIRString(unit)),
                value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(value)))
            ))
        )
    }
}

@Suite("FHIR Configuration Tests")
struct FHIRToGDTConfigurationTests {
    
    @Test("Default configuration values")
    func defaultConfiguration() {
        let config = FHIRToGDTConfiguration.default
        
        #expect(config.gdtVersion == "02.10")
        #expect(config.encoding == .latin1)
        #expect(config.senderID == "HEALTH_SERVER")
        #expect(config.receiverID == "PVS")
    }
    
    @Test("Custom configuration")
    func customConfiguration() {
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            senderID: "MY_SENDER",
            receiverID: "MY_RECEIVER",
            outputDirectory: URL(fileURLWithPath: "/custom/path"),
            fileNamePrefix: "custom"
        )
        
        #expect(config.gdtVersion == "02.10")
        #expect(config.encoding == .latin1)
        #expect(config.senderID == "MY_SENDER")
        #expect(config.receiverID == "MY_RECEIVER")
        #expect(config.fileNamePrefix == "custom")
    }
}

// MARK: - ECG GDT 2.1 Tests

@Suite("ECG GDT 2.1 Tests")
struct ECGGDT21Tests {
    
    @Test("Convert ECG observation with heart rate for GDT 2.1")
    func convertECGHeartRateGDT21() throws {
        let observation = createECGObservation(
            heartRate: 72,
            qrsDuration: 98,
            qtInterval: 420,
            qtcInterval: 440
        )
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("02.10"))
        #expect(formatted.contains("72"))
        #expect(formatted.contains("98"))
        #expect(formatted.contains("420"))
        #expect(formatted.contains("440"))
        #expect(formatted.contains("ECG") || formatted.contains("EKG") || formatted.contains("11524-6"))
    }
    
    @Test("Convert full 12-lead ECG for GDT 2.1")
    func convertFull12LeadECGGDT21() throws {
        let observation = createFull12LeadECGObservation()
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("02.10"))
        #expect(formatted.contains("75"))
        #expect(formatted.contains("110"))
        #expect(formatted.contains("160"))
        #expect(formatted.contains("92"))
        #expect(formatted.contains("400"))
        #expect(formatted.contains("430"))
    }
    
    @Test("ECG with interpretation for GDT 2.1")
    func convertECGWithInterpretationGDT21() throws {
        let observation = createECGObservationWithInterpretation(
            interpretation: "Sinusrhythmus, normale EKG-Befunde"
        )
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("Sinusrhythmus"))
    }
    
    // MARK: - GDT 2.1 Test Helpers
    
    func createECGObservation(heartRate: Int, qrsDuration: Int, qtInterval: Int, qtcInterval: Int) -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString("11524-6")),
                        display: FHIRPrimitive<FHIRString>(FHIRString("ECG study")),
                        system: FHIRPrimitive<FHIRURI>(FHIRURI(stringLiteral: "http://loinc.org"))
                    )
                ],
                text: FHIRPrimitive<FHIRString>(FHIRString("12-lead ECG"))
            ),
            component: [
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8867-4")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("Heart rate")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("/min")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(heartRate)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8633-0")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QRS duration")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(qrsDuration)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8634-8")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QT interval")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(qtInterval)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8636-3")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QTc interval")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(qtcInterval)))
                    ))
                )
            ],
            status: FHIRPrimitive<ObservationStatus>(.final)
        )
    }
    
    func createFull12LeadECGObservation() -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString("34534-8")),
                        display: FHIRPrimitive<FHIRString>(FHIRString("12 lead ECG panel")),
                        system: FHIRPrimitive<FHIRURI>(FHIRURI(stringLiteral: "http://loinc.org"))
                    )
                ]
            ),
            component: [
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8867-4")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("Heart rate")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("/min")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(75)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8626-4")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("P wave duration")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(110)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8625-6")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("PR interval")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(160)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8633-0")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QRS duration")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(92)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8634-8")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QT interval")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(400)))
                    ))
                ),
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8636-3")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("QTc interval")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("ms")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(430)))
                    ))
                )
            ],
            status: FHIRPrimitive<ObservationStatus>(.final)
        )
    }
    
    func createECGObservationWithInterpretation(interpretation: String) -> Observation {
        return Observation(
            code: CodeableConcept(
                coding: [
                    Coding(
                        code: FHIRPrimitive<FHIRString>(FHIRString("11524-6")),
                        display: FHIRPrimitive<FHIRString>(FHIRString("ECG study"))
                    )
                ]
            ),
            component: [
                ObservationComponent(
                    code: CodeableConcept(coding: [
                        Coding(code: FHIRPrimitive<FHIRString>(FHIRString("8867-4")),
                               display: FHIRPrimitive<FHIRString>(FHIRString("Heart rate")))
                    ]),
                    value: .quantity(Quantity(
                        unit: FHIRPrimitive<FHIRString>(FHIRString("/min")),
                        value: FHIRPrimitive<FHIRDecimal>(FHIRDecimal(Decimal(68)))
                    ))
                )
            ],
            note: [
                Annotation(text: FHIRPrimitive<FHIRString>(FHIRString(interpretation)))
            ],
            status: FHIRPrimitive<ObservationStatus>(.final)
        )
    }
}

// MARK: - Apple Watch ECG Full GDT 2.1 Validation Tests

@Suite("Apple Watch ECG Full GDT 2.1 Validation Tests")
struct AppleWatchECGFullGDTTests {
    
    static let appleWatchECGJSON = """
    {
      "resourceType" : "Observation",
      "id" : "B55DB2DD-8929-4F4C-B498-778EFAC66902",
      "identifier" : [{ "id" : "B55DB2DD-8929-4F4C-B498-778EFAC66902" }],
      "code" : {
        "coding" : [
          { "display" : "Electrocardiogram", "system" : "http://developer.apple.com/documentation/healthkit", "code" : "HKElectrocardiogram" },
          { "display" : "MDC_ECG_ELEC_POTL", "system" : "urn:oid:2.16.840.1.113883.6.24", "code" : "131328" }
        ]
      },
      "category" : [{ "coding" : [{ "display" : "Procedure", "system" : "http://terminology.hl7.org/CodeSystem/observation-category", "code" : "procedure" }] }],
      "status" : "final",
      "effectivePeriod" : { "end" : "2023-01-14T22:51:42+01:00", "start" : "2023-01-14T22:51:12+01:00" },
      "issued" : "2025-12-22T18:52:36+01:00",
      "component" : [{
        "valueSampledData" : { "origin" : { "value" : 0, "code" : "uV", "system" : "http://unitsofmeasure.org", "unit" : "uV" }, "dimensions" : 1, "period" : 1.953125, "data" : "60.750 362.972 365.192" },
        "code" : { "coding" : [{ "display" : "MDC_ECG_ELEC_POTL_I", "code" : "131329", "system" : "urn:oid:2.16.840.1.113883.6.24" }] }
      }]
    }
    """
    
    @Test("Full GDT 2.1 output validation for Apple Watch ECG")
    func validateFullGDT21Output() throws {
        let observation = try parseAppleWatchECGObservation()
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            senderID: "HEALTHSERVER",
            receiverID: "MEDISTAR",
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("8000"))
        #expect(formatted.contains("6310"))
        #expect(formatted.contains("9218"))
        #expect(formatted.contains("02.10"))
        #expect(formatted.contains("HEALTHSERVER"))
        #expect(formatted.contains("MEDISTAR"))
        #expect(formatted.contains("6200"))
        #expect(formatted.contains("14012023"))
        #expect(formatted.contains("6201"))
        #expect(formatted.contains("8402"))
        #expect(formatted.contains("HKElectrocardiogram") || formatted.contains("131328"))
        
        let lines = formatted.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        for line in lines {
            #expect(line.count >= 7, "Line too short: \(line)")
            let lengthPrefix = String(line.prefix(3))
            #expect(Int(lengthPrefix) != nil, "Invalid length prefix: \(lengthPrefix)")
        }
    }
    
    @Test("Apple Watch ECG with effectivePeriod generates correct date")
    func effectivePeriodGeneratesCorrectDate() throws {
        let observation = try parseAppleWatchECGObservation()
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        #expect(formatted.contains("14012023"))
        #expect(formatted.contains("225112"))
    }
    
    @Test("GDT line length calculation is correct")
    func gdtLineLengthCalculationCorrect() throws {
        let observation = try parseAppleWatchECGObservation()
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        
        let lines = formatted.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        for line in lines {
            let declaredLength = Int(String(line.prefix(3))) ?? 0
            let actualLength = line.count + 2
            #expect(declaredLength == actualLength,
                   "Line length mismatch: declared=\(declaredLength), actual=\(actualLength) for line: \(line)")
        }
    }
    
    @Test("GDT 2.1 complete document structure validation")
    func gdt21CompleteStructure() throws {
        let observation = try parseAppleWatchECGObservation()
        
        let config = FHIRToGDTConfiguration(
            gdtVersion: "02.10",
            encoding: .latin1,
            senderID: "TEST_SENDER",
            receiverID: "TEST_RECEIVER",
            outputDirectory: URL(fileURLWithPath: "/tmp/test")
        )
        let converter = FHIRToGDTConverter(configuration: config)
        
        let result = try converter.convert(observation)
        let formatted = result.document.format()
        let lines = formatted.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        
        #expect(lines.first?.contains("8000") == true)
        #expect(lines.first?.contains("6310") == true)
        
        let hasVersionLine = lines.contains { $0.contains("9218") && $0.contains("02.10") }
        #expect(hasVersionLine, "Missing GDT version line")
        
        let hasSenderLine = lines.contains { $0.contains("9106") && $0.contains("TEST_SENDER") }
        #expect(hasSenderLine, "Missing sender ID line")
        
        let hasReceiverLine = lines.contains { $0.contains("9103") && $0.contains("TEST_RECEIVER") }
        #expect(hasReceiverLine, "Missing receiver ID line")
        
        let hasExamDate = lines.contains { $0.contains("6200") }
        #expect(hasExamDate, "Missing examination date line")
        
        let hasExamTime = lines.contains { $0.contains("6201") }
        #expect(hasExamTime, "Missing examination time line")
        
        let hasRecordLength = lines.contains { $0.contains("8100") }
        #expect(hasRecordLength, "Document should contain record length (8100)")
    }
    
    func parseAppleWatchECGObservation() throws -> Observation {
        let jsonData = Self.appleWatchECGJSON.data(using: .utf8)!
        return try JSONDecoder().decode(Observation.self, from: jsonData)
    }
}
