import Foundation

/// Represents a complete GDT document/file
///
/// A GDT document consists of multiple lines, starting with a record type
/// and optionally ending with a record length.
public struct GDTDocument: Sendable {
    /// The record type for this document
    public let recordType: GDTRecordType

    /// The lines in this document (excluding header and footer)
    public private(set) var lines: [GDTLine]

    /// The encoding to use for this document
    public let encoding: GDTEncoding

    /// GDT version identifier — always "02.10" (GDT 2.1)
    public let gdtVersion: String

    /// Sender identifier
    public var senderID: String?

    /// Receiver identifier
    public var receiverID: String?

    /// Initialize a new GDT document
    /// - Parameters:
    ///   - recordType: The type of record (Satzart)
    ///   - encoding: The character encoding to use
    ///   - gdtVersion: The GDT version string (default: "02.10")
    public init(
        recordType: GDTRecordType,
        encoding: GDTEncoding = .latin1,
        gdtVersion: String = "02.10"
    ) {
        self.recordType = recordType
        self.encoding = encoding
        self.gdtVersion = gdtVersion
        self.lines = []
    }

    /// Add a line to the document
    /// - Parameter line: The GDT line to add
    public mutating func addLine(_ line: GDTLine) {
        lines.append(line)
    }

    /// Add a field with content
    /// - Parameters:
    ///   - fieldIdentifier: The field identifier
    ///   - content: The content value
    public mutating func addField(_ fieldIdentifier: GDTFieldIdentifier, content: String) {
        lines.append(GDTLine(fieldIdentifier: fieldIdentifier, content: content))
    }

    /// Add a field with a date value
    public mutating func addField(_ fieldIdentifier: GDTFieldIdentifier, date: Date) {
        lines.append(GDTLine(fieldIdentifier: fieldIdentifier, date: date))
    }

    /// Add a field with a time value
    public mutating func addTimeField(_ fieldIdentifier: GDTFieldIdentifier, time: Date) {
        lines.append(GDTLine(fieldIdentifier: fieldIdentifier, time: time))
    }

    /// Add a field with an integer value
    public mutating func addField(_ fieldIdentifier: GDTFieldIdentifier, intValue: Int) {
        lines.append(GDTLine(fieldIdentifier: fieldIdentifier, intValue: intValue))
    }

    /// Add a field with a decimal value
    public mutating func addField(_ fieldIdentifier: GDTFieldIdentifier, decimalValue: Double, precision: Int = 2) {
        lines.append(GDTLine(fieldIdentifier: fieldIdentifier, decimalValue: decimalValue, precision: precision))
    }

    /// Build all lines including header and footer
    private func buildAllLines() -> [GDTLine] {
        var allLines: [GDTLine] = []

        // 1. Record type (8000) - always first
        allLines.append(GDTLine(recordType: recordType))

        // 2. GDT Version (9218)
        allLines.append(GDTLine(fieldIdentifier: .gdtVersion, content: gdtVersion))

        // 3. Sender ID if present (field 9106 in GDT 2.1)
        if let senderID = senderID {
            allLines.append(GDTLine(fieldIdentifier: .senderID, content: senderID))
        }

        // 4. Receiver ID if present (field 9103 in GDT 2.1)
        if let receiverID = receiverID {
            allLines.append(GDTLine(fieldIdentifier: .receiverID, content: receiverID))
        }

        // 5. Character set
        allLines.append(GDTLine(fieldIdentifier: .charset, content: encoding.gdtIdentifier))

        // 6. Content lines
        allLines.append(contentsOf: lines)

        // 7. Calculate and add record length (8100)
        // Record length includes ALL lines including the length line itself
        // We need to calculate it beforehand
        let recordLength = calculateRecordLength(lines: allLines)

        // Insert record length after record type
        allLines.insert(
            GDTLine(fieldIdentifier: .recordLength, intValue: recordLength),
            at: 1
        )

        return allLines
    }

    /// Calculate the total record length
    private func calculateRecordLength(lines: [GDTLine]) -> Int {
        // Calculate length of all existing lines
        var totalLength = lines.reduce(0) { $0 + $1.lineLength }

        // Add the length line itself
        // The length value might be 1-5 digits, affecting the line length
        // We'll estimate and adjust
        let estimatedLengthLineLength = 9 + String(totalLength + 15).count
        totalLength += estimatedLengthLineLength

        return totalLength
    }

    /// Format the document as a GDT string
    /// - Returns: The complete GDT document as a string
    public func format() -> String {
        let allLines = buildAllLines()
        return allLines.map { $0.format(encoding: encoding) }.joined()
    }

    /// Format the document as raw bytes
    /// - Returns: The complete GDT document as Data
    public func formatAsData() -> Data? {
        let string = format()
        return string.data(using: encoding.stringEncoding)
    }

    /// Write the document to a file
    /// - Parameter url: The file URL to write to
    /// - Throws: Any error from file writing
    public func write(to url: URL) throws {
        guard let data = formatAsData() else {
            throw GDTError.encodingError
        }
        try data.write(to: url)
    }

    /// Write the document to a file path
    /// - Parameter path: The file path to write to
    /// - Throws: Any error from file writing
    public func write(toPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        try write(to: url)
    }
}

// MARK: - CustomStringConvertible

extension GDTDocument: CustomStringConvertible {
    public var description: String {
        "GDTDocument(type: \(recordType.code), lines: \(lines.count))"
    }
}

// MARK: - GDT Errors

public enum GDTError: Error, Sendable {
    case encodingError
    case invalidFieldIdentifier
    case invalidRecordType
    case invalidLineFormat
    case fileWriteError(String)
}

extension GDTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode GDT document with specified encoding"
        case .invalidFieldIdentifier:
            return "Invalid GDT field identifier"
        case .invalidRecordType:
            return "Invalid GDT record type"
        case .invalidLineFormat:
            return "Invalid GDT line format"
        case .fileWriteError(let message):
            return "Failed to write GDT file: \(message)"
        }
    }
}
