import Foundation
import Testing
@testable import Prism

@Suite struct MarkdownBlockParsingTests {
    @Test func reasoningKeepsHeadingsListsCodeAndInlineMarkdown() {
        let text = "## 核对依据\n**事实**与[来源](https://example.com)\n- 第一项\n- `第二项`\n\n1. 下一步\n```swift\nlet fact = true\n```"
        #expect(MarkdownText.parseBlocks(text) == [
            .heading(level: 2, content: "核对依据"),
            .paragraph("**事实**与[来源](https://example.com)"),
            .listGroup([.bullet("第一项"), .bullet("`第二项`")]),
            .blank,
            .listGroup([.numbered(marker: "1.", content: "下一步")]),
            .code("let fact = true")
        ])
    }

    @Test func streamedTableHeaderNeverDisappearsOrDuplicates() {
        #expect(MarkdownText.parseBlocks("| 事实 | 来源 |") == [.paragraph("| 事实 | 来源 |")])
        #expect(MarkdownText.parseBlocks("| 事实 | 来源 |\n| --- | --- |") == [
            .table(headers: ["事实", "来源"], rows: [])
        ])
        #expect(MarkdownText.parseBlocks("| 事实 | 来源 |\n| --- | --- |\n| 已确认 | 原文 |") == [
            .table(headers: ["事实", "来源"], rows: [["已确认", "原文"]])
        ])
    }

    @Test func unfinishedCodeFenceKeepsStreamedContent() {
        #expect(MarkdownText.parseBlocks("```swift\nlet a = 1") == [.code("let a = 1")])
        #expect(MarkdownText.parseBlocks("```swift\nlet a = 1\n```\n最终答复") == [
            .code("let a = 1"), .paragraph("最终答复")
        ])
    }
}

@Suite @MainActor struct MarkdownSnapshotTests {
    @Test func finalSnapshotWinsOverAnOlderLongParse() async {
        let state = MarkdownRenderState(text: "原文")
        let old = Task { await state.update(String(repeating: "## 长文\n- 检查证据\n", count: 10_000)) }
        await Task.yield()
        await state.update("## 完整最终结果\n**保留全部文字**")
        await old.value
        #expect(state.blocks == [.heading(level: 2, content: "完整最终结果"), .paragraph("**保留全部文字**")])
    }

    @Test func cancelledParseCannotReplaceVisibleSnapshot() async {
        let state = MarkdownRenderState(text: "原文")
        let obsolete = Task { await state.update(String(repeating: "## 旧快照\n", count: 10_000)) }
        obsolete.cancel()
        await obsolete.value
        #expect(state.blocks == [.paragraph("原文")])
        await state.update("最新文字")
        #expect(state.blocks == [.paragraph("最新文字")])
    }

    @Test func revertingToRenderedTextInvalidatesInFlightParse() async {
        let state = MarkdownRenderState(text: "原文")
        let obsolete = Task { await state.update(String(repeating: "长文\n", count: 10_000)) }
        await Task.yield()
        await state.update("原文")
        await obsolete.value
        #expect(state.blocks == [.paragraph("原文")])
    }
}


@Suite struct InlineMarkdownRenderingTests {
    @Test(arguments: [
        ("**一是你们有一套不用说话的互动方式。 **对视、走路互撞。", "一是你们有一套不用说话的互动方式。 ", "对视、走路互撞。"),
        ("**二是节奏。 **长年不怎么联系。", "二是节奏。 ", "长年不怎么联系。"),
        ("**三是模糊。**一段没有被命名的关系。", "三是模糊。", "一段没有被命名的关系。"),
        ("**四是起点早。 **高中开始的东西。", "四是起点早。 ", "高中开始的东西。")
    ])
    func screenshotStrongTextActuallyHasBoldAttributes(example: (String, String, String)) throws {
        let rendered = InlineMarkdown.parse(example.0)
        #expect(String(rendered.characters) == example.1 + example.2)
        let bold = try #require(rendered.range(of: example.1))
        #expect(rendered[bold].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        let plain = try #require(rendered.range(of: example.2))
        #expect(rendered[plain].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) != true })
    }

    @Test func linksCodeAndEscapedAsterisksSurviveStrongFallback() throws {
        let source = #"**重点。 **正文与 `**代码**`、\*\*字面星号\*\*，以及[**来源。**](https://example.com/a**b**)。"#
        let rendered = InlineMarkdown.parse(source)
        #expect(String(rendered.characters) == "重点。 正文与 **代码**、**字面星号**，以及来源。。")
        let code = try #require(rendered.range(of: "**代码**"))
        #expect(rendered[code].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.code) == true })
        let literal = try #require(rendered.range(of: "**字面星号**"))
        #expect(rendered[literal].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) != true })
        let link = try #require(rendered.range(of: "来源。"))
        #expect(rendered[link].runs.allSatisfy { $0.link?.absoluteString == "https://example.com/a**b**" })
        #expect(rendered[link].runs.allSatisfy { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    @Test func standardNestedEmphasisAndUnfinishedStreamsKeepTheirText() throws {
        let rendered = InlineMarkdown.parse("**事实与*解释***，以及**未生成完")
        #expect(String(rendered.characters) == "事实与解释，以及**未生成完")
        let nested = try #require(rendered.range(of: "解释"))
        #expect(rendered[nested].runs.allSatisfy { $0.inlinePresentationIntent?.contains([.emphasized, .stronglyEmphasized]) == true })
        #expect(String(InlineMarkdown.parse("** 尚未闭合").characters) == "** 尚未闭合")
    }
}
