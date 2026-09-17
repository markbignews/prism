import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var apiKey = "" {
        didSet { saveConfig() }
    }
    @Published var baseURL = "https://api.deepseek.com" {
        didSet { saveConfig() }
    }
    @Published var model = "deepseek-flash" {
        didSet { saveConfig() }
    }
    @Published var flashModel = "deepseek-flash" {
        didSet { saveConfig() }
    }
    @Published var language: AppLanguage = .simplifiedChinese {
        didSet { saveConfig() }
    }
    @Published var parameters = ModelParameters() {
        didSet { saveConfig() }
    }
    @Published var flashParameters = ModelParameters(
        thinkingEnabled: true, reasoningEffort: "high"
    ) {
        didSet { saveConfig() }
    }
    @Published var summaryDialogCount = 5 {
        didSet { saveConfig() }
    }
    /// Context message window for the agent's history injection; 0 keeps everything.
    @Published var contextWindow = 60 {
        didSet { saveConfig() }
    }
    /// Write a prism.log file next to the data directory.
    @Published var enableLogging = true {
        didSet {
            saveConfig()
            PrismLog.setEnabled(enableLogging)
        }
    }
    @Published var showReasoningPanel = true {
        didSet { saveConfig() }
    }
    @Published var onboardingCompleted = false {
        didSet { saveConfig() }
    }
    @Published var conversationMode: ConversationMode = .balanced {
        didSet { saveConfig() }
    }
    @Published var responseLength: ResponseLength = .standard {
        didSet { saveConfig() }
    }
    /// Latest provider metadata fetched without invoking a model.
    @Published private(set) var providerBalance: DeepSeekBalanceResponse? = nil
    @Published private(set) var balanceUnavailable = false

    @Published var storageError: String?
    var canChangeStorage: () -> Bool = { true }

    /// Only dataPath stays in UserDefaults — it's the bootstrap key.
    @Published var dataPath: String {
        didSet {
            guard oldValue != dataPath else { return }
            do {
                guard canChangeStorage() else { throw SQLiteStore.Failure(message: "Wait for the active reply or summary before changing folders.") }
                guard !dataPath.contains("/Library/Mobile Documents/") else { throw SQLiteStore.Failure(message: "Choose a local folder; iCloud storage has been removed.") }
                if !oldValue.isEmpty { try migrateData(from: oldValue, to: dataPath) }
                UserDefaults.standard.set(dataPath, forKey: "storage.dataPath")
                PrismLog.configure(dataPath: dataPath)
                UsageStatsStore.shared.configure(dataPath: dataPath)
                storageError = nil
                saveConfig()
            } catch { dataPath = oldValue; storageError = error.localizedDescription }
        }
    }

    // MARK: - Local storage

    private static let localDefaultPath: String =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Prism").path

    // MARK: - Init

    init() {
        let defaultDataPath = Self.localDefaultPath
        dataPath = UserDefaults.standard.string(forKey: "storage.dataPath") ?? defaultDataPath
        do {
            dataPath = try SQLiteStore.localRoot(URL(fileURLWithPath: dataPath)).path
            UserDefaults.standard.set(dataPath, forKey: "storage.dataPath")
        } catch { storageError = error.localizedDescription }
        PrismLog.configure(dataPath: dataPath)
        UsageStatsStore.shared.configure(dataPath: dataPath)

        // Migrate legacy UserDefaults keys → config.json
        let legacyKey = UserDefaults.standard.string(forKey: "deepseek.apiKey") ?? ""

        // Load from config.json in data directory
        loadConfig(legacyAPIKey: legacyKey)
        PrismLog.setEnabled(enableLogging)

        // If migrated, clear legacy UserDefaults
        if !legacyKey.isEmpty {
            for k in ["deepseek.apiKey", "deepseek.baseURL", "deepseek.model",
                      "deepseek.flashModel", "ui.language", "deepseek.parameters",
                      "deepseek.flashParameters", "agent.summaryDialogCount",
                      "agent.summaryIntervalMinutes", "ui.showReasoningPanel"] {
                UserDefaults.standard.removeObject(forKey: k)
            }
        }
    }

    /// Refresh the DeepSeek account balance in the background. The endpoint
    /// returns account metadata only, so this does not consume model tokens.
    func refreshProviderBalance() async {
        let parameters = model.lowercased().contains("flash") ? flashParameters : self.parameters
        let client = DeepSeekClient(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            parameters: parameters,
            language: language
        )
        do {
            providerBalance = try await client.fetchBalance()
            balanceUnavailable = false
        } catch {
            providerBalance = nil
            balanceUnavailable = true
        }
    }

    // MARK: - Config Persistence

    private var configURL: URL {
        URL(fileURLWithPath: dataPath).appendingPathComponent("config.json")
    }

    private struct ConfigFile: Codable {
        var apiKey = ""
        var baseURL = "https://api.deepseek.com"
        var model = "deepseek-flash"
        var flashModel = "deepseek-flash"
        var language = "zh-Hans"
        var parameters = ModelParameters()
        var flashParameters = ModelParameters()
        var summaryDialogCount = 5
        var contextWindow = 60
        var enableLogging = true
        var showReasoningPanel = true
        var onboardingCompleted = false
        var conversationMode = "balanced"
        var responseLength = "standard"
    }

    private func loadConfig(legacyAPIKey: String = "") {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            // No config file yet — adopt an earlier Prism settings.json if present.
            if importLegacySettingsIfNeeded() { return }
            // Otherwise use defaults, migrating legacy API key if present
            if !legacyAPIKey.isEmpty { apiKey = legacyAPIKey }
            return
        }
        apiKey = config.apiKey.isEmpty ? legacyAPIKey : config.apiKey
        baseURL = config.baseURL
        model = config.model
        flashModel = config.flashModel
        language = AppLanguage(rawValue: config.language) ?? .simplifiedChinese
        parameters = config.parameters
        flashParameters = config.flashParameters
        // Prism intentionally maintains the two current conversation models.
        // Retired aliases and past custom selections migrate to Flash.
        let supportedModel = DeepSeekModels.supportedConversationModel(
            DeepSeekModels.canonical(model, baseURL: baseURL)
        )
        let migratedModelDefaults = supportedModel != model || flashModel != DeepSeekModels.flash
        model = supportedModel
        flashModel = DeepSeekModels.flash
        summaryDialogCount = config.summaryDialogCount
        contextWindow = config.contextWindow
        enableLogging = config.enableLogging
        showReasoningPanel = config.showReasoningPanel
        onboardingCompleted = config.onboardingCompleted
        conversationMode = ConversationMode(rawValue: config.conversationMode) ?? .balanced
        responseLength = ResponseLength(rawValue: config.responseLength) ?? .standard

        if migratedModelDefaults { saveConfig() }
    }

    // MARK: - Legacy settings.json Import

    /// Earlier Prism builds wrote camelCase `settings.json` into the data directory.
    /// When config.json is absent, adopt those settings once for continuity.
    private func importLegacySettingsIfNeeded() -> Bool {
        let legacySettingsURL = URL(fileURLWithPath: dataPath).appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: legacySettingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let baseURL = json["baseURL"] as? String ?? json["base_url"] as? String else {
            return false
        }

        self.baseURL = baseURL
        apiKey = json["apiKey"] as? String ?? json["api_key"] as? String ?? ""
        flashModel = DeepSeekModels.flash
        let conversationModel = json["conversationModel"] as? String ?? json["conversation_model"] as? String ?? "flash"
        model = conversationModel == "pro" ? DeepSeekModels.pro : DeepSeekModels.flash

        let lang = json["language"] as? String ?? "en"
        language = switch lang.lowercased() {
        case "zh", "zh-cn", "zh-hans": .simplifiedChinese
        case "zh-hant", "zh-tw": .traditionalChinese
        default: .english
        }
        let defaultMode = json["defaultMode"] as? String ?? json["default_mode"] as? String ?? "balanced"
        conversationMode = ConversationMode(rawValue: defaultMode) ?? .balanced
        let length = json["responseLength"] as? String ?? json["response_length"] as? String ?? "standard"
        responseLength = ResponseLength(rawValue: length) ?? .standard
        summaryDialogCount = json["summaryInterval"] as? Int ?? json["summary_interval"] as? Int ?? 5
        contextWindow = json["contextWindow"] as? Int ?? json["context_window"] as? Int ?? 60
        enableLogging = json["enableLogging"] as? Bool ?? json["enable_logging"] as? Bool ?? true

        parameters.thinkingEnabled = json["proThinkingEnabled"] as? Bool ?? true
        parameters.reasoningEffort = json["proReasoningEffort"] as? String ?? "high"
        flashParameters.thinkingEnabled = json["flashThinkingEnabled"] as? Bool ?? true
        flashParameters.reasoningEffort = json["flashReasoningEffort"] as? String ?? "high"


        print("[AppSettings] imported legacy settings.json from \(dataPath)")
        return true
    }

    // MARK: - Reset

    /// Delete all data files and reset settings to factory defaults.
    /// Triggered from Settings → Reset. App needs a restart afterwards.
    func resetAll() {
        let folder = URL(fileURLWithPath: dataPath)

        guard canChangeStorage() else { storageError = "Wait for the active operation before resetting."; return }
        do { try SQLiteStore(root: folder).clear() }
        catch { storageError = error.localizedDescription; return }
        // Original JSON and migration backups are retained; the database's
        // import markers prevent them from being re-imported after reset.

        // Delete config
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("usage_stats.json"))

        // Reset UserDefaults, including per-conversation safety context and
        // the installation identifier that would otherwise survive a reset.
        UserDefaults.standard.removeObject(forKey: "storage.dataPath")
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("safety.") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.removeObject(forKey: "ui.lastConversationID")
        UserDefaults.standard.removeObject(forKey: "deepseek.userID")

        // Reset published properties to defaults (didSet will save new config)
        apiKey = ""
        baseURL = "https://api.deepseek.com"
        model = "deepseek-flash"
        flashModel = "deepseek-flash"
        language = .simplifiedChinese
        parameters = ModelParameters()
        flashParameters = ModelParameters(
            thinkingEnabled: true, reasoningEffort: "high"
        )
        UsageStatsStore.shared.reset()
        summaryDialogCount = 5
        contextWindow = 60
        enableLogging = true
        showReasoningPanel = true
        onboardingCompleted = false
        responseLength = .standard

    }

    // MARK: - Data Migration

    /// Copy all data files from the old storage path to the new one.
    /// Existing files at the destination are never overwritten.
    func migrateData(from oldPath: String, to newPath: String) throws {
        let fm = FileManager.default
        let old = URL(fileURLWithPath: oldPath)
        let target = URL(fileURLWithPath: newPath)
        if fm.fileExists(atPath: target.appendingPathComponent("prism.sqlite3").path) {
            throw SQLiteStore.Failure(message: "Destination already contains a database. Choose an empty local folder.")
        }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        for name in ["conversations.json", "usage_stats.json", "Data"] {
            let source = old.appendingPathComponent(name), destination = target.appendingPathComponent(name)
            if fm.fileExists(atPath: source.path), !fm.fileExists(atPath: destination.path) { try fm.copyItem(at: source, to: destination) }
        }
        // Write the database last. A failed legacy-file copy therefore leaves
        // the destination retryable instead of creating a partial database.
        if fm.fileExists(atPath: old.appendingPathComponent("prism.sqlite3").path) {
            try SQLiteStore(root: old).backup(to: target.appendingPathComponent("prism.sqlite3"))
        }
    }

    private func saveConfig() {
        let folder = URL(fileURLWithPath: dataPath)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            storageError = error.localizedDescription
            return
        }

        let config = ConfigFile(
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            flashModel: flashModel,
            language: language.rawValue,
            parameters: parameters,
            flashParameters: flashParameters,
            summaryDialogCount: summaryDialogCount,
            contextWindow: contextWindow,
            enableLogging: enableLogging,
            showReasoningPanel: showReasoningPanel,
            onboardingCompleted: onboardingCompleted,
            conversationMode: conversationMode.rawValue,
            responseLength: responseLength.rawValue
        )
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            storageError = error.localizedDescription
        }
    }
}

extension Notification.Name {
    /// Posted when the user changes the data storage path.
    static let prismDataPathChanged = Notification.Name("prismDataPathChanged")
}
