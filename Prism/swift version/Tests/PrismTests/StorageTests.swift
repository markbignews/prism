import Foundation
import CSQLite
import Testing
@testable import Prism

@Suite struct SQLiteStorageTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func payload(_ value: Int) -> Data { Data("[{\"id\":\"one\",\"value\":\(value)}]".utf8) }

    @Test func staleWriterCannotOverwriteAndBatchRollsBackEveryCollection() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try SQLiteStore(root: root), other = try SQLiteStore(root: root)
        for name in ["a", "b"] {
            _ = try first.read(name, legacy: root.appendingPathComponent(name))
            _ = try other.read(name, legacy: root.appendingPathComponent(name))
        }
        try other.write("b", data: payload(2))
        #expect(throws: SQLiteStore.Failure.self) { try first.writeBatch(["a": payload(1), "b": payload(1)]) }
        let reader = try SQLiteStore(root: root)
        #expect(try reader.read("a", legacy: root.appendingPathComponent("a")) == Data("[]".utf8))
        #expect(try reader.read("b", legacy: root.appendingPathComponent("b")) == payload(2))
        // Rollback also restores the writer's revision cache.
        try first.write("a", data: payload(3))
    }

    @Test func legacyImportCreatesBackupAndOnlineBackupIncludesWAL() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("memory.json")
        try payload(1).write(to: legacy)
        let store = try SQLiteStore(root: root)
        #expect(try store.read("memory.json", legacy: legacy) == payload(1))
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathExtension("pre-sqlite.bak").path))
        try store.write("memory.json", data: payload(2))
        let destination = root.appendingPathComponent("backup", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try store.backup(to: destination.appendingPathComponent("prism.sqlite3"))
        let restored = try SQLiteStore(root: destination)
        #expect(try restored.read("memory.json", legacy: legacy) == payload(2))
    }

    @Test func historyIsBoundedAndTemporaryLockCanBeRetried() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = try SQLiteStore(root: root)
        _ = try store.read("memory.json", legacy: root.appendingPathComponent("absent"))
        for value in 0..<30 { try store.write("memory.json", data: payload(value)) }
        var db: OpaquePointer?
        #expect(sqlite3_open(root.appendingPathComponent("prism.sqlite3").path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT count(*) FROM history", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) <= 5)
        sqlite3_finalize(statement); statement = nil
        #expect(sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
        #expect(throws: SQLiteStore.Failure.self) { try store.write("memory.json", data: payload(31)) }
        #expect(sqlite3_exec(db, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
        try store.write("memory.json", data: payload(32))
        #expect(try store.read("memory.json", legacy: root) == payload(32))
    }
}
