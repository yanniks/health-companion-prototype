import Foundation

/// Abstraction for patient identity verification (DP1, §5.2.2).
///
/// The reference architecture specifies that the IAM component should
/// "interact with the PMS to verify whether the person authenticating
/// is actually a patient of the practice." This protocol decouples the
/// IAM from any specific patient data source, allowing:
///
/// 1. The bundled `PatientStore` (text-file based) for development/demo
/// 2. A PMS-backed implementation for production deployments
///
/// Production implementors should create a concrete type that queries the
/// PMS (e.g., via GDT or FHIR patient demographics) and conforms to this
/// protocol, then inject it via `app.patientVerificationService`.
protocol PatientVerificationService: Sendable {
    /// Checks whether a patient with the given ID exists and is authorized
    /// to share data with this practice.
    func exists(patientId: String) async -> Bool

    /// Retrieves minimal patient master data for the given patient.
    /// Only returns attributes required for authorization and patient matching
    /// (data minimization per DP4).
    func get(patientId: String) async -> PatientRecord?
}

// MARK: - PatientStore Conformance

/// The bundled `PatientStore` serves as the default `PatientVerificationService`
/// for the exemplary implementation. In production, this would be replaced by
/// a PMS-backed implementation that queries patient master data from the
/// practice management system (DP1: minimal manual effort).
extension PatientStore: PatientVerificationService {}
