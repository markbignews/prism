import Foundation
import Darwin

/// Injectable persistence used by tests. Production settings save locally and
/// never instantiate or call a Keychain client.
@MainActor protocol CredentialStore {
    func read(account: String) throws -> String?
    func write(_ value: String, account: String) throws
    func remove(account: String) throws
}

enum PrivateConfiguration {
    /// Create the temporary file as owner-only before writing any plaintext,
    /// then atomically replace the configuration without widening permissions.
    static func write(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".prism-config-" + UUID().uuidString)
        let manager = FileManager.default
        guard manager.createFile(atPath: temporary.path, contents: nil,
                                 attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary)
        let result = temporary.path.withCString { source in
            destination.path.withCString { target in Darwin.rename(source, target) }
        }
        if result != 0 { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
