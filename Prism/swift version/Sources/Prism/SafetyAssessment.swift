import Foundation

/// Routing depends on a contextual model assessment, never on words in user text.
/// Uncertainty and transport/schema failures are different from immediate danger.
struct SafetyAssessment: Decodable, Equatable {
    enum Flag: String, Decodable { case ok, uncertain, crisis }
    var flag: Flag
    var immediateDanger: Bool?
    var evidence: String?

    enum CodingKeys: String, CodingKey {
        case flag, evidence
        case immediateDanger = "immediate_danger"
    }

    var requiresIntervention: Bool {
        flag == .crisis && immediateDanger == true
            && evidence?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var isUncertain: Bool { flag == .uncertain || (flag == .crisis && !requiresIntervention) }
}
