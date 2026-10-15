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
