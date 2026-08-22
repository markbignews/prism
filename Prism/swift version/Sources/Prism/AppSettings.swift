import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private static let modelDefaultsV3Key = "deepseek.modelDefaultsV3Applied"
    @Published var apiKey = "" {
        didSet { saveConfig() }
    }
    @Published var baseURL = "https://api.deepseek.com" {
        didSet { saveConfig() }
    }
    @Published var model = "deepseek-v4-flash" {
        didSet { saveConfig() }
    }
    @Published var flashModel = "deepseek-v4-flash" {
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
    /// Context message window for the agent's history injection
    /// (Tauri parity: `context_window`, default 60; 0 = keep everything).
    @Published var contextWindow = 60 {
        didSet { saveConfig() }
    }
    /// Write a prism.log file next to the data directory
    /// (Tauri parity: `enable_logging`).
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
    @Published var useiCloud = false {
        didSet {
            saveConfig()
            if oldValue != useiCloud {
                let target = useiCloud ? (iCloudPath ?? Self.localDefaultPath) : Self.localDefaultPath
                if dataPath != target {
                    dataPath = target
                }
            }
        }
    }

    /// Latest provider metadata fetched without invoking a model.
    @Published private(set) var providerBalance: DeepSeekBalanceResponse? = nil
    @Published private(set) var balanceUnavailable = false

    /// Only dataPath stays in UserDefaults — it's the bootstrap key.
    @Published var dataPath: String {
        didSet {
            UserDefaults.standard.set(dataPath, forKey: "storage.dataPath")
            PrismLog.configure(dataPath: dataPath)
            UsageStatsStore.shared.configure(dataPath: dataPath)
            if oldValue != dataPath, !oldValue.isEmpty {
                migrateData(from: oldValue, to: dataPath)
            }
        }
    }

    // MARK: - iCloud

    private static let localDefaultPath: String =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Prism").path

    var iCloudPath: String? {
        guard let url = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) else { return nil }
        return url.appendingPathComponent("Documents/Prism", isDirectory: true).path
    }

    func checkiCloudAvailability() -> Bool {
        iCloudPath != nil
    }

    // MARK: - Init

    init() {
        let defaultDataPath = Self.localDefaultPath
        dataPath = UserDefaults.standard.string(forKey: "storage.dataPath") ?? defaultDataPath
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
        var model = "deepseek-v4-flash"
        var flashModel = "deepseek-v4-flash"
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
        var useiCloud = false
    }

    private func loadConfig(legacyAPIKey: String = "") {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            // No config file yet — fall back to Tauri's settings.json when the
            // data directory is shared across implementations (Tauri parity:
            // Swift config.json is imported by the Tauri build, and vice versa).
            if importTauriSettingsIfNeeded() { return }
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
        if !UserDefaults.standard.bool(forKey: Self.modelDefaultsV3Key) {
            if parameters.reasoningEffort == "max" {
                parameters.reasoningEffort = "high"
            }
            if flashModel == "deepseek-v4-flash", flashParameters.reasoningEffort == "max" {
                flashParameters.reasoningEffort = "high"
            }
            UserDefaults.standard.set(true, forKey: Self.modelDefaultsV3Key)
        }
        summaryDialogCount = config.summaryDialogCount
        contextWindow = config.contextWindow
        enableLogging = config.enableLogging
        showReasoningPanel = config.showReasoningPanel
        onboardingCompleted = config.onboardingCompleted
        conversationMode = ConversationMode(rawValue: config.conversationMode) ?? .balanced
        responseLength = ResponseLength(rawValue: config.responseLength) ?? .standard
        useiCloud = config.useiCloud
    }

    // MARK: - Tauri settings.json Import

    /// Tauri writes `settings.json` (camelCase) into the data directory.
    /// When Prism Swift has no config.json yet, adopt the Tauri settings so
    /// both implementations stay in sync when sharing a data folder.
    private func importTauriSettingsIfNeeded() -> Bool {
        let tauriURL = URL(fileURLWithPath: dataPath).appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: tauriURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        guard let baseURL = json["baseURL"] as? String ?? json["base_url"] as? String else {
            return false
        }

        self.baseURL = baseURL
        apiKey = json["apiKey"] as? String ?? json["api_key"] as? String ?? ""
        let flash = json["flashModel"] as? String ?? json["flash_model"] as? String ?? "deepseek-v4-flash"
        let pro = json["proModel"] as? String ?? json["pro_model"] as? String ?? "deepseek-v4-pro"
        flashModel = flash
        let conversationModel = json["conversationModel"] as? String ?? json["conversation_model"] as? String ?? "flash"
        model = conversationModel == "pro" ? pro : flash

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

        useiCloud = json["icloudSync"] as? Bool ?? json["iCloudSync"] as? Bool ?? false
        print("[AppSettings] imported Tauri settings.json from \(dataPath)")
        return true
    }

    // MARK: - Reset

    /// Delete all data files and reset settings to factory defaults.
    /// Triggered from Settings → Reset. App needs a restart afterwards.
    func resetAll() {
        let folder = URL(fileURLWithPath: dataPath)

        // Delete conversations
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("conversations.json"))

        // Delete archives
        let archiveFolder = folder.appendingPathComponent("Data", isDirectory: true)
        try? FileManager.default.removeItem(at: archiveFolder)

        // Delete config
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("usage_stats.json"))

        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: "storage.dataPath")
        UserDefaults.standard.removeObject(forKey: Self.modelDefaultsV3Key)

        // Reset published properties to defaults (didSet will save new config)
        apiKey = ""
        baseURL = "https://api.deepseek.com"
        model = "deepseek-v4-flash"
        flashModel = "deepseek-v4-flash"
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
        useiCloud = false
    }

    // MARK: - Data Migration

    /// Copy all data files from the old storage path to the new one.
    /// Existing files at the destination are never overwritten.
    func migrateData(from oldPath: String, to newPath: String) {
        let fm = FileManager.default
        let oldDir = URL(fileURLWithPath: oldPath)
        let newDir = URL(fileURLWithPath: newPath)

        guard fm.fileExists(atPath: oldDir.path) else {
            print("[migrateData] old path does not exist: \(oldPath)")
            return
        }

        // Create destination directory
        do {
            try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        } catch {
            print("[migrateData] cannot create destination: \(error.localizedDescription)")
            return
        }

        // conversations.json
        let oldConv = oldDir.appendingPathComponent("conversations.json")
        let newConv = newDir.appendingPathComponent("conversations.json")
        if fm.fileExists(atPath: oldConv.path), !fm.fileExists(atPath: newConv.path) {
            do { try fm.copyItem(at: oldConv, to: newConv) }
            catch { print("[migrateData] conversations.json copy failed: \(error.localizedDescription)") }
        }

        let oldUsage = oldDir.appendingPathComponent("usage_stats.json")
        let newUsage = newDir.appendingPathComponent("usage_stats.json")
        if fm.fileExists(atPath: oldUsage.path), !fm.fileExists(atPath: newUsage.path) {
            try? fm.copyItem(at: oldUsage, to: newUsage)
        }

        // Data/ subdirectory (person_archive, emotion_timeline, blindspots)
        let oldArchive = oldDir.appendingPathComponent("Data", isDirectory: true)
        let newArchive = newDir.appendingPathComponent("Data", isDirectory: true)
        if fm.fileExists(atPath: oldArchive.path), !fm.fileExists(atPath: newArchive.path) {
            do { try fm.copyItem(at: oldArchive, to: newArchive) }
            catch { print("[migrateData] Data/ copy failed: \(error.localizedDescription)") }
        }

        // Re-save config to the new path
        saveConfig()

        NotificationCenter.default.post(name: .prismDataPathChanged, object: nil)
    }

    private func saveConfig() {
        let folder = URL(fileURLWithPath: dataPath)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("[saveConfig] cannot create directory: \(error.localizedDescription)")
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
            responseLength: responseLength.rawValue,
            useiCloud: useiCloud
        )
        do {
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("[saveConfig] write failed: \(error.localizedDescription)")
        }
    }
}

extension Notification.Name {
    /// Posted when the user changes the data storage path.
    static let prismDataPathChanged = Notification.Name("prismDataPathChanged")
}
