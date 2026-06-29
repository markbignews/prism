import Foundation

// MARK: - Terminal rendering engine (Claude Code style)

/// ANSI escape codes for rich terminal output.
/// Works on macOS, Linux, and modern Windows Terminal (WT 1.22+).
enum Term {

    // MARK: - Styles

    static let reset   = "\u{001B}[0m"
    static let bold    = "\u{001B}[1m"
    static let dim     = "\u{001B}[2m"
    static let italic  = "\u{001B}[3m"
    static let uline   = "\u{001B}[4m"

    // MARK: - 16 Colors

    static let black   = "\u{001B}[30m"
    static let red     = "\u{001B}[31m"
    static let green   = "\u{001B}[32m"
    static let yellow  = "\u{001B}[33m"
    static let blue    = "\u{001B}[34m"
    static let magenta = "\u{001B}[35m"
    static let cyan    = "\u{001B}[36m"
    static let white   = "\u{001B}[37m"
    static let gray    = "\u{001B}[90m"

    // MARK: - Backgrounds

    static let bgRed   = "\u{001B}[41m"
    static let bgBlue  = "\u{001B}[44m"

    // MARK: - Cursor

    static func cursorUp(_ n: Int = 1)  -> String { "\u{001B}[\(n)A" }
    static func cursorDown(_ n: Int = 1) -> String { "\u{001B}[\(n)B" }
    static let clearLine = "\u{001B}[2K"
    static let clearToEnd = "\u{001B}[0J"
    static var isTTY: Bool { isatty(STDOUT_FILENO) != 0 }

    // MARK: - Composers

    static func err(_ text: String) -> String { red + text + reset }
    static func ok(_ text: String) -> String  { green + text + reset }
    static func warn(_ text: String) -> String { yellow + text + reset }
    static func info(_ text: String) -> String { cyan + text + reset }
    static func muted(_ text: String) -> String { dim + text + reset }
    static func strong(_ text: String) -> String { bold + text + reset }

    /// Write and flush. Skips ANSI codes when stdout isn't a TTY (piped).
    static func write(_ text: String, style: String = "") {
        if isTTY {
            fputs(style + text + reset, stdout)
        } else {
            fputs(text, stdout)
        }
        fflush(stdout)
    }

    /// Write a line with optional style.
    static func line(_ text: String, style: String = "") {
        write(text + "\n", style: style)
    }

    // MARK: - Special UI

    /// A horizontal divider line.
    static func divider(_ char: Character = "─", width: Int = 60) {
        line(String(repeating: char, count: width), style: dim)
    }

    /// "  ▶ message" style
    static func bullet(_ text: String) {
        line("  ▶ " + text)
    }

    /// Live streaming token output — no newline, just push characters.
    static func stream(_ token: String) {
        if isTTY {
            fputs(token, stdout)
        } else {
            fputs(token, stdout)
        }
        fflush(stdout)
    }

    /// Clear the current line (for progress / spinner replacement).
    static func overwrite(_ text: String) {
        if isTTY {
            fputs("\r\033[2K" + text, stdout)
        } else {
            fputs(text + "\n", stdout)
        }
        fflush(stdout)
    }

    // MARK: - Progress

    /// Simple spinner that runs until cancelled.
    static func spinner(_ message: String) -> Task<Void, Never> {
        Task {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            var i = 0
            while !Task.isCancelled {
                overwrite(frames[i] + " " + muted(message))
                i = (i + 1) % frames.count
                try? await Task.sleep(for: .milliseconds(80))
            }
            overwrite("")
        }
    }
}

// MARK: - Interactive Prompts

/// Synchronous line input with optional prompt style.
func readInput(prompt: String = "> ") -> String? {
    fputs(prompt, stdout)
    fflush(stdout)
    return readLine()
}

/// Yes/No confirmation.
func confirm(_ question: String, default: Bool = false) -> Bool {
    let hint = `default` ? "[Y/n]" : "[y/N]"
    fputs(Term.muted("  \(question) \(hint) "), stdout)
    fflush(stdout)
    guard let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return `default` }
    if answer.isEmpty { return `default` }
    return answer == "y" || answer == "yes"
}

/// Wait for Enter key (used for "press enter to continue").
func waitForEnter(_ message: String = "按 Enter 继续...") {
    fputs(Term.muted("  \(message)"), stdout)
    fflush(stdout)
    _ = readLine()
}

/// Mask an API key for display.
func maskKey(_ text: String) -> String {
    guard text.count > 8 else { return "***" }
    return String(text.prefix(5)) + "..." + String(text.suffix(3))
}
