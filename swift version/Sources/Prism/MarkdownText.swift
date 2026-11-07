import SwiftUI
import Foundation

/// Block Markdown shared by replies and reasoning. Parsing stream updates runs
/// off the main actor; unchanged blocks skip rebuilding their view trees.
struct MarkdownText: View {
    let text: String
    var style: Style
    @StateObject private var rendering: MarkdownRenderState

    enum Style: Equatable {
        case body, reasoning

        var font: Font { self == .reasoning ? .callout : .body }

        func headingFont(_ level: Int) -> Font {
            if self == .reasoning { return .callout.weight(.semibold) }
            switch level {
            case 1: return .title2
            case 2: return .title3
            case 3: return .headline
            default: return .subheadline
            }
        }
    }

    init(text: String, style: Style = .body) {
        self.text = text
        self.style = style
        // StateObject's autoclosure constructs the initial snapshot only once
        // for this view identity, rather than once per incoming stream frame.
        _rendering = StateObject(wrappedValue: MarkdownRenderState(text: text))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rendering.blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, style: style).equatable()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .lineSpacing(3)
        .textSelection(.enabled)
        .task(id: text) { await rendering.update(text) }
    }

    /// Parse markdown blocks once. Static so it's clear this has no side effects.
    nonisolated static func parseBlocks(_ text: String) -> [MarkdownBlock] {
        var result: [MarkdownBlock] = []
        var inCodeBlock = false
        var codeLines: [String] = []

        // Collect consecutive list items
        var pendingList: [MarkdownBlock] = []

        // Collect consecutive table rows
        var pendingTable: [String] = []

        func flushList() {
            if !pendingList.isEmpty {
                result.append(.listGroup(pendingList))
                pendingList = []
            }
        }

        func flushTable() {
            guard !pendingTable.isEmpty else { return }
            defer { pendingTable = [] }
            // A streamed header is ordinary text until its separator arrives;
            // never discard a partial row or duplicate it as both header/data.
            guard pendingTable.count >= 2, isTableSeparator(pendingTable[1]) else {
                result.append(contentsOf: pendingTable.map { .paragraph($0) })
                return
            }
            let headers = parseTableRow(pendingTable[0])
            let rows = pendingTable.dropFirst(2).map { line in
                let cells = parseTableRow(line)
                return cells + Array(repeating: "", count: max(0, headers.count - cells.count))
            }
            result.append(.table(headers: headers, rows: rows))
        }

        for rawLine in text.components(separatedBy: .newlines) {
            if Task.isCancelled { return [] }
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushList()
                flushTable()
                if inCodeBlock {
                    result.append(.code(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(rawLine)
                continue
            }

            // Table row detection: starts and ends with |
            if isTableRow(trimmed) {
                flushList()
                pendingTable.append(trimmed)
                continue
            } else if !pendingTable.isEmpty {
                flushTable()
            }

            if trimmed.isEmpty {
                flushList()
                result.append(.blank)
            } else if let heading = parseHeading(trimmed) {
                flushList()
                result.append(.heading(level: heading.level, content: heading.content))
            } else if isBullet(trimmed) {
                let content = strippedBulletContent(trimmed)
                pendingList.append(.bullet(content))
            } else if let numbered = parseNumbered(trimmed) {
                pendingList.append(.numbered(marker: numbered.marker, content: numbered.content))
            } else {
                flushList()
                result.append(.paragraph(rawLine))
            }
        }

        flushList()
        flushTable()

        if inCodeBlock, !codeLines.isEmpty {
            result.append(.code(codeLines.joined(separator: "\n")))
        }

        return result.isEmpty ? [.paragraph("")] : result
    }

    // MARK: - Table Helpers

    nonisolated private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|")
    }

    nonisolated private static func isTableSeparator(_ line: String) -> Bool {
        // Separator: |---|----| like structure
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return false }
        let inner = line.dropFirst().dropLast()
        let cleaned = inner.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return false }
        return cleaned.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" }
    }

    nonisolated private static func parseTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var skipNext = false
        for ch in line {
            if skipNext {
                // escaped char
                current.append(ch)
                skipNext = false
                continue
            }
            if ch == "\\" {
                skipNext = true
                continue
            }
            if ch == "|" {
                // First | starts the row, subsequent | delimit cells
                if !current.isEmpty || !cells.isEmpty {
                    cells.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        // Remove empty trailing cell from trailing |
        if let last = cells.last, last.isEmpty {
            cells.removeLast()
        }
        return cells
    }

    // MARK: - Common Parsers

    nonisolated private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            || line.hasPrefix("• ")
    }

    nonisolated private static func strippedBulletContent(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2))
        }
        if line.hasPrefix("• ") {
            return String(line.dropFirst(2))
        }
        return line
    }

    nonisolated private static func parseHeading(_ line: String) -> (level: Int, content: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes),
              line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    nonisolated private static func parseNumbered(_ line: String) -> (marker: String, content: String)? {
        guard let separatorIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let marker = String(line[...separatorIndex])
        guard marker.dropLast().allSatisfy({ $0.isNumber }),
              separatorIndex > line.startIndex else { return nil }
        let contentStart = line.index(after: separatorIndex)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return (marker, String(line[line.index(after: contentStart)...]))
    }

}

