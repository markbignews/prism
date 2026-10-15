import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private let credentialStore: any CredentialStore
    private let migratesUserDefaults: Bool
    private var credentialID = UUID().uuidString
    private var persistedCredential: String?
    private var isLoadingConfig = true
    private var credentialReadFailed = false
    private var configurationLoadFailed = false
    @Published var apiKey = "" {
        didSet {
            if oldValue != apiKey {
                invalidateModelCatalog()
                if !isLoadingConfig { credentialReadFailed = false }
            }
            saveConfig()
        }
    }
    @Published var baseURL = "https://api.deepseek.com" {
        didSet { if oldValue != baseURL { invalidateModelCatalog() }; saveConfig() }
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

    @Published private(set) var availableModels: [ProviderModel] = []
    @Published private(set) var isFetchingModels = false
    @Published private(set) var modelCatalogError: String?
    @Published private(set) var credentialsVerified = false
    // An opaque revision lets SwiftUI debounce changes without exposing keys as task IDs.
    @Published private(set) var modelCatalogRevision = UUID()
    private var catalogRequestID = UUID()

    var usesFlashParameters: Bool {
        model.localizedCaseInsensitiveContains("flash") || availableModels.first(where: { $0.id == model })?.isFlash == true
    }

    var modelChoices: [ProviderModel] {
        var choices = availableModels
        if choices.isEmpty, URL(string: baseURL)?.host?.lowercased() == "api.deepseek.com" {
            choices = [ProviderModel(id: DeepSeekModels.flash, name: "DeepSeek V4.1 Flash"),
                       ProviderModel(id: DeepSeekModels.pro, name: "DeepSeek V4 Pro")]
        }
        for id in [model, flashModel] where !id.isEmpty && !choices.contains(where: { $0.id == id }) {
            choices.append(ProviderModel(id: id))
        }
        return ProviderModel.sorted(choices)
    }

    private func invalidateModelCatalog() {
        catalogRequestID = UUID()
        credentialsVerified = false
        availableModels = []
        modelCatalogError = nil
        isFetchingModels = false
        modelCatalogRevision = UUID()
    }

    /// Re-check credentials and request identity after suspension so a stale
    /// provider response cannot change a newly entered provider's selections.
    func refreshModels(client: ModelCatalogClient = ModelCatalogClient()) async {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let requestID = UUID()
        catalogRequestID = requestID
        let requestKey = apiKey
        let requestBase = baseURL
        let requestModel = model
        let requestAuxiliary = flashModel
        isFetchingModels = true
        modelCatalogError = nil
        defer { if catalogRequestID == requestID { isFetchingModels = false } }
        do {
            let models = try await client.fetch(apiKey: requestKey, baseURL: requestBase)
            guard !Task.isCancelled, catalogRequestID == requestID,
                  apiKey == requestKey, baseURL == requestBase else { return }
            availableModels = models
            credentialsVerified = true
            // Keep a valid deliberate selection. Missing/default models choose Flash first.
            if model == requestModel { model = ProviderModel.selection(current: model, from: models) }
            if flashModel == requestAuxiliary { flashModel = ProviderModel.selection(current: flashModel, from: models) }
        } catch {
            guard !Task.isCancelled, catalogRequestID == requestID else { return }
            credentialsVerified = false
            modelCatalogError = ProviderFailure.message(error, language: language)
        }
    }

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

    init(storagePath: String? = nil, credentialStore: any CredentialStore = KeychainCredentials()) {
        self.credentialStore = credentialStore
        migratesUserDefaults = storagePath == nil
        let defaultDataPath = Self.localDefaultPath
        dataPath = storagePath ?? UserDefaults.standard.string(forKey: "storage.dataPath") ?? defaultDataPath
        do {
            dataPath = try SQLiteStore.localRoot(URL(fileURLWithPath: dataPath)).path
            if storagePath == nil { UserDefaults.standard.set(dataPath, forKey: "storage.dataPath") }
        } catch { storageError = error.localizedDescription }
        PrismLog.configure(dataPath: dataPath)
        UsageStatsStore.shared.configure(dataPath: dataPath)

        // Migrate legacy UserDefaults keys → config.json
        let legacyKey = storagePath == nil ? (UserDefaults.standard.string(forKey: "deepseek.apiKey") ?? "") : ""

        // Load from config.json in data directory
        loadConfig(legacyAPIKey: legacyKey)
        isLoadingConfig = false
        saveConfig()
        PrismLog.setEnabled(enableLogging)

        // If migrated, clear legacy UserDefaults
        if !legacyKey.isEmpty, storageError == nil {
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
        let parameters = usesFlashParameters ? flashParameters : self.parameters
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
        // Decode old plaintext only; new saves leave this nil (omitted in JSON).
        var apiKey: String? = nil
        var credentialID: String? = nil
        var baseURL = "https://api.deepseek.com"
        var model = "deepseek-flash"
        var flashModel = "deepseek-flash"
        var language = "zh-Hans"
        var parameters = ModelParameters()
        var flashParameters = ModelParameters()
        var summaryDialogCount = 5
        var enableLogging = true
        var showReasoningPanel = true
        var onboardingCompleted = false
        var conversationMode = "balanced"
        var responseLength = "standard"
    }

    private func loadConfig(legacyAPIKey: String = "") {
        guard let data = try? Data(contentsOf: configURL),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaults = try? JSONEncoder().encode(ConfigFile()),
              var merged = try? JSONSerialization.jsonObject(with: defaults) as? [String: Any] else {
            if FileManager.default.fileExists(atPath: configURL.path) {
                configurationLoadFailed = true
                credentialReadFailed = true
                storageError = "Cannot read config.json; the original settings were preserved."
                return
            }
            // No config file yet — adopt an earlier Prism settings.json if present.
            if importLegacySettingsIfNeeded() { return }
            // Otherwise use defaults, migrating legacy API key if present
            if !legacyAPIKey.isEmpty { apiKey = legacyAPIKey }
            return
        }
        merged.merge(raw) { _, new in new }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: mergedData) else {
            configurationLoadFailed = true
            storageError = "Cannot read config.json; the original settings were preserved."
            credentialReadFailed = true
            return
        }
        credentialID = config.credentialID ?? credentialID
        do {
            let stored = try credentialStore.read(account: credentialID)
            persistedCredential = stored
            apiKey = stored ?? config.apiKey ?? legacyAPIKey
        } catch {
            apiKey = config.apiKey ?? legacyAPIKey
            credentialReadFailed = true
            storageError = error.localizedDescription
        }
        baseURL = config.baseURL
        model = config.model
        flashModel = config.flashModel
        language = AppLanguage(rawValue: config.language) ?? .simplifiedChinese
        parameters = config.parameters
        flashParameters = config.flashParameters
        let canonicalModel = DeepSeekModels.supportedConversationModel(DeepSeekModels.canonical(model, baseURL: baseURL))
        let canonicalAuxiliary = DeepSeekModels.supportedConversationModel(DeepSeekModels.canonical(flashModel, baseURL: baseURL))
        let migratedModelDefaults = canonicalModel != model || canonicalAuxiliary != flashModel
        model = canonicalModel
        flashModel = canonicalAuxiliary
        summaryDialogCount = config.summaryDialogCount
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
    @discardableResult func resetAll() -> Bool {
        let folder = URL(fileURLWithPath: dataPath)

        guard canChangeStorage() else { storageError = "Wait for the active operation before resetting."; return false }
        do {
            try SQLiteStore(root: folder).clear()
            try credentialStore.remove(account: credentialID)
            persistedCredential = ""
        }
        catch { storageError = error.localizedDescription; return false }
        credentialReadFailed = false; configurationLoadFailed = false
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
        enableLogging = true
        showReasoningPanel = true
        onboardingCompleted = false
        responseLength = .standard
        return storageError == nil
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
        guard !isLoadingConfig, !credentialReadFailed, !configurationLoadFailed else { return }
        let folder = URL(fileURLWithPath: dataPath)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            storageError = error.localizedDescription
            return
        }

        let config = ConfigFile(
            credentialID: credentialID,
            baseURL: baseURL,
            model: model,
            flashModel: flashModel,
            language: language.rawValue,
            parameters: parameters,
            flashParameters: flashParameters,
            summaryDialogCount: summaryDialogCount,
            enableLogging: enableLogging,
            showReasoningPanel: showReasoningPanel,
            onboardingCompleted: onboardingCompleted,
            conversationMode: conversationMode.rawValue,
            responseLength: responseLength.rawValue
        )
        do {
            if persistedCredential != apiKey {
                if apiKey.isEmpty { try credentialStore.remove(account: credentialID) }
                else { try credentialStore.write(apiKey, account: credentialID) }
                guard (try credentialStore.read(account: credentialID) ?? "") == apiKey else {
                    throw SQLiteStore.Failure(message: "Keychain verification failed; the old config was preserved.")
                }
                persistedCredential = apiKey
            }
            let data = try JSONEncoder().encode(config)
            try data.write(to: configURL, options: .atomic)
            if migratesUserDefaults, UserDefaults.standard.string(forKey: "deepseek.apiKey") == apiKey {
                UserDefaults.standard.removeObject(forKey: "deepseek.apiKey")
            }
            // An older settings.json may still contain the same plaintext.
            // Scrub it only after the Keychain and replacement config succeeded.
            let legacy = folder.appendingPathComponent("settings.json")
            if let bytes = try? Data(contentsOf: legacy),
               var object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
                object.removeValue(forKey: "apiKey"); object.removeValue(forKey: "api_key")
                try JSONSerialization.data(withJSONObject: object, options: .sortedKeys).write(to: legacy, options: .atomic)
            }
            storageError = nil
        } catch {
            storageError = error.localizedDescription
        }
    }
    func retryCredentialStorage() {
        if configurationLoadFailed {
            isLoadingConfig = true
            configurationLoadFailed = false; credentialReadFailed = false
            loadConfig()
            isLoadingConfig = false
            guard !configurationLoadFailed, !credentialReadFailed else { return }
        }
        if credentialReadFailed {
            do {
                let stored = try credentialStore.read(account: credentialID)
                credentialReadFailed = false
                if let stored { apiKey = stored; persistedCredential = stored }
            } catch { storageError = error.localizedDescription; return }
        }
        saveConfig()
    }
}

extension Notification.Name {
    /// Posted when the user changes the data storage path.
    static let prismDataPathChanged = Notification.Name("prismDataPathChanged")
}
