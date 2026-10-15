import SwiftUI

struct ModelDiscoverySection: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    Task { await settings.refreshModels() }
                } label: {
                    Label(L10n.text(.fetchModels, settings.language), systemImage: "arrow.clockwise")
                }
                .disabled(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.isFetchingModels)
                if settings.isFetchingModels {
                    ProgressView().controlSize(.small)
                }
            }
            Text(L10n.text(.modelListHint, settings.language))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = settings.modelCatalogError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            Picker(L10n.text(.conversationModel, settings.language), selection: $settings.model) {
                ForEach(settings.modelChoices) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            TextField(L10n.text(.manualConversationModel, settings.language), text: $settings.model)
                .textFieldStyle(.roundedBorder)
            Picker(L10n.text(.auxiliaryModel, settings.language), selection: $settings.flashModel) {
                ForEach(settings.modelChoices) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            TextField(L10n.text(.manualAuxiliaryModel, settings.language), text: $settings.flashModel)
                .textFieldStyle(.roundedBorder)
        }
        .task(id: settings.modelCatalogRevision) {
            guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            await settings.refreshModels()
        }
    }
}
