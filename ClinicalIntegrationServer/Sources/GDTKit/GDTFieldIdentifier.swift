/// GDT (Gerätedatentransfer) Field Identifiers — GDT 2.1
///
/// Standard field identifiers as defined by QMS (Qualitätsring Medizinische Software e.V.)
/// for GDT version 2.1 (version string "02.10").
///
/// Sources:
/// - GDT 2.1 specification (QMS)
/// - GDT 3.5 Starterpaket XSD schemas (backward-compatible fields)
/// - GDT example files (Beispieldateien)
///
/// Only identifiers verifiable from the GDT 2.1 specification or its
/// backward-compatible successors are included here.
public enum GDTFieldIdentifier: String, Sendable {
    // MARK: - Header / System Fields

    /// Record type (Satzart) — required first line of every GDT record
    case recordType = "8000"

    /// Record length in bytes (Satzlänge)
    case recordLength = "8100"

    /// GDT version (GDT-ID / Version) — "02.10" for GDT 2.1
    case gdtVersion = "9218"

    /// Sender identifier (Absender)
    case senderID = "9106"

    /// Receiver identifier (Empfänger)
    case receiverID = "9103"

    /// Character set (Zeichensatz) — "2" = IBM CP 437 (Latin-1 compatible)
    case charset = "9206"

    // MARK: - Patient Data (3xxx)

    /// Patient number (Patientennummer)
    case patientID = "3000"

    /// Last name (Nachname)
    case lastName = "3101"

    /// First name (Vorname)
    case firstName = "3102"

    /// Date of birth (Geburtsdatum) — Format: DDMMYYYY
    case birthDate = "3103"

    /// Title (Titel)
    case title = "3104"

    /// Insurance number (Versichertennummer)
    case insuranceNumber = "3105"

    /// Street address (Straße)
    case street = "3106"

    /// Postal code (PLZ)
    case postalCode = "3107"

    /// City (Wohnort)
    case city = "3108"

    /// Gender (Geschlecht) — 1 = male, 2 = female
    case gender = "3110"

    /// Height in cm (Größe)
    case height = "3622"

    /// Weight in kg (Gewicht)
    case weight = "3623"

    // MARK: - Examination Data (6xxx)

    /// Date of examination (Tag der Erhebung) — Format: DDMMYYYY
    case examinationDate = "6200"

    /// Time of examination (Uhrzeit der Erhebung) — Format: HHMMSS
    case examinationTime = "6201"

    /// Free-text comment (Freitext / Befundtext)
    case freeText = "6228"

    // MARK: - Test / Result Data (8xxx)

    /// Device or test identifier (Geräte- bzw. Testident)
    case testIdentifier = "8402"

    /// Short test name (Testbezeichnung kurz) — max 20 characters
    case testNameShort = "8410"

    /// Long test name (Testbezeichnung lang)
    case testNameLong = "8411"

    /// Test status (Teststatus)
    case testStatus = "8418"

    /// Numeric result value (Ergebniswert)
    case resultValue = "8420"

    /// Unit of measurement (Einheit)
    case unit = "8421"

    /// Limit indicator (Grenzwertindikator) — H = high, L = low
    case limitIndicator = "8422"

    /// Normal-range text (Normalwerttext)
    case normalRangeText = "8430"

    /// Normal-range lower limit (Normalwert untere Grenze)
    case normalRangeLower = "8431"

    /// Normal-range upper limit (Normalwert obere Grenze)
    case normalRangeUpper = "8432"

    /// Textual result (Ergebnistext)
    case resultText = "8460"

    /// Comment (Kommentar)
    case comment = "8470"

    /// Result status (Ergebnisstatus)
    case resultStatus = "8480"

    // MARK: - ECG Fields (85xx)

    /// Heart rate in bpm (Herzfrequenz)
    case ecgHeartRate = "8501"

    /// ECG interpretation / finding (EKG-Befund)
    case ecgInterpretation = "8520"
}

// MARK: - Convenience

extension GDTFieldIdentifier {
    /// The 4-digit numeric field identifier code.
    public var code: String {
        rawValue
    }

    /// Human-readable description of the field.
    public var description: String {
        switch self {
        case .recordType:      return "Record Type"
        case .recordLength:    return "Record Length"
        case .gdtVersion:      return "GDT Version"
        case .senderID:        return "Sender ID"
        case .receiverID:      return "Receiver ID"
        case .charset:         return "Character Set"
        case .patientID:       return "Patient ID"
        case .lastName:        return "Last Name"
        case .firstName:       return "First Name"
        case .birthDate:       return "Birth Date"
        case .title:           return "Title"
        case .insuranceNumber: return "Insurance Number"
        case .street:          return "Street"
        case .postalCode:      return "Postal Code"
        case .city:            return "City"
        case .gender:          return "Gender"
        case .height:          return "Height"
        case .weight:          return "Weight"
        case .examinationDate: return "Examination Date"
        case .examinationTime: return "Examination Time"
        case .freeText:        return "Free Text"
        case .testIdentifier:  return "Test Identifier"
        case .testNameShort:   return "Test Name (Short)"
        case .testNameLong:    return "Test Name (Long)"
        case .testStatus:      return "Test Status"
        case .resultValue:     return "Result Value"
        case .unit:            return "Unit"
        case .limitIndicator:  return "Limit Indicator"
        case .normalRangeText: return "Normal Range Text"
        case .normalRangeLower: return "Normal Range Lower"
        case .normalRangeUpper: return "Normal Range Upper"
        case .resultText:      return "Result Text"
        case .comment:         return "Comment"
        case .resultStatus:    return "Result Status"
        case .ecgHeartRate:    return "ECG Heart Rate"
        case .ecgInterpretation: return "ECG Interpretation"
        }
    }
}
