import Foundation
import Testing
@testable import Prism

@MainActor final class TestCredentials: CredentialStore {
    static let shared = TestCredentials()
    var values: [String: String] = [:]
    var failWrites = false
    var failReads = false
    func read(account: String) throws -> String? {
        if failReads { throw SQLiteStore.Failure(message: "simulated Keychain access denied") }
        return values[account]
    }
    func write(_ value: String, account: String) throws {
        if failWrites { throw SQLiteStore.Failure(message: "simulated locked Keychain") }
        values[account] = value
    }
    func remove(account: String) throws { values[account] = nil }
}

@Suite @MainActor struct CredentialMigrationTests {
    @Test func corruptConfigurationRetryCannotOverwriteOriginalAndLockedReadCannotDeleteKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("config.json")
        let corrupt = Data("{truncated".utf8)
        try corrupt.write(to: file)
        let credentials = TestCredentials()
        let broken = AppSettings(storagePath: root.path, credentialStore: credentials)
        broken.retryCredentialStorage()
        #expect(try Data(contentsOf: file) == corrupt)
        broken.apiKey = "new unsaved credential"
        #expect(try Data(contentsOf: file) == corrupt)
        try Data(#"{"credentialID":"existing"}"#.utf8).write(to: file)
        credentials.values["existing"] = "protected-key"
        credentials.failReads = true
        let locked = AppSettings(storagePath: root.path, credentialStore: credentials)
        #expect(locked.storageError != nil)
        locked.model = "new-model"
        #expect(credentials.values["existing"] == "protected-key")
        credentials.failReads = false
        locked.retryCredentialStorage()
        #expect(locked.apiKey == "protected-key" && locked.storageError == nil)
    }
    @Test func migrationRemovesPlaintextOnlyAfterCredentialIsStoredAndSurvivesReload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config.json")
        try Data(#"{"apiKey":"test-secret","model":"custom","contextWindow":60}"#.utf8).write(to: config)
        let credentials = TestCredentials()
        credentials.failWrites = true
        let settings = AppSettings(storagePath: root.path, credentialStore: credentials)
        #expect(settings.apiKey == "test-secret")
        #expect(settings.storageError != nil)
        #expect(try String(contentsOf: config, encoding: .utf8).contains("test-secret"))
        credentials.failWrites = false
        settings.retryCredentialStorage()
        let text = try String(contentsOf: config, encoding: .utf8)
        #expect(!text.contains("test-secret") && !text.contains("apiKey") && !text.contains("contextWindow"))
        let restored = AppSettings(storagePath: root.path, credentialStore: credentials)
        #expect(restored.apiKey == "test-secret" && restored.model == "custom")
        restored.apiKey = ""
        #expect(AppSettings(storagePath: root.path, credentialStore: credentials).apiKey.isEmpty)
    }
}

@Suite @MainActor struct PlaintextCredentialTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func defaultStoragePersistsLocallyWithOwnerOnlyPermissionsAndClears() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = AppSettings(storagePath: root.path)
        settings.apiKey = "test-local-key"
        let file = root.appendingPathComponent("config.json")
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect(object["apiKey"] as? String == "test-local-key")
        #expect(object["credentialID"] == nil)
        #expect(AppSettings(storagePath: root.path).apiKey == "test-local-key")
        settings.model = "custom-model"
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        settings.apiKey = ""
        #expect(AppSettings(storagePath: root.path).apiKey.isEmpty)
        #expect(!String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("test-local-key"))
    }

    @Test func oldKeychainOnlyConfigurationRequestsReentryWithoutReadingKeychain() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        try Data(#"{"credentialID":"old-keychain-item","model":"custom-model"}"#.utf8).write(to: file)
        let settings = AppSettings(storagePath: root.path)
        #expect(settings.apiKey.isEmpty && settings.needsCredentialReentry)
        #expect(settings.storageError == nil)
        #expect(AppSettings(storagePath: root.path).needsCredentialReentry)
        settings.apiKey = "replacement-local-key"
        let restored = AppSettings(storagePath: root.path)
        #expect(restored.apiKey == "replacement-local-key")
        #expect(!restored.needsCredentialReentry && restored.model == "custom-model")
    }

    @Test func existingPlaintextMigratesWithoutSecretDuplicationAndSurvivesFolderChange() throws {
        let root = try folder(), destination = try folder()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: destination) }
        try Data(#"{"apiKey":"legacy-local-key","baseURL":"https://api.deepseek.com"}"#.utf8)
            .write(to: root.appendingPathComponent("settings.json"))
        let settings = AppSettings(storagePath: root.path)
        #expect(settings.apiKey == "legacy-local-key")
        #expect(!String(decoding: try Data(contentsOf: root.appendingPathComponent("settings.json")), as: UTF8.self).contains("legacy-local-key"))
        settings.dataPath = destination.path
        #expect(settings.storageError == nil)
        #expect(AppSettings(storagePath: destination.path).apiKey == "legacy-local-key")
    }

    @Test func malformedConfigurationIsNotOverwrittenByPlaintextSave() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("config.json")
        let original = Data("{broken".utf8)
        try original.write(to: file)
        let settings = AppSettings(storagePath: root.path)
        settings.apiKey = "must-not-overwrite"
        settings.retryCredentialStorage()
        #expect(try Data(contentsOf: file) == original)
        #expect(settings.storageError != nil)
    }
}
