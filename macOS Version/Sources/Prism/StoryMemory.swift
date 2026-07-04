import Foundation

enum StoryMemory {
    static func ingest(userText: String, messageID: UUID, conversation: inout Conversation) {
        let paragraphs = splitParagraphs(userText)

        guard !paragraphs.isEmpty else { return }

        if paragraphs.count > 1 {
            for paragraph in paragraphs where paragraph.count >= 12 {
                appendChapter(from: paragraph, messageID: messageID, conversation: &conversation)
            }
            return
        }

        let paragraph = paragraphs[0]
        if paragraph.count >= 80 || conversation.chapters.isEmpty {
            appendChapter(from: paragraph, messageID: messageID, conversation: &conversation)
        } else if let lastIndex = conversation.chapters.indices.last {
            conversation.chapters[lastIndex].summary = boundedSummary(
                conversation.chapters[lastIndex].summary + "\n" + paragraph
            )
            conversation.chapters[lastIndex].keywords = mergeKeywords(
                conversation.chapters[lastIndex].keywords,
                extractKeywords(from: paragraph)
            )
            conversation.chapters[lastIndex].messageIDs.append(messageID)
            conversation.chapters[lastIndex].updatedAt = Date()
        }
    }

    static func relevantContext(for userText: String, in conversation: Conversation, language: AppLanguage) -> String? {
        guard !conversation.chapters.isEmpty else { return nil }

        let lowered = userText.lowercased()
        let directMatches = directChapterMatches(in: lowered, chapters: conversation.chapters)
        if !directMatches.isEmpty {
            return format(directMatches, language: language)
        }

        guard shouldSearchMemory(lowered) else { return nil }

        let queryKeywords = Set(extractKeywords(from: lowered))
        let scored = conversation.chapters.compactMap { chapter -> (StoryChapter, Int)? in
            var score = 0
            for keyword in chapter.keywords where lowered.contains(keyword.lowercased()) {
                score += 3
            }
            for keyword in queryKeywords where chapter.summary.lowercased().contains(keyword) || chapter.title.lowercased().contains(keyword) {
                score += 1
            }
            return score > 0 ? (chapter, score) : nil
        }
        .sorted { $0.1 > $1.1 }
        .prefix(3)
        .map(\.0)

        if !scored.isEmpty {
            return format(Array(scored), language: language)
        }

        return format(Array(conversation.chapters.suffix(2)), language: language)
    }

    /// Public keyword extractor for use by the auto-summarization agent
    static func extractKeywordsPublic(from text: String) -> [String] {
        extractKeywords(from: text)
    }

    private static func appendChapter(from paragraph: String, messageID: UUID, conversation: inout Conversation) {
        let title = makeTitle(from: paragraph, fallbackNumber: conversation.chapters.count + 1)
        let chapter = StoryChapter(
            title: title,
            summary: boundedSummary(paragraph),
            keywords: extractKeywords(from: paragraph),
            messageIDs: [messageID]
        )
        conversation.chapters.append(chapter)
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty {
                    paragraphs.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                    current = []
                }
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            paragraphs.append(current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return paragraphs.filter { !$0.isEmpty }
    }

    private static func makeTitle(from text: String, fallbackNumber: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstSentence = normalized
            .components(separatedBy: CharacterSet(charactersIn: "。！？.!?\n"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !firstSentence.isEmpty else { return "Chapter \(fallbackNumber)" }
        return String(firstSentence.prefix(24))
    }

    private static func boundedSummary(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 900 ? String(trimmed.suffix(900)) : trimmed
    }

    private static func extractKeywords(from text: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "，。！？；：、“”‘’（）【】《》…"))
        let tokens = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { token in
                token.count >= 2 &&
                !stopWords.contains(token)
            }

        var result: [String] = []
        for token in tokens where !result.contains(token) {
            result.append(token)
            if result.count >= 12 { break }
        }
        return result
    }

    private static func mergeKeywords(_ lhs: [String], _ rhs: [String]) -> [String] {
        var merged = lhs
        for keyword in rhs where !merged.contains(keyword) {
            merged.append(keyword)
        }
        return Array(merged.prefix(16))
    }

    private static func directChapterMatches(in lowered: String, chapters: [StoryChapter]) -> [StoryChapter] {
        for (index, chapter) in chapters.enumerated() {
            let number = index + 1
            if lowered.contains("第\(number)章") ||
                lowered.contains("第\(number)节") ||
                lowered.contains("章节\(number)") ||
                lowered.contains("chapter \(number)") {
                return [chapter]
            }
        }
        return chapters.filter { chapter in
            lowered.contains(chapter.title.lowercased()) && chapter.title.count >= 4
        }
    }

    private static func shouldSearchMemory(_ lowered: String) -> Bool {
        let indicators = [
            "章节", "那段", "前面", "之前", "刚才", "刚刚", "上面", "回到", "提到",
            "chapter", "earlier", "previous", "before", "that part", "the part"
        ]
        return indicators.contains { lowered.contains($0) }
    }

    private static func format(_ chapters: [StoryChapter], language: AppLanguage) -> String {
        let heading: String
        let keywordLabel: String
        let summaryLabel: String
        switch language {
        case .simplifiedChinese:
            heading = "以下是本地章节记忆中与本轮问题相关的内容。只在确实相关时使用，不要机械复述："
            keywordLabel = "关键词"
            summaryLabel = "摘要"
        case .traditionalChinese:
            heading = "以下是本地章節記憶中與本輪問題相關的內容。只在確實相關時使用，不要機械複述："
            keywordLabel = "關鍵詞"
            summaryLabel = "摘要"
        case .english:
            heading = "Relevant local chapter memory for this turn. Use only when genuinely relevant; do not recite it mechanically:"
            keywordLabel = "Keywords"
            summaryLabel = "Summary"
        }

        let body = chapters.enumerated().map { index, chapter in
            """
            \(index + 1). \(chapter.title)
            \(keywordLabel): \(chapter.keywords.joined(separator: ", "))
            \(summaryLabel): \(chapter.summary)
            """
        }
        .joined(separator: "\n\n")

        return heading + "\n\n" + body
    }

    private static let stopWords: Set<String> = [
        "就是", "然后", "但是", "因为", "所以", "这个", "那个", "他们", "我们", "你们",
        "自己", "感觉", "觉得", "没有", "不是", "还是", "只是", "已经", "可能",
        "the", "and", "that", "this", "with", "from", "have", "just", "feel", "because"
    ]
}
