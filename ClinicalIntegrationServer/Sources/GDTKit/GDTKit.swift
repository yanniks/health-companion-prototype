/// GDTKit - A Swift library for generating GDT (Gerätedatentransfer) files
///
/// GDT is a German standard for data exchange between medical practice
/// management systems (PVS) and medical devices. This library provides
/// types and utilities for creating GDT-compliant files.
///
/// ## Overview
///
/// Use `GDTDocument` to create a new GDT file:
///
/// ```swift
/// var doc = GDTDocument(recordType: .newExaminationData)
/// doc.senderID = "HEALTH_SERVER"
/// doc.receiverID = "MEDISTAR"
///
/// // Add patient data
/// doc.addField(.patientID, content: "12345")
/// doc.addField(.lastName, content: "Mustermann")
/// doc.addField(.firstName, content: "Max")
///
/// // Add examination result
/// doc.addField(.examinationDate, date: Date())
/// doc.addField(.testNameShort, content: "BZ")
/// doc.addField(.testNameLong, content: "Blutzucker")
/// doc.addField(.resultValue, decimalValue: 95.5)
/// doc.addField(.unit, content: "mg/dl")
///
/// // Write to file
/// try doc.write(toPath: "/path/to/output.gdt")
/// ```
///
/// ## GDT Standard
///
/// This library supports GDT 2.1 field identifiers and record types.
/// For more information about the GDT standard, visit:
/// https://www.qms-standards.de/standards/gdt/

// Export all public types
@_exported import struct Foundation.Date
@_exported import struct Foundation.Data
@_exported import struct Foundation.URL

// Re-export public types
public typealias FieldID = GDTFieldIdentifier
public typealias RecordType = GDTRecordType
