import SwiftUI
import AppKit

/// NSTextView provides native wheel/trackpad scrolling, selection, find and IME.
struct ScrollableComposer: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> ComposerScrollView {
        let scroll = ComposerScrollView()
        let editor = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        editor.delegate = context.coordinator
        editor.onSubmit = onSubmit
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.textContainerInset = NSSize(width: 0, height: 4)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.textContainer?.lineFragmentPadding = 0
        editor.minSize = .zero
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.setAccessibilityLabel(placeholder)
        scroll.documentView = editor
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        return scroll
    }
    func updateNSView(_ scroll: ComposerScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        editor.onSubmit = onSubmit
        editor.setAccessibilityLabel(placeholder)
        // Do not replace the storage while an input method owns marked text.
        if editor.string != text, !editor.hasMarkedText() {
            editor.string = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            scroll.resizeDocument()
            editor.scrollRangeToVisible(editor.selectedRange())
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        return CGSize(width: width, height: nsView.measuredHeight(width: width))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScrollableComposer
        init(_ parent: ScrollableComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            (editor.enclosingScrollView as? ComposerScrollView)?.resizeDocument()
        }
    }
}

final class ComposerTextView: NSTextView {
    var onSubmit: () -> Void = {}
    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), !hasMarkedText(),
           event.modifierFlags.intersection([.shift, .option, .control]).isEmpty {
            onSubmit()
            return
        }
        super.keyDown(with: event)
    }
}

final class ComposerScrollView: NSScrollView {
    private var resizingDocument = false
    private var measuredText: String?
    private var measuredWidth: CGFloat = 0
    private var cachedHeight: CGFloat = 28

    func measuredHeight(width: CGFloat) -> CGFloat {
        guard let editor = documentView as? NSTextView else { return 28 }
        if measuredText == editor.string, measuredWidth == width { return cachedHeight }
        let font = editor.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        // Measurement must not mutate the live text container or view frame:
        // SwiftUI probes several widths, and those mutations trigger layout loops.
        let sample = editor.string.isEmpty ? " " : editor.string + (editor.string.hasSuffix("\n") ? " " : "")
        let size = (sample as NSString).boundingRect(with: NSSize(width: max(1, width - 12), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).size
        let line = NSLayoutManager().defaultLineHeight(for: font)
        cachedHeight = max(28, min(ceil(size.height + 8), ceil(line * 6 + 8)))
        measuredText = editor.string
        measuredWidth = width
        return cachedHeight
    }
    func resizeDocument() {
        guard !resizingDocument, contentSize.width > 20,
              let editor = documentView as? NSTextView,
              let layout = editor.layoutManager, let container = editor.textContainer else { return }
        resizingDocument = true
        defer { resizingDocument = false }
        let width = contentSize.width - 12
        if abs(editor.frame.width - width) > 0.5 {
            editor.setFrameSize(NSSize(width: width, height: max(28, editor.frame.height)))
        }
        if abs(container.containerSize.width - width) > 0.5 {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        let line = layout.defaultLineHeight(for: editor.font ?? .systemFont(ofSize: NSFont.systemFontSize))
        let used = layout.usedRect(for: container).height + (editor.string.hasSuffix("\n") ? line : 0)
        let height = max(contentSize.height, ceil(used + 8))
        if abs(editor.frame.height - height) > 0.5 { editor.setFrameSize(NSSize(width: width, height: height)) }
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resizeDocument()
    }
    override func layout() {
        super.layout()
        resizeDocument()
    }
}
