import SwiftUI
import Foundation

/// Renders markdown text as SwiftUI views, including tables.
///
/// Blocks are parsed once at init time and stored, so SwiftUI body re-evaluations
/// don't re-parse the entire markdown string — critical for streaming performance.
struct MarkdownText: View {
    let text: String
    private let blocks: [MarkdownBlock]

    init(text: String) {
        self.text = text
        self.blocks = MarkdownText.parseBlocks(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .blank:
                    Spacer(minLength: 4)
                case .heading(let level, let content):
                    InlineMarkdownText(content)
                        .font(Self.headingFont(level))
                        .fontWeight(.semibold)
                        .padding(.top, level <= 2 ? 4 : 2)
                case .bullet(let content):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .font(.body)
                        InlineMarkdownText(content)
                            .font(.body)
                    }
                case .numbered(let marker, let content):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker)
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        InlineMarkdownText(content)
                            .font(.body)
                    }
                case .code(let content):
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                case .paragraph(let content):
                    InlineMarkdownText(content)
                        .font(.body)
                case .listGroup(let items):
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .bullet(let content):
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("•")
                                        .font(.body)
                                    InlineMarkdownText(content)
                                        .font(.body)
                                }
                            case .numbered(let marker, let content):
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(marker)
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    InlineMarkdownText(content)
                                        .font(.body)
                                }
                            default:
                                EmptyView()
                            }
                        }
                    }
                case .table(let headers, let rows):
                    TableView(headers: headers, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineSpacing(3)
        .textSelection(.enabled)
    }

    /// Parse markdown blocks once. Static so it's clear this has no side effects.
    fileprivate static func parseBlocks(_ text: String) -> [MarkdownBlock] {
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
            if pendingTable.count >= 2 {
                // First row = header, skip separator (|---|), rest = data rows
                let headerLine = pendingTable[0]
                let headers = parseTableRow(headerLine)
                var rows: [[String]] = []
                // Find separator row (|---|---|) — must be second row
                let startIdx: Int
                if pendingTable.count > 1 && isTableSeparator(pendingTable[1]) {
                    startIdx = 2
                } else {
                    // No separator, treat all rows as data (no header styling)
                    startIdx = 1
                    rows.append(headers)
                }
                for i in startIdx..<pendingTable.count {
                    let cells = parseTableRow(pendingTable[i])
                    if !cells.isEmpty {
                        // Pad to match header width
                        let padded = cells.count < headers.count
                            ? cells + Array(repeating: "", count: headers.count - cells.count)
                            : cells
                        rows.append(padded)
                    }
                }
                if !rows.isEmpty {
                    result.append(.table(headers: headers, rows: rows))
                }
            }
            pendingTable = []
        }

        for rawLine in text.components(separatedBy: .newlines) {
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

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        // Separator: |---|----| like structure
        guard line.hasPrefix("|") && line.hasSuffix("|") else { return false }
        let inner = line.dropFirst().dropLast()
        let cleaned = inner.replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return false }
        return cleaned.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" }
    }

    private static func parseTableRow(_ line: String) -> [String] {
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

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            || line.hasPrefix("• ")
    }

    private static func strippedBulletContent(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
            return String(line.dropFirst(2))
        }
        if line.hasPrefix("• ") {
            return String(line.dropFirst(2))
        }
        return line
    }

    private static func parseHeading(_ line: String) -> (level: Int, content: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes),
              line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func parseNumbered(_ line: String) -> (marker: String, content: String)? {
        guard let separatorIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return nil }
        let marker = String(line[...separatorIndex])
        guard marker.dropLast().allSatisfy({ $0.isNumber }),
              separatorIndex > line.startIndex else { return nil }
        let contentStart = line.index(after: separatorIndex)
        guard contentStart < line.endIndex, line[contentStart] == " " else { return nil }
        return (marker, String(line[line.index(after: contentStart)...]))
    }

    fileprivate static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
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
                    InlineMarkdownText(header)
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
                        InlineMarkdownText(cell)
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
        lhs.text == rhs.text
    }
}

// MARK: - Inline Markdown

private struct InlineMarkdownText: View {
    var content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributed: AttributedString {
        (try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(content)
    }
}

// MARK: - Markdown Block Model

private enum MarkdownBlock {
    case blank
    case heading(level: Int, content: String)
    case bullet(String)
    case numbered(marker: String, content: String)
    case code(String)
    case paragraph(String)
    case listGroup([MarkdownBlock])
    case table(headers: [String], rows: [[String]])
}
