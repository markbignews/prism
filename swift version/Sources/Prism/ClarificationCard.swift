import SwiftUI

/// The same inline surface as timeline approval; no modal window is presented.
struct ClarificationCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var chatStore: ChatStore
    let request: UserClarification
    @Binding var draft: ClarificationDraft
    var maxBodyHeight: CGFloat = 120
    var onSubmit: (ClarificationSubmission) -> Void
    @State private var collapsed = false

    private func text(_ simplified: String, _ traditional: String, _ english: String) -> String {
        ProviderFailure.localized(simplified, traditional, english, language: settings.language)
    }
    private var canSubmit: Bool {
        !chatStore.isSending && !chatStore.isSummarizing
            && chatStore.pendingClarification?.id == request.id
            && request.response(selectedOption: draft.selectedOption, customText: draft.customText, language: settings.language) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if collapsed {
                HStack(spacing: 8) {
                    Label(request.question, systemImage: "questionmark.bubble")
                        .font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                    Button(text("展开回答", "展開回答", "Answer")) { collapsed = false }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(request.question, systemImage: "questionmark.bubble")
                            .font(.caption.weight(.semibold))
                            .textSelection(.enabled)
                        ForEach(request.options.indices, id: \.self) { index in
                            let option = request.options[index]
                            Button {
                                draft.selectedOption = draft.selectedOption == index ? nil : index
                            } label: {
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: draft.selectedOption == index ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(draft.selectedOption == index ? Color.accentColor : .secondary)
                                    Text(option.label).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }
                                .font(.caption)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(option.description)
                            .accessibilityLabel(option.label + (option.description.isEmpty ? "" : ". " + option.description))
                            .accessibilityValue(draft.selectedOption == index ? text("已选择", "已選擇", "Selected") : "")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxBodyHeight)
                .scrollBounceBehavior(.basedOnSize)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.customText)
                        .font(.caption)
                        .scrollContentBackground(.hidden)
                        .accessibilityLabel(text("手动回答或补充", "手動回答或補充", "Your answer or additional detail"))
                    if draft.customText.isEmpty {
                        Text(text("也可直接手动回答，或补充选项…", "也可直接手動回答，或補充選項…", "Type your answer or add detail…"))
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.horizontal, 5).padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 36)
                .padding(5)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                if draft.customText.trimmingCharacters(in: .whitespacesAndNewlines).count > 8_000 {
                    Text(text("补充最多 8000 字。", "補充最多 8000 字。", "Maximum 8,000 characters."))
                        .font(.caption2).foregroundStyle(.red)
                }
                HStack(spacing: 8) {
                    Button(text("提交并继续", "提交並繼續", "Submit and continue")) {
                        guard canSubmit else { return }
                        onSubmit(.init(requestID: request.id, selectedOption: draft.selectedOption, customText: draft.customText))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)
                    Button(text("收起，稍后回答", "收起，稍後回答", "Answer later")) { collapsed = true }
                        .buttonStyle(.bordered)
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