/// Keep the last prepared snapshot visible while parsing a new stream frame.
/// A cancelled/older parse can never replace the latest requested text.
@MainActor
final class MarkdownRenderState: ObservableObject {
    @Published private(set) var blocks: [MarkdownBlock]
    private var renderedText: String
    private var revision = 0

    init(text: String) {
        renderedText = text
        blocks = MarkdownText.parseBlocks(text)
    }

    func update(_ text: String) async {
        guard !Task.isCancelled else { return }
        revision += 1
        let requestedRevision = revision
        guard text != renderedText else { return }
        let parsing = Task.detached(priority: .userInitiated) {
            MarkdownText.parseBlocks(text)
        }
        let prepared = await withTaskCancellationHandler {
            await parsing.value
        } onCancel: {
            parsing.cancel()
        }
        guard !Task.isCancelled, requestedRevision == revision else { return }
        renderedText = text
        if blocks != prepared { blocks = prepared }
    }
}

private struct MarkdownBlockView: View, Equatable {
    let block: MarkdownBlock
    let style: MarkdownText.Style

    var body: some View {
        switch block {
        case .blank:
            Color.clear.frame(height: 4).accessibilityHidden(true)
        case .heading(let level, let content):
            InlineMarkdownText(content).equatable()
                .font(style.headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, level <= 2 ? 4 : 2)
        case .bullet(let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").font(style.font)
                InlineMarkdownText(content).equatable().font(style.font)
            }
        case .numbered(let marker, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker).font(style.font.monospacedDigit()).foregroundStyle(.secondary)
                InlineMarkdownText(content).equatable().font(style.font)
            }
        case .code(let content):
            CodeBlockView(content: content, font: style.font)
        case .paragraph(let content):
            InlineMarkdownText(content).equatable().font(style.font)
        case .listGroup(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownBlockView(block: item, style: style).equatable()
                }
            }
        case .table(let headers, let rows):
            TableView(headers: headers, rows: rows)
        }
    }
}

// MARK: - Table View

private struct TableView: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            // Header row
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
                    InlineMarkdownText(header).equatable()
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.08))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.12))
                                .frame(height: 0.5)
                        }
                }
            }

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                        InlineMarkdownText(cell).equatable()
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(i % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                    }
                }
                Divider().opacity(0.3)
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}

// MARK: - Equatable Support

extension MarkdownText: @MainActor Equatable {
    static func == (lhs: MarkdownText, rhs: MarkdownText) -> Bool {
        lhs.text == rhs.text && lhs.style == rhs.style
    }
}

// MARK: - Inline Markdown

private struct InlineMarkdownText: View, Equatable {
    var content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        InlineMarkdown.parse(content)
    }
}

