import SwiftUI

struct NarrativeTimelineView: View {
    let events: [NarrativeEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let ordered = TimelineWording.ordered(events)
            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, event in
                TimelineSentenceRow(event: event, isLast: index == ordered.count - 1)
            }
        }
    }
}

struct TimelineSentenceRow: View {
    let event: NarrativeEvent
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
                Text([event.startLabel, event.endLabel].filter { !$0.isEmpty }.joined(separator: " – "))
                    .font(.caption).foregroundStyle(.secondary)
                Text(event.title).font(.callout.weight(.medium))
                if !event.summary.isEmpty && event.summary != event.title {
                    Text(event.summary).font(.callout)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
        }
    }
}
