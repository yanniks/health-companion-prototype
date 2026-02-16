import Foundation

/// Represents a single line in a GDT file
///
/// GDT line format: `LLLFFFFContent\r\n`
/// - LLL: 3-digit line length
/// - FFFF: 4-digit field identifier
/// - Content: Variable length content
/// - \r\n: Line terminator (CR+LF)
public struct GDTLine: Sendable, Equatable {
    /// The field identifier for this line
    public let fieldIdentifier: GDTFieldIdentifier
    
    /// The content/value of this line
    public let content: String
    
    /// Initialize a GDT line with a field identifier and content
    /// - Parameters:
    ///   - fieldIdentifier: The GDT field identifier
    ///   - content: The content value (will be trimmed)
    public init(fieldIdentifier: GDTFieldIdentifier, content: String) {
        self.fieldIdentifier = fieldIdentifier
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Initialize a GDT line with a record type
    /// - Parameter recordType: The GDT record type
    public init(recordType: GDTRecordType) {
        self.fieldIdentifier = .recordType
        self.content = recordType.code
    }
    
    /// Calculate the total line length
    /// Format: LLL (3) + FFFF (4) + Content (n) + CR+LF (2) = 9 + n
    public var lineLength: Int {
        return 3 + 4 + content.count + 2
    }
    
    /// Format the line as a GDT string
    /// - Parameter encoding: The character encoding to use for length calculation
    /// - Returns: The formatted GDT line string
    public func format(encoding: GDTEncoding = .latin1) -> String {
        // Calculate the byte length based on encoding
        let contentBytes = content.data(using: encoding.stringEncoding)?.count ?? content.count
        let totalLength = 3 + 4 + contentBytes + 2
        
        // Format: LLLFFFFContent\r\n
        let lengthStr = String(format: "%03d", totalLength)
        return "\(lengthStr)\(fieldIdentifier.code)\(content)\r\n"
    }
    
    /// Format the line as raw bytes
    /// - Parameter encoding: The character encoding to use
    /// - Returns: The formatted GDT line as Data
    public func formatAsData(encoding: GDTEncoding = .latin1) -> Data? {
        return format(encoding: encoding).data(using: encoding.stringEncoding)
    }
}

// MARK: - CustomStringConvertible

extension GDTLine: CustomStringConvertible {
    public var description: String {
        return "GDTLine(\(fieldIdentifier.code): \(content))"
    }
}

// MARK: - Convenience Initializers

extension GDTLine {
    /// Create a line with a date value
    /// - Parameters:
    ///   - fieldIdentifier: The field identifier
    ///   - date: The date to format (DDMMYYYY)
    public init(fieldIdentifier: GDTFieldIdentifier, date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddMMyyyy"
        self.init(fieldIdentifier: fieldIdentifier, content: formatter.string(from: date))
    }
    
    /// Create a line with a time value
    /// - Parameters:
    ///   - fieldIdentifier: The field identifier
    ///   - time: The time to format (HHMMSS)
    public init(fieldIdentifier: GDTFieldIdentifier, time: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        self.init(fieldIdentifier: fieldIdentifier, content: formatter.string(from: time))
    }
    
    /// Create a line with an integer value
    public init(fieldIdentifier: GDTFieldIdentifier, intValue: Int) {
        self.init(fieldIdentifier: fieldIdentifier, content: String(intValue))
    }
    
    /// Create a line with a decimal value
    /// - Parameters:
    ///   - fieldIdentifier: The field identifier
    ///   - decimalValue: The decimal value
    ///   - precision: Number of decimal places (default: 2)
    public init(fieldIdentifier: GDTFieldIdentifier, decimalValue: Double, precision: Int = 2) {
        let formatted = String(format: "%.\(precision)f", decimalValue)
        self.init(fieldIdentifier: fieldIdentifier, content: formatted)
    }
}