/// Foundation handles links, code and emphasis. Mask paired strong delimiters
/// before parsing so Chinese punctuation/stray spaces do not expose model markup.
/// This changes presentation only; message storage/copy retains the original.
enum InlineMarkdown {
    nonisolated static func parse(_ source: String) -> AttributedString {
        guard source.contains("**") else { return native(source) }
        let characters = Array(source)
        var markers: [Int] = []
        var i = 0
        while i < characters.count {
            if characters[i] == "\\" {
                i += 2 // Escaped asterisks must remain literal.
                continue
            }
            if characters[i] == "`" {
                let start = i
                while i < characters.count, characters[i] == "`" { i += 1 }
                let length = i - start
                var end = i
                var closingEnd: Int?
                while end < characters.count {
                    if characters[end] != "`" { end += 1; continue }
                    let runStart = end
                    while end < characters.count, characters[end] == "`" { end += 1 }
                    if end - runStart == length { closingEnd = end; break }
                }
                // An unmatched backtick is plain text in Markdown.
                if let closingEnd { i = closingEnd }
                continue
            }
            if characters[i] == "(", i > 0, characters[i - 1] == "]" {
                var depth = 1
                i += 1
                while i < characters.count, depth > 0 {
                    if characters[i] == "\\" { i += 2; continue }
                    if characters[i] == "(" { depth += 1 }
                    if characters[i] == ")" { depth -= 1 }
                    i += 1
                }
                continue // Never format a link destination/title.
            }
            if characters[i] == "<" {
                if let end = characters[(i + 1)...].firstIndex(of: ">") {
                    i = end + 1
                    continue
                }
            }
            if characters[i] == "*" {
                let start = i
                while i < characters.count, characters[i] == "*" { i += 1 }
                if i - start == 2 { markers.append(start) }
                if i - start == 3 { markers.append(start + 1) }
                continue // Preserve the single emphasis in ***nested*** spans.
            }
            i += 1
        }

        guard markers.count >= 2 else { return native(source) }
        var tokenPrefix = "\u{E000}prism"
        while source.contains(tokenPrefix) { tokenPrefix += "x" }
        var replacements: [Int: String] = [:]
        var pairs: [(open: String, close: String)] = []
        for index in stride(from: 0, to: markers.count - markers.count % 2, by: 2) {
            let start = markers[index]
            let end = markers[index + 1]
            guard characters[(start + 2)..<end].contains(where: { !$0.isWhitespace }) else { continue }
            let open = "\(tokenPrefix)\(index)open\u{E001}"
            let close = "\(tokenPrefix)\(index)close\u{E001}"
            replacements[start] = open
            replacements[end] = close
            pairs.append((open, close))
        }
        var prepared = ""
        i = 0
        while i < characters.count {
            if let token = replacements[i] {
                prepared += token
                i += 2
            } else {
                prepared.append(characters[i])
                i += 1
            }
        }
        var result = native(prepared)
        for pair in pairs {
            guard let open = result.range(of: pair.open), let close = result.range(of: pair.close) else { continue }
            let content = open.upperBound..<close.lowerBound
            for run in Array(result[content].runs) {
                result[run.range].inlinePresentationIntent = (run.inlinePresentationIntent ?? []).union(.stronglyEmphasized)
            }
            result.replaceSubrange(close, with: AttributedString())
            if let open = result.range(of: pair.open) { result.replaceSubrange(open, with: AttributedString()) }
        }
        return result
    }

    nonisolated private static func native(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(source)
    }

}

// MARK: - Code Block with Copy Button

/// Monospaced code block with a hover-revealed copy button.
private struct CodeBlockView: View {
    @EnvironmentObject private var settings: AppSettings
    let content: String
    var font: Font = .body
    @State private var isHovering = false
    @State private var copied = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(content)
                .font(font.monospaced())
                .padding(8)
                .padding(.trailing, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            if isHovering || copied {
                Button {
                    NativeSupport.copyToClipboard(content)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(5)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .help(L10n.text(.copyCode, settings.language))
                .padding(4)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Markdown Block Model

enum MarkdownBlock: Equatable, Sendable {
    case blank
    case heading(level: Int, content: String)
    case bullet(String)
    case numbered(marker: String, content: String)
    case code(String)
    case paragraph(String)
    case listGroup([MarkdownBlock])
    case table(headers: [String], rows: [[String]])
}
