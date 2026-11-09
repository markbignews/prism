import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var chatStore: ChatStore
    @ObservedObject private var usageStatsStore = UsageStatsStore.shared

    var body: some View {
        Form {
            Section(L10n.text(.modelUsage, settings.language)) {
                usageBlock
            }

            if let error = settings.storageError {
                Text(error).foregroundStyle(.red)
                Button(L10n.text(.retryStorage, settings.language)) { settings.retryCredentialStorage() }
            }
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
                SingleLineSecretField(placeholder: L10n.text(.apiKey, settings.language), text: $settings.apiKey)
                    .frame(height: 24)
                    .padding(6)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))

                Text(ProviderFailure.localized("API Key 明文保存在本机配置文件中，不访问钥匙串。", "API Key 以明文儲存在本機設定檔中，不存取鑰匙圈。", "The API key is saved in a local plaintext configuration file. Keychain is not accessed.", language: settings.language))
                    .font(.caption).foregroundStyle(.secondary)
                if settings.needsCredentialReentry {
                    Text(ProviderFailure.localized("旧版密钥保存在钥匙串中，请重新粘贴一次。", "舊版密鑰儲存在鑰匙圈中，請重新貼上一次。", "Your previous key was stored in Keychain. Please paste it here once.", language: settings.language))
                        .font(.caption).foregroundStyle(.secondary)
                }

                TextField(L10n.text(.baseURL, settings.language), text: $settings.baseURL)
                    .textFieldStyle(.roundedBorder)

                ModelDiscoverySection()

            }

            Section(L10n.text(.proParameters, settings.language)) {
                ModelParameterSection(
                    parameters: Binding(
                        get: { settings.usesFlashParameters ? settings.flashParameters : settings.parameters },
                        set: { if settings.usesFlashParameters { settings.flashParameters = $0 } else { settings.parameters = $0 } }
                    ),
                    showThinking: true
                )
            }

            Section(L10n.text(.flashParameters, settings.language)) {
                Text(ProviderFailure.localized("辅助模型用于摘要、章节整理和后台检查，不负责直接回复。后台任务固定关闭深度思考；对话的思考设置以上方为准。", "輔助模型用於摘要、章節整理和背景檢查，不負責直接回覆。背景任務固定關閉深度思考；對話的思考設定以上方為準。", "The auxiliary model handles summaries, chapters and background checks. These tasks use thinking disabled; the controls above apply to conversation replies.", language: settings.language))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.text(.interface, settings.language)) {
                Picker(L10n.text(.language, settings.language), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(L10n.languageName(language, in: settings.language)).tag(language)
                    }
                }

                Picker(L10n.text(.conversationMode, settings.language), selection: $settings.conversationMode) {
                    Text(L10n.text(.modeRational, settings.language)).tag(ConversationMode.rational)
                    Text(L10n.text(.modeBalanced, settings.language)).tag(ConversationMode.balanced)
                    Text(L10n.text(.modeWarm, settings.language)).tag(ConversationMode.warm)
                }
                .pickerStyle(.segmented)

                Text(L10n.text(.conversationModeHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L10n.text(.responseLength, settings.language), selection: $settings.responseLength) {
                    Text(L10n.text(.modeBrief, settings.language)).tag(ResponseLength.brief)
                    Text(L10n.text(.modeStandard, settings.language)).tag(ResponseLength.standard)
                    Text(L10n.text(.modeDetailed, settings.language)).tag(ResponseLength.detailed)
                }
                .pickerStyle(.segmented)

                Text(L10n.text(.responseLengthHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(L10n.text(.contextWindow, settings.language))
                    Spacer()
                    Text(ProviderFailure.localized("按模型容量管理", "依模型容量管理", "Managed by model capacity", language: settings.language))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Text(L10n.text(.contextWindowHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(L10n.text(.enableLogging, settings.language), isOn: $settings.enableLogging)
                    .toggleStyle(.switch)

                Text(L10n.text(.loggingHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label {
                    Text(L10n.text(.aiLabelDisclaimer, settings.language))
                } icon: {
                    Image(systemName: "info.circle")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Section(L10n.text(.storage, settings.language)) {
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
                        showFolderImporter = true
                    }
                    .disabled(chatStore.isSending || chatStore.isSummarizing)
                }

                Text(L10n.text(.dataPathHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L10n.text(.openDataFolder, settings.language)) {
                    NSWorkspace.shared.open(URL(fileURLWithPath: settings.dataPath))
                }
                Button(L10n.text(.exportSnapshot, settings.language)) {
                    NativeSupport.exportSnapshot(chatStore, language: settings.language)
                }
                Button(L10n.text(.importSnapshot, settings.language)) { showImportAlert = true }
                    .disabled(chatStore.isSending || chatStore.isSummarizing || chatStore.hasStorageFailure)
                Text(L10n.text(.importSnapshotHint, settings.language)).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button {
                    NativeSupport.exportLog(from: settings.dataPath)
                } label: {
                    Label(L10n.text(.exportLogs, settings.language), systemImage: "square.and.arrow.up")
                }

                Text(L10n.text(.exportLogsHint, settings.language))
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
        .onAppear {
            usageStatsStore.reload()
            if settings.providerBalance == nil {
                Task { await settings.refreshProviderBalance() }
            }
        }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            guard !chatStore.isSending, !chatStore.isSummarizing else { return }
            settings.dataPath = url.path
        }
        .alert(L10n.text(.resetTitle, settings.language), isPresented: $showResetAlert) {
            Button(L10n.text(.resetButton, settings.language), role: .destructive) {
                if settings.resetAll() { NativeSupport.quitApp() }
            }
            Button(L10n.text(.cancel, settings.language), role: .cancel) {}
        } message: {
            Text(L10n.text(.resetMessage, settings.language))
        }
        .confirmationDialog(L10n.text(.importSnapshot, settings.language), isPresented: $showImportAlert) {
            Button(L10n.text(.importSnapshot, settings.language), role: .destructive) {
                NativeSupport.importSnapshot(chatStore, language: settings.language)
            }
        } message: { Text(L10n.text(.importSnapshotHint, settings.language)) }
    }

    @State private var showResetAlert = false
    @State private var showImportAlert = false
    @State private var showFolderImporter = false
}

private extension SettingsView {
    var usageBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                usageMetric(L10n.text(.inputTokens, settings.language), tokenText(usageStatsStore.stats.inputTokens))
                usageMetric(L10n.text(.outputTokens, settings.language), tokenText(usageStatsStore.stats.outputTokens))
                usageMetric(
                    L10n.text(.cacheHitRate, settings.language),
                    usageStatsStore.stats.cacheHitRate.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
                )
            }

            HStack(spacing: 12) {
                usageMetric(ProviderFailure.localized("已报告的思考 token", "已回報的思考 token", "Reported reasoning tokens", language: settings.language),
                    usageStatsStore.stats.reportedReasoningTokens.map(tokenText) ?? "—")
                usageMetric(ProviderFailure.localized("后台请求", "背景請求", "Background requests", language: settings.language),
                    tokenText(usageStatsStore.stats.backgroundRequests ?? 0))
                usageMetric(ProviderFailure.localized("上下文整理请求", "上下文整理請求", "Context summary requests", language: settings.language),
                    tokenText(usageStatsStore.stats.compactionRequests ?? 0))
            }
            if let report = chatStore.selectedConversation?.optimizationReport, report.beforeTokens > 0 {
                Text(ProviderFailure.localized("最近请求估算：", "最近請求估算：", "Latest request estimate: ", language: settings.language)
                     + "\(report.beforeTokens) → \(report.afterTokens) token")
                    .font(.caption).foregroundStyle(.secondary)
                if let actual = report.observedInputTokens {
                    Text(ProviderFailure.localized("服务商最近报告的输入：", "服務商最近回報的輸入：", "Last provider-reported input: ", language: settings.language)
                         + "\(actual) token")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if report.summaryFailed {
                    Text(ProviderFailure.localized("这次自动整理未完成，原始内容已保留。", "這次自動整理未完成，原始內容已保留。", "Automatic context summary did not finish; originals were retained.", language: settings.language))
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            if let providerBalance = settings.providerBalance, !providerBalance.balanceInfos.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.accountBalance, settings.language))
                        .font(.caption.weight(.semibold))
                    ForEach(providerBalance.balanceInfos) { info in
                        HStack {
                            Text(info.currency).font(.caption.monospaced())
                            Spacer()
                            Text("\(info.totalBalance)  ·  \(L10n.text(.grantedBalance, settings.language)): \(info.grantedBalance)  ·  \(L10n.text(.toppedUpBalance, settings.language)): \(info.toppedUpBalance)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
            } else if settings.balanceUnavailable {
                Text(L10n.text(.balanceUnavailable, settings.language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    func usageMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
    }

    func tokenText(_ value: Int64) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
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

                Toggle(ProviderFailure.localized("按任务自动调整思考", "依任務自動調整思考", "Adapt thinking to the task", language: settings.language), isOn: Binding(
                    get: { parameters.adaptiveThinking != false },
                    set: { parameters.adaptiveThinking = $0 }
                ))
                .disabled(!parameters.thinkingEnabled)
                Text(ProviderFailure.localized("普通承接和工具选择优先用较低强度；需要深入分析时提高到你设置的强度。仅对官方 DeepSeek 服务启用自动调整。", "一般承接與工具選擇優先用較低強度；需要深入分析時提高至你設定的強度。僅對官方 DeepSeek 服務啟用自動調整。", "Use lower effort for initial replies and tool selection, and your chosen effort for deeper analysis. Automatic adjustment applies only to official DeepSeek routes.", language: settings.language))
                    .font(.caption).foregroundStyle(.secondary)

                Picker(L10n.text(.reasoningEffort, settings.language), selection: Binding(
                    get: { parameters.reasoningEffort },
                    set: { parameters.reasoningEffort = $0 }
                )) {
                    Text("Low").tag("low")
                    Text(L10n.text(.high, settings.language)).tag("high")
                    Text(L10n.text(.max, settings.language)).tag("max")
                }
                .disabled(!parameters.thinkingEnabled)

                TextField(ProviderFailure.localized("模型可阅读长度（token）", "模型可閱讀長度（token）", "Model context window (tokens)", language: settings.language), value: Binding(
                    get: { ContextPolicy.resolve(client: DeepSeekClient(apiKey: "", baseURL: settings.baseURL,
                        model: settings.model, parameters: parameters, language: settings.language)).window },
                    set: { parameters.contextWindowTokens = min(32_000_000, max(8192, $0)) }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                Text(ProviderFailure.localized("应与服务商公布的模型上限一致。未识别的模型先按保守值估算；这不是实际计费数量。", "應與服務商公布的模型上限一致。未識別的模型先依保守值估算；這不是實際計費數量。", "Match your provider's model limit. Unrecognized models start with a conservative estimate; this is not a billing count.", language: settings.language))
                    .font(.caption).foregroundStyle(.secondary)

                Text(L10n.text(.thinkingHint, settings.language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
