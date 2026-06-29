import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        Form {
            Section(L10n.text(.autoSummarization, settings.language)) {
                Picker(L10n.text(.summaryInterval, settings.language), selection: $settings.summaryDialogCount) {
                    Text(L10n.text(.intervalOff, settings.language)).tag(0)
                    Text(L10n.text(.dialog2, settings.language)).tag(2)
                    Text(L10n.text(.dialog5, settings.language)).tag(5)
                    Text(L10n.text(.dialog10, settings.language)).tag(10)
                }
                .pickerStyle(.menu)

                Text(L10n.text(.autoSummaryHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text(.deepSeek, settings.language)) {
                SecureField(L10n.text(.apiKey, settings.language), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)

                TextField(L10n.text(.baseURL, settings.language), text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)

                Picker(L10n.text(.conversationModel, settings.language), selection: $settings.model) {
                    Text("DeepSeek V4 Pro").tag("deepseek-v4-pro")
                    Text("DeepSeek V4 Flash").tag("deepseek-v4-flash")
                }
            }

            Section(L10n.text(.proParameters, settings.language)) {
                ModelParameterSection(
                    parameters: Binding(
                        get: { settings.parameters },
                        set: { settings.parameters = $0 }
                    ),
                    showThinking: true
                )
            }

            Section(L10n.text(.flashParameters, settings.language)) {
                ModelParameterSection(
                    parameters: Binding(
                        get: { settings.flashParameters },
                        set: { settings.flashParameters = $0 }
                    ),
                    showThinking: true
                )
            }

            Section(L10n.text(.interface, settings.language)) {
                Picker(L10n.text(.language, settings.language), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L10n.languageName(language, in: settings.language)).tag(language)
                    }
                }

                Picker(L10n.text(.responseLength, settings.language), selection: $settings.responseLength) {
                    Text(L10n.text(.modeBrief, settings.language)).tag(ResponseLength.brief)
                    Text(L10n.text(.modeStandard, settings.language)).tag(ResponseLength.standard)
                    Text(L10n.text(.modeDetailed, settings.language)).tag(ResponseLength.detailed)
                }
                .pickerStyle(.segmented)

                Text(L10n.text(.responseLengthHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.text(.storage, settings.language)) {
                Toggle(L10n.text(.useiCloud, settings.language), isOn: $settings.useiCloud)
                    .toggleStyle(.switch)

                if settings.useiCloud {
                    Label(L10n.text(.iCloudActive, settings.language), systemImage: "icloud.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text(L10n.text(.dataPath, settings.language))
                        .frame(width: 80, alignment: .leading)
                    Text(settings.dataPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.text(.choose, settings.language)) {
                        chooseFolder()
                    }
                    .disabled(settings.useiCloud)
                }

                Text(L10n.text(.dataPathHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    showResetAlert = true
                } label: {
                    Label(L10n.text(.reset, settings.language), systemImage: "arrow.counterclockwise")
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .alert(L10n.text(.resetTitle, settings.language), isPresented: $showResetAlert) {
            Button(L10n.text(.resetButton, settings.language), role: .destructive) {
                settings.resetAll()
                NSApplication.shared.terminate(nil)
            }
            Button(L10n.text(.cancel, settings.language), role: .cancel) {}
        } message: {
            Text(L10n.text(.resetMessage, settings.language))
        }
    }

    @State private var showResetAlert = false

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = L10n.text(.choose, settings.language)
        panel.message = L10n.text(.dataPathHint, settings.language)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let oldPath = settings.dataPath
        settings.dataPath = url.path
        if oldPath != url.path {
            chatStore.reloadStorage(from: settings)
        }
    }
}

struct ParameterSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var format: String

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 140, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: format, value))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
    }
}

struct ModelParameterSection: View {
    @EnvironmentObject private var settings: AppSettings
    @Binding var parameters: ModelParameters
    var showThinking: Bool

    var body: some View {
        Group {
            if showThinking {
                Toggle(L10n.text(.thinkingMode, settings.language), isOn: Binding(
                    get: { parameters.thinkingEnabled },
                    set: { parameters.thinkingEnabled = $0 }
                ))

                Picker(L10n.text(.reasoningEffort, settings.language), selection: Binding(
                    get: { parameters.reasoningEffort },
                    set: { parameters.reasoningEffort = $0 }
                )) {
                    Text(L10n.text(.high, settings.language)).tag("high")
                    Text(L10n.text(.max, settings.language)).tag("max")
                }
                .disabled(!parameters.thinkingEnabled)

                Text(L10n.text(.thinkingHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
