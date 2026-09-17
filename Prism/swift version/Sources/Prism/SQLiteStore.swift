import Foundation
import CSQLite

/// Same schema as the Rust client. Snapshot revisions reject stale writers.
final class SQLiteStore {
    private var db: OpaquePointer?
    private var revisions: [String: Int64] = [:]
    let root: URL
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    init(root: URL) throws {
        self.root = root
        guard !root.path.contains("/Library/Mobile Documents/") else {
            throw Failure(message: "Choose local storage; iCloud storage has been removed.")
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard sqlite3_open(root.appendingPathComponent("prism.sqlite3").path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open SQLite"
            if let db { sqlite3_close(db) }; db = nil
            throw Failure(message: message)
        }
        sqlite3_busy_timeout(db, 5000)
        guard try scalar("PRAGMA user_version") <= 1 else { throw Failure(message: "This database requires a newer Prism version.") }
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        try execute("""
        CREATE TABLE IF NOT EXISTS collections(name TEXT PRIMARY KEY, revision INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS records(collection TEXT NOT NULL, id TEXT NOT NULL, position INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(collection,id));
        CREATE TABLE IF NOT EXISTS history(sequence INTEGER PRIMARY KEY AUTOINCREMENT, collection TEXT NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, saved_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
        PRAGMA user_version=1;
        """)
    }
    deinit { if let db { sqlite3_close(db) } }
    private func failure() -> Failure { Failure(message: String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }
    private func statement(_ sql: String, _ arguments: [String] = []) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        for (i, argument) in arguments.enumerated() {
            let code = argument.withCString { sqlite3_bind_text(stmt, Int32(i+1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            if code != SQLITE_OK { sqlite3_finalize(stmt); throw failure() }
        }
        return stmt
    }
    private func scalar(_ sql: String, _ arguments: [String] = []) throws -> Int64 {
        let stmt = try statement(sql, arguments); defer { sqlite3_finalize(stmt) }
        let result=sqlite3_step(stmt)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw failure() }
        return result == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }
    private func run(_ sql: String, _ arguments: [String]) throws {
        let stmt = try statement(sql, arguments); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    func read(_ name: String, legacy: URL) throws -> Data {
        if try scalar("SELECT COUNT(*) FROM collections WHERE name=?", [name]) == 0 {
            var records: Any = [Any]()
            if FileManager.default.fileExists(atPath: legacy.path) {
                let data = try Data(contentsOf: legacy)
                let raw = try JSONSerialization.jsonObject(with: data)
                if let array = raw as? [Any] { records = array }
                else if let object = raw as? [String: Any], let array = ["conversations","entries","persons","memories","blindspots","events"].compactMap({ object[$0] as? [Any] }).first { records = array }
                else { throw Failure(message: "Unknown legacy archive format: \(legacy.lastPathComponent)") }
                let backup = legacy.appendingPathExtension("pre-sqlite.bak")
                if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: legacy, to: backup) }
            }
            let normalized = Self.normalize(records)
            revisions[name] = 0
            try write(name, data: JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys]))
        }
        try execute("BEGIN")
        do {
            let revision = try scalar("SELECT revision FROM collections WHERE name=?", [name])
            let stmt = try statement("SELECT payload FROM records WHERE collection=? ORDER BY position", [name])
            var records: [Any] = []
            do {
                defer { sqlite3_finalize(stmt) }
                while true {
                    let code=sqlite3_step(stmt)
                    if code == SQLITE_DONE { break }
                    guard code == SQLITE_ROW else { throw failure() }
                    let string=String(cString: sqlite3_column_text(stmt, 0))
                    records.append(try JSONSerialization.jsonObject(with: Data(string.utf8)))
                }
            }
            try execute("COMMIT")
            revisions[name] = revision
            return try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func write(_ name: String, data: Data) throws {
        guard let expected = revisions[name] else { throw Failure(message: "Read the collection before writing; existing data is protected.") }
        guard let records = Self.normalize(try JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { throw Failure(message: "Expected records with IDs") }
        try execute("BEGIN IMMEDIATE")
        do {
            let actual=try scalar("SELECT revision FROM collections WHERE name=?", [name])
            guard actual == expected else { throw Failure(message: "Storage conflict: another client changed these records. Unsaved changes remain in this window; preserve them before reopening.") }
            var existing: [String:(Int,String)] = [:]
            let select=try statement("SELECT id,position,payload FROM records WHERE collection=?",[name])
            do {
                defer { sqlite3_finalize(select) }
                while true {
                    let code=sqlite3_step(select)
                    if code == SQLITE_DONE { break }
                    guard code == SQLITE_ROW else { throw failure() }
                    existing[String(cString:sqlite3_column_text(select,0))]=(Int(sqlite3_column_int64(select,1)),String(cString:sqlite3_column_text(select,2)))
                }
            }
            var seen=Set<String>(), changed=actual == 0
            for (position, record) in records.enumerated() {
                guard let rawID=record["id"] as? String else { throw Failure(message:"Record without an ID; migration stopped") }
                let id=rawID.lowercased()
                guard seen.insert(id).inserted else { throw Failure(message:"Duplicate record ID; transaction rolled back") }
                let payload=String(decoding:try JSONSerialization.data(withJSONObject:record,options:[.sortedKeys,.withoutEscapingSlashes]),as:UTF8.self)
                if let previous=existing[id], previous.0 == position, previous.1 == payload { continue }
                changed=true
                try run("INSERT INTO records(collection,id,position,payload) VALUES(?,?,?,?) ON CONFLICT(collection,id) DO UPDATE SET position=excluded.position,payload=excluded.payload",[name,id,String(position),payload])
                if name != "conversations.json" { try run("INSERT INTO history(collection,revision,payload) VALUES(?,?,?)",[name,String(actual+1),payload]) }
            }
            for id in existing.keys where !seen.contains(id) {
                changed=true
                try run("DELETE FROM records WHERE collection=? AND id=?",[name,id])
                try run("DELETE FROM history WHERE collection=? AND lower(json_extract(payload,'$.id'))=?",[name,id])
            }
            let next=actual + (changed ? 1 : 0)
            try run("INSERT INTO collections(name,revision) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET revision=excluded.revision",[name,String(next)])
            try execute("COMMIT"); revisions[name]=next
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func clear() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try execute("DELETE FROM records; DELETE FROM history; UPDATE collections SET revision=revision+1;")
            try execute("COMMIT"); revisions.removeAll()
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func backup(to target: URL) throws {
        var dest: OpaquePointer?
        guard sqlite3_open(target.path, &dest) == SQLITE_OK else { if let dest { sqlite3_close(dest) }; throw failure() }
        defer { sqlite3_close(dest) }
        guard let backup=sqlite3_backup_init(dest,"main",db,"main") else { throw Failure(message: "Cannot start database backup") }
        let result=sqlite3_backup_step(backup,-1)
        let end=sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, end == SQLITE_OK else { throw Failure(message: "Database backup failed; original database is unchanged") }
    }
    static func normalize(_ value: Any, key: String = "") -> Any {
        if let a=value as? [Any] { return a.map { normalize($0,key:key) } }
        if var o=value as? [String:Any] {
            for (k,v) in o { o[k]=normalize(v,key:k) }
            if o["messages"] != nil, o["mode"] == nil || o["mode"] is NSNull { o["mode"]="balanced" }
            return o
        }
        if (key.hasSuffix("At") || key.hasSuffix("Date") || key == "timeSpanStart" || key == "timeSpanEnd"), let number=value as? NSNumber {
            let date=Date(timeIntervalSinceReferenceDate:number.doubleValue)
            let formatter=ISO8601DateFormatter(); formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            return formatter.string(from:date)
        }
        return value
    }
    static func encoder() -> JSONEncoder { let encoder=JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return encoder }
    static func decoder() -> JSONDecoder {
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container=try decoder.singleValueContainer()
            if let n=try? container.decode(Double.self) { return Date(timeIntervalSinceReferenceDate:n) }
            let text=try container.decode(String.self)
            let formatter=ISO8601DateFormatter(); formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            if let date=formatter.date(from:text) { return date }
            formatter.formatOptions=[.withInternetDateTime]
            if let date=formatter.date(from:text) { return date }
            throw Failure(message:"Invalid stored date: \(text)")
        }
        return decoder
    }
    static func localRoot(_ root: URL) throws -> URL {
        guard root.path.contains("/Library/Mobile Documents/") else { return root }
        let fm = FileManager.default
        let target=fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Prism/Imported-iCloud")
        let marker=target.appendingPathComponent("legacy-source.txt")
        if fm.fileExists(atPath:target.path) {
            guard (try? String(contentsOf:marker,encoding:.utf8)) == root.path else { throw Failure(message:"Local import destination already exists; original cloud data was not changed.") }
            return target
        }
        try fm.createDirectory(at:target,withIntermediateDirectories:true)
        // Copy legacy files individually. A direct copy of a SQLite file can
        // omit its WAL sidecar, so any existing database is transferred below
        // with SQLite's backup API instead.
        for source in try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            if ["prism.sqlite3", "prism.sqlite3-wal", "prism.sqlite3-shm"].contains(source.lastPathComponent) { continue }
            try fm.copyItem(at: source, to: target.appendingPathComponent(source.lastPathComponent))
        }
        let sourceDatabase = root.appendingPathComponent("prism.sqlite3")
        if fm.fileExists(atPath: sourceDatabase.path) {
            try copyDatabaseSnapshot(from: sourceDatabase, to: target.appendingPathComponent("prism.sqlite3"))
        }
        try root.path.write(to:marker,atomically:true,encoding:.utf8)
        return target
    }
    private static func copyDatabaseSnapshot(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let source { sqlite3_close(source) }
            throw Failure(message: "Cannot open the existing SQLite database for import.")
        }
        defer { sqlite3_close(source) }
        var destination: OpaquePointer?
        guard sqlite3_open(destinationURL.path, &destination) == SQLITE_OK else {
            if let destination { sqlite3_close(destination) }
            throw Failure(message: "Cannot create the imported SQLite database.")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw Failure(message: "Cannot start the SQLite import backup.")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else {
            throw Failure(message: "SQLite import backup failed; the original cloud database is unchanged.")
        }
    }
}
