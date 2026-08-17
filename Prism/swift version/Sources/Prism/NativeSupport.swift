import SwiftUI
import AppKit

// MARK: - Platform Primitives (only AppKit code in the project)

/// macOS has no pure-SwiftUI replacement for the clipboard, app termination
/// or .icns loading. These three primitives are isolated here so every other
/// file stays pure SwiftUI.
@MainActor
enum NativeSupport {

    /// Copy a string to the general pasteboard (NSPasteboard is the only
    /// clipboard API on macOS).
    static func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Terminate the app (used by the "Reset & Quit" flow).
    static func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    /// Export a snapshot of the current local log through the native save
    /// panel. Reading then atomically writing also handles saving over an
    /// existing destination selected by the user.
    @discardableResult
    static func exportLog(from dataPath: String) -> Bool {
        let source = URL(fileURLWithPath: dataPath).appendingPathComponent("prism.log")
        let panel = NSSavePanel()
        panel.title = "Export Prism Log"
        panel.nameFieldStringValue = "prism.log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - App Icon Helper

/// Loads the bundled AppIcon.icns, falling back to the brain SF Symbol
/// when running outside the .app bundle (e.g. during development).
/// `.icns` decoding requires NSImage — there is no SwiftUI-only loader.
struct AppIconImage: View {
    var body: some View {
        if let nsImage = loadAppIcon() {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "brain.head.profile")
        }
    }

    private func loadAppIcon() -> NSImage? {
        // 1. SwiftPM does not always expose the surrounding .app as
        // `Bundle.main`. Resolve Contents/Resources from the executable path.
        let executableCandidates = [
            Bundle.main.executableURL,
            URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        ].compactMap { $0 }
        for executableURL in executableCandidates {
            let packagedIconURL = executableURL
                .deletingLastPathComponent() // MacOS
                .deletingLastPathComponent() // Contents
                .appendingPathComponent("Resources/Prism.icns")
            if let image = NSImage(contentsOf: packagedIconURL) {
                return image
            }
        }
        // 2. The running application may already resolve CFBundleIconFile.
        // is the most reliable path for a SwiftPM executable wrapped in .app.
        if let image = NSApplication.shared.applicationIconImage,
           image.size.width > 0,
           image.size.height > 0 {
            return image
        }
        // 3. Standard bundle resource lookup (works in Xcode projects)
        if let url = Bundle.main.url(forResource: "Prism", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // 4. Explicitly resolve Contents/Resources for conventional bundles.
        let resourcesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/Prism.icns")
        if let img = NSImage(contentsOf: resourcesURL) {
            return img
        }
        // 5. Adjacent to executable (development fallback)
        let adjacentURL = Bundle.main.bundleURL.appendingPathComponent("Prism.icns")
        if let img = NSImage(contentsOf: adjacentURL) {
            return img
        }
        return nil
    }
}
