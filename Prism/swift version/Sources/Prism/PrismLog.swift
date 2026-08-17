import Foundation

/// Lightweight file logger (Tauri parity: `enable_logging` writes
/// prism.log next to Prism's data directory; console mirror included).
///
/// The log file lives at `<dataPath>/prism.log` — the same location the
/// Tauri build uses, so both implementations share one log when they
/// share a data folder.
///
/// All call sites are on the main actor (ChatAgent is @MainActor), so the
/// whole type is main-actor isolated — no locks needed, Swift 6 safe.
@MainActor
enum PrismLog {
    private static var logURL: URL?
    private static var enabled = true
    private static let timestampFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Point the logger at a data directory (call whenever the storage
    /// path changes). Creating the file is deferred until the first log
    /// line so an unwritable location never blocks startup.
    static func configure(dataPath: String) {
        logURL = URL(fileURLWithPath: dataPath).appendingPathComponent("prism.log")
    }

    /// Toggle file logging on/off (console output is always kept).
    static func setEnabled(_ flag: Bool) {
        enabled = flag
    }

    static func log(_ message: String) {
        print(message)
        guard enabled, let logURL else { return }
        let line = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let fh = try? FileHandle(forWritingTo: logURL) {
            defer { try? fh.close() }
            do {
                try fh.seekToEnd()
                try fh.write(contentsOf: data)
                return
            } catch {
                // fall through to create/overwrite below
            }
        }
        try? data.write(to: logURL)
    }
}
