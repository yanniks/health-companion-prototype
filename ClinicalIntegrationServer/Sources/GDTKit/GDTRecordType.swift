/// GDT (Gerätedatentransfer) Record Types
///
/// Standard record types (Satzarten) as defined by QMS.
/// These define the type of data exchange operation.
public enum GDTRecordType: String, Sendable {
    // MARK: - Stammdaten (Master Data)

    /// Send master data to device (Stammdaten übermitteln)
    /// Used to send patient data to a medical device before examination
    case sendMasterData = "6200"

    /// Request master data from device (Stammdaten anfordern)
    case requestMasterData = "6201"

    // MARK: - Examination Data

    /// Request examination data (Untersuchungsdaten anfordern)
    case requestExaminationData = "6300"

    /// Show examination data (Untersuchungsdaten zeigen)
    /// Used when device wants to display data
    case showExaminationData = "6301"

    /// Transmit examination data (Untersuchungsdaten übermitteln)
    /// Used when device sends examination results
    case transmitExaminationData = "6302"

    /// New examination data (Neue Untersuchungsdaten)
    /// Most commonly used for sending new results
    case newExaminationData = "6310"

    /// Show new examination data
    case showNewExaminationData = "6311"

    // MARK: - Administrative

    /// Error message (Fehlermeldung)
    case errorMessage = "6399"

    /// Request device settings
    case requestDeviceSettings = "6100"

    /// Send device settings
    case sendDeviceSettings = "6101"
}

// MARK: - Extension for convenience

extension GDTRecordType {
    /// Returns the 4-digit record type code
    public var code: String {
        rawValue
    }

    /// Returns a human-readable description
    public var description: String {
        switch self {
        case .sendMasterData:
            return "Send Master Data"
        case .requestMasterData:
            return "Request Master Data"
        case .requestExaminationData:
            return "Request Examination Data"
        case .showExaminationData:
            return "Show Examination Data"
        case .transmitExaminationData:
            return "Transmit Examination Data"
        case .newExaminationData:
            return "New Examination Data"
        case .showNewExaminationData:
            return "Show New Examination Data"
        case .errorMessage:
            return "Error Message"
        case .requestDeviceSettings:
            return "Request Device Settings"
        case .sendDeviceSettings:
            return "Send Device Settings"
        }
    }

    /// Indicates if this record type represents incoming data (from device to PVS)
    public var isIncoming: Bool {
        switch self {
        case .transmitExaminationData, .newExaminationData, .showExaminationData, .showNewExaminationData:
            return true
        default:
            return false
        }
    }

    /// Indicates if this record type represents outgoing data (from PVS to device)
    public var isOutgoing: Bool {
        switch self {
        case .sendMasterData, .requestExaminationData, .requestMasterData:
            return true
        default:
            return false
        }
    }
}
