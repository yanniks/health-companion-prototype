import Foundation

/// Supported character encodings for GDT files
public enum GDTEncoding: Sendable {
    /// CP437 (DOS codepage) - traditional GDT encoding
    case cp437

    /// ISO 8859-1 (Latin-1) - common modern encoding
    case latin1

    /// Windows-1252 - Windows Latin encoding
    case windows1252

    /// UTF-8 - not standard but some systems accept it
    case utf8

    /// The corresponding Swift String.Encoding
    public var stringEncoding: String.Encoding {
        switch self {
        case .cp437:
            // CP437 is not directly available, fall back to Latin1
            // In production, you might want to use a custom encoding
            return .isoLatin1
        case .latin1:
            return .isoLatin1
        case .windows1252:
            return .windowsCP1252
        case .utf8:
            return .utf8
        }
    }

    /// The GDT charset identifier (for field 9206)
    public var gdtIdentifier: String {
        switch self {
        case .cp437:
            return "1"  // IBM PC
        case .latin1:
            return "2"  // ISO 8859-1
        case .windows1252:
            return "3"  // Windows ANSI
        case .utf8:
            return "4"  // UTF-8 (non-standard)
        }
    }
}
