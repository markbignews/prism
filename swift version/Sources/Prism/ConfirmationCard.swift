import SwiftUI

/// Reserve space for the composer and conversation even when several reviews
/// arrive together. Only explanatory text scrolls; decision buttons stay visible.
enum ConfirmationLayout {
    static func bodyHeight(availableHeight: CGFloat, cardCount: Int) -> CGFloat {
        let height = availableHeight.isFinite ? max(0, availableHeight) : 680
        let count = max(1, cardCount)
        return max(36, min(160, height * 0.4 / CGFloat(count) - 64))
    }
}

struct ConfirmationCard<Content: View, Actions: View>: View {
    var maxBodyHeight: CGFloat
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: maxBodyHeight)
            .scrollBounceBehavior(.basedOnSize)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions() }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { actions() }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
