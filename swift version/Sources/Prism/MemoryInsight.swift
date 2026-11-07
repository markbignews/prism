import Foundation

/// The archive remains searchable in full. The panel gives a bounded paragraph
/// instead of repeating every chapter card. Rebuilds generate one real summary;
/// older archives use short extracts until the user rebuilds them.
enum MemoryInsight {
    static func singleParagraph(_ text: String) -> String {
        text.components(separatedBy: .newlines).map { line in
            line.replacingOccurrences(of: #"^\s*(?:[-*•]\s+|\d+[.)、]\s*)"#,
                                      with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func paragraph(_ entries: [MemoryEntry], language: AppLanguage) -> String {
        let limit = language == .english ? 600 : 220
        let ordered = entries.sorted { $0.createdAt > $1.createdAt }
        var seen = Set<String>()
        var extracts: [String] = []
        var length = 0
        for entry in ordered {
            let text = singleParagraph(entry.content)
            guard !text.isEmpty, seen.insert(BlindspotMemory.normalized(text)).inserted else { continue }
            if length + text.count <= limit {
                extracts.append(text)
                length += text.count + 1
            } else if extracts.isEmpty {
                // Prefer a complete sentence; otherwise clearly mark a preview.
                let preview = String(text.prefix(limit - 1))
                if let end = preview.lastIndex(where: { "。！？.!?".contains($0) }),
                   preview.distance(from: preview.startIndex, to: end) >= limit / 3 {
                    extracts.append(String(preview[...end]))
                } else {
                    extracts.append(preview + "…")
                }
                break
            }
            if extracts.count == 3 { break }
        }
        return extracts.joined(separator: " ")
    }
}
