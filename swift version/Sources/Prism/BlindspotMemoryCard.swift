import SwiftUI

struct BlindspotMemoryCard: View {
    let group: BlindspotMemory.Group
    let language: AppLanguage
    var remove: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.latest.pattern).font(.headline)
                Spacer()
                Text(L10n.text(.memorySuspected, language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(L10n.text(.removeBlindspotGroup, language))
                .accessibilityLabel(L10n.text(.removeBlindspotGroup, language))
            }
            if !isExpanded {
                Text(group.latest.evidence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(group.observations) { observation in
                        VStack(alignment: .leading, spacing: 4) {
                            if group.observations.count > 1 {
                                Text(observation.createdAt, format: .dateTime.year().month().day())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Text(observation.evidence)
                                .foregroundStyle(.secondary)
                            if !observation.counterQuestion.isEmpty {
                                Text("\(L10n.text(.memoryCounterQuestion, language))：\(observation.counterQuestion)")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }
                .font(.caption)
                .padding(.top, 4)
                .textSelection(.enabled)
            } label: {
                Text(L10n.text(.memoryObservationDetails, language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
