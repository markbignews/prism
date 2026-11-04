import Foundation

/// A pattern is a tentative hypothesis; individual observations remain available
/// in its details. Grouping old archives does not rewrite or discard their data.
enum BlindspotMemory {
    struct Group: Identifiable {
        var id: String
        var latest: BlindspotRecord
        var observations: [BlindspotRecord]
        var recordIDs: [UUID]
    }

    static func patternKey(_ pattern: String) -> String {
        let key = normalized(pattern)
        switch key {
        case "解释循环", "解釋循環", "explanationloop": return "explanation_loop"
        case "回避自我", "selfavoidance": return "self_avoidance"
        case "意图行动差距", "意圖行動差距", "intentionactiongap": return "intention_action_gap"
        default: return key
        }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().unicodeScalars
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) }
            .map(String.init).joined()
    }

    static func groups(_ records: [BlindspotRecord]) -> [Group] {
        var groups: [Group] = []
        var indices: [String: Int] = [:]
        // Preserve input order as the tie breaker for legacy equal timestamps.
        let ordered = records.enumerated().sorted {
            $0.element.createdAt == $1.element.createdAt
                ? $0.offset > $1.offset : $0.element.createdAt > $1.element.createdAt
        }
        for (_, record) in ordered {
            let key = record.conversationID.uuidString + ":" + patternKey(record.pattern)
            if let index = indices[key] {
                groups[index].recordIDs.append(record.id)
                if !groups[index].observations.contains(where: {
                    normalized($0.evidence) == normalized(record.evidence)
                }) {
                    groups[index].observations.append(record)
                }
            } else {
                indices[key] = groups.count
                groups.append(Group(id: key, latest: record, observations: [record], recordIDs: [record.id]))
            }
        }
        return groups
    }

    /// Re-reading the same evidence or changing only the follow-up question is
    /// not a new occurrence. Do not use fuzzy similarity: a small negation,
    /// person or date change can materially change the evidence.
    static func insert(_ record: BlindspotRecord, into records: inout [BlindspotRecord]) {
        let pattern = patternKey(record.pattern)
        let evidence = normalized(record.evidence)
        guard !pattern.isEmpty, !evidence.isEmpty else { return }
        let matching = records.filter {
            $0.conversationID == record.conversationID && patternKey($0.pattern) == pattern
        }
        guard !matching.contains(where: {
            normalized($0.evidence) == evidence ||
                (record.sourceMessageID != nil && $0.sourceMessageID == record.sourceMessageID)
        }) else { return }
        var newRecord = record
        newRecord.pattern = record.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        newRecord.evidence = record.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        // Repetition is evidence-specific, never inferred from duplicate rows.
        newRecord.severity = matching.isEmpty ? "new" : "recurring"
        records.append(newRecord)
        if records.count > 300 {
            records = records.sorted { $0.createdAt > $1.createdAt }.prefix(300).map { $0 }
        }
    }

    static func historyContext(_ records: [BlindspotRecord]) -> String {
        let current = groups(records)
        guard !current.isEmpty else { return "（无历史盲点记录）" }
        return current.prefix(6).map { group in
            let evidence = group.observations.prefix(2)
                .map { String($0.evidence.prefix(160)) }.joined(separator: "；")
            return "- [待验证] \(group.latest.pattern): \(evidence)"
        }.joined(separator: "\n")
    }
}
