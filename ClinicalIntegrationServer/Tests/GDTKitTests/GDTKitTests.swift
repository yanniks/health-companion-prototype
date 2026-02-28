import Foundation
import Testing

@testable import GDTKit

@Suite("GDT Field Identifier Tests")
struct GDTFieldIdentifierTests {

    @Test("Field identifier codes are 4 digits")
    func fieldIdentifierCodeLength() {
        let identifiers: [GDTFieldIdentifier] = [
            .recordType, .patientID, .lastName, .firstName,
            .examinationDate, .resultValue, .unit,
        ]

        for identifier in identifiers {
            #expect(identifier.code.count == 4)
        }
    }

    @Test("Record type identifier is 8000")
    func recordTypeCode() {
        #expect(GDTFieldIdentifier.recordType.code == "8000")
    }

    @Test("Patient ID identifier is 3000")
    func patientIdCode() {
        #expect(GDTFieldIdentifier.patientID.code == "3000")
    }

    @Test("Result value identifier is 8420")
    func resultValueCode() {
        #expect(GDTFieldIdentifier.resultValue.code == "8420")
    }
}

@Suite("GDT Record Type Tests")
struct GDTRecordTypeTests {

    @Test("Record type codes are 4 digits")
    func recordTypeCodeLength() {
        let types: [GDTRecordType] = [
            .sendMasterData, .newExaminationData, .transmitExaminationData,
        ]

        for type in types {
            #expect(type.code.count == 4)
        }
    }

    @Test("New examination data is 6310")
    func newExaminationDataCode() {
        #expect(GDTRecordType.newExaminationData.code == "6310")
    }

    @Test("Incoming record types are correctly identified")
    func incomingRecordTypes() {
        #expect(GDTRecordType.newExaminationData.isIncoming == true)
        #expect(GDTRecordType.transmitExaminationData.isIncoming == true)
        #expect(GDTRecordType.sendMasterData.isIncoming == false)
    }
}

@Suite("GDT Line Tests")
struct GDTLineTests {

    @Test("Line length calculation is correct")
    func lineLengthCalculation() {
        let line = GDTLine(fieldIdentifier: .patientID, content: "12345")
        // LLL (3) + FFFF (4) + content (5) + CRLF (2) = 14
        #expect(line.lineLength == 14)
    }

    @Test("Empty content line length is correct")
    func emptyContentLineLength() {
        let line = GDTLine(fieldIdentifier: .patientID, content: "")
        // LLL (3) + FFFF (4) + content (0) + CRLF (2) = 9
        #expect(line.lineLength == 9)
    }

    @Test("Line formatting is correct")
    func lineFormatting() {
        let line = GDTLine(fieldIdentifier: .patientID, content: "12345")
        let formatted = line.format()

        #expect(formatted == "014300012345\r\n")
    }

    @Test("Date formatting is DDMMYYYY")
    func dateFormatting() {
        // Create a specific date: January 15, 2024
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let line = GDTLine(fieldIdentifier: .examinationDate, date: date)

        #expect(line.content == "15012024")
    }

    @Test("Time formatting is HHMMSS")
    func timeFormatting() {
        var components = DateComponents()
        components.year = 2024
        components.month = 1
        components.day = 15
        components.hour = 14
        components.minute = 30
        components.second = 45
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(from: components)!

        let line = GDTLine(fieldIdentifier: .examinationTime, time: date)

        #expect(line.content == "143045")
    }

    @Test("Decimal value formatting with precision")
    func decimalValueFormatting() {
        let line = GDTLine(fieldIdentifier: .resultValue, decimalValue: 123.456, precision: 2)
        #expect(line.content == "123.46")
    }

    @Test("Content is trimmed")
    func contentTrimming() {
        let line = GDTLine(fieldIdentifier: .lastName, content: "  Mustermann  \n")
        #expect(line.content == "Mustermann")
    }
}

@Suite("GDT Document Tests")
struct GDTDocumentTests {

    @Test("Document creation with record type")
    func documentCreation() {
        let doc = GDTDocument(recordType: .newExaminationData)
        #expect(doc.recordType == .newExaminationData)
    }

    @Test("Adding fields to document")
    func addingFields() {
        var doc = GDTDocument(recordType: .newExaminationData)
        doc.addField(.patientID, content: "12345")
        doc.addField(.lastName, content: "Mustermann")

        #expect(doc.lines.count == 2)
    }

    @Test("Document formatting includes header")
    func documentHeaderFormat() {
        var doc = GDTDocument(recordType: .newExaminationData)
        doc.senderID = "TEST"
        doc.receiverID = "PVS"
        doc.addField(.patientID, content: "12345")

        let formatted = doc.format()

        // Should start with record type
        #expect(formatted.hasPrefix("01380006310\r\n"))
        // Should contain GDT version
        #expect(formatted.contains("921802.10"))
    }

    @Test("Document can be written to data")
    func documentToData() {
        var doc = GDTDocument(recordType: .newExaminationData)
        doc.addField(.patientID, content: "12345")

        let data = doc.formatAsData()
        #expect(data != nil)
    }
}

@Suite("GDT Encoding Tests")
struct GDTEncodingTests {

    @Test("Latin1 encoding identifier is correct")
    func latin1Identifier() {
        #expect(GDTEncoding.latin1.gdtIdentifier == "2")
    }

    @Test("UTF8 encoding identifier is correct")
    func utf8Identifier() {
        #expect(GDTEncoding.utf8.gdtIdentifier == "4")
    }

    @Test("String encoding mapping is correct")
    func stringEncodingMapping() {
        #expect(GDTEncoding.latin1.stringEncoding == .isoLatin1)
        #expect(GDTEncoding.utf8.stringEncoding == .utf8)
    }
}
