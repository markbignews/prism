import SwiftUI

struct TimelineWordingView: View {
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var settings: AppSettings
    let events: [NarrativeEvent]

    private var isLoading: Bool {
        chatStore.timelineWordingConversationID == chatStore.selectedConversationID && chatStore.timelineWordingIsLoading
    }

    private var failed: Bool {
        chatStore.timelineWordingConversationID == chatStore.selectedConversationID && chatStore.timelineWordingFailed
    }

    private var requestKey: String {
        (chatStore.selectedConversationID?.uuidString ?? "") + ":" + settings.language.rawValue + ":" + TimelineWording.fingerprint(events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let ordered = TimelineWording.ordered(events)
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, event in
                TimelineSentenceRow(event: event, language: settings.language, isLast: index == ordered.count - 1)
            }
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text(.timelineUnifyingWording, settings.language)).font(.caption)
                }
                .foregroundStyle(.secondary)
            } else if failed {
                Text(L10n.text(.timelineWordingFailed, settings.language))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(L10n.text(.timelineUnifyWording, settings.language)) {
                guard let id = chatStore.selectedConversationID else { return }
                Task { await chatStore.unifyTimelineWording(conversationID: id, settings: settings, force: true) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .disabled(isLoading || chatStore.hasStorageFailure)

            DisclosureGroup(L10n.text(.timelineOriginalNodes, settings.language)) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ordered) { event in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.caption.weight(.medium))
                            Text([event.startLabel, event.endLabel].filter { !$0.isEmpty }.joined(separator: " – "))
                                .font(.caption)
                            if !event.summary.isEmpty { Text(event.summary).font(.caption) }
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 6)
                .textSelection(.enabled)
            }
            .font(.caption)
        }
        .task(id: requestKey) {
            guard let id = chatStore.selectedConversationID else { return }
            // Coalesce rapidly approved nodes before starting a model request.
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await chatStore.unifyTimelineWording(conversationID: id, settings: settings)
        }
    }
}

struct TimelineSentenceRow: View {
    let event: NarrativeEvent
    let language: AppLanguage
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: event.timeKind == "date" ? "calendar" : "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.indigo)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.indigo.opacity(0.12)))
                if !isLast { Rectangle().fill(.quaternary).frame(width: 2, height: 22) }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let text = TimelineWording.currentText(for: event, language: language) {
                    Text(text).font(.callout)
                } else {
                    Text(L10n.text(.timelineSourceWording, language))
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text([event.startLabel, event.endLabel].filter { !$0.isEmpty }.joined(separator: " – "))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(event.summary.isEmpty ? event.title : event.summary).font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
    }
}
