import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var apiKey = "" {
        didSet { saveConfig() }
    }
    @Published var baseURL = "https://api.deepseek.com" {
        didSet { saveConfig() }
    }
    @Published var model = "deepseek-v4-pro" {
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

    /// Only dataPath stays in UserDefaults — it's the bootstrap key.
    @Published var dataPath: String {
        didSet {
            UserDefaults.standard.set(dataPath, forKey: "storage.dataPath")
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

        // Migrate legacy UserDefaults keys → config.json
        let legacyKey = UserDefaults.standard.string(forKey: "deepseek.apiKey") ?? ""

        // Load from config.json in data directory
        loadConfig(legacyAPIKey: legacyKey)

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

    // MARK: - Config Persistence

    private var configURL: URL {
        URL(fileURLWithPath: dataPath).appendingPathComponent("config.json")
    }

    private struct ConfigFile: Codable {
        var apiKey = ""
        var baseURL = "https://api.deepseek.com"
        var model = "deepseek-v4-pro"
        var flashModel = "deepseek-v4-flash"
        var language = "zh-Hans"
        var parameters = ModelParameters()
        var flashParameters = ModelParameters()
        var summaryDialogCount = 5
        var showReasoningPanel = true
        var onboardingCompleted = false
        var conversationMode = "balanced"
        var responseLength = "standard"
        var useiCloud = false
    }

    private func loadConfig(legacyAPIKey: String = "") {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(ConfigFile.self, from: data) else {
            // No config file yet — use defaults, migrate legacy API key if present
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
        summaryDialogCount = config.summaryDialogCount
        showReasoningPanel = config.showReasoningPanel
        onboardingCompleted = config.onboardingCompleted
        conversationMode = ConversationMode(rawValue: config.conversationMode) ?? .balanced
        responseLength = ResponseLength(rawValue: config.responseLength) ?? .standard
        useiCloud = config.useiCloud
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

        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: "storage.dataPath")

        // Reset published properties to defaults (didSet will save new config)
        apiKey = ""
        baseURL = "https://api.deepseek.com"
        model = "deepseek-v4-pro"
        flashModel = "deepseek-v4-flash"
        language = .simplifiedChinese
        parameters = ModelParameters()
        flashParameters = ModelParameters(
            thinkingEnabled: true, reasoningEffort: "high"
        )
        summaryDialogCount = 5
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
