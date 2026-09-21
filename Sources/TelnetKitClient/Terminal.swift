import Darwin
import Foundation

/// Minimal terminal control for the interactive client.
enum Terminal {
    /// Puts stdin into raw mode so every keystroke reaches the peer immediately, and keeps
    /// output post-processing so `\n` still starts a new line. Returns nil when stdin is
    /// not a terminal, which is how a piped invocation is detected.
    static func enterRawMode() -> termios? {
        guard isatty(STDIN_FILENO) == 1 else { return nil }
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }
        var raw = original
        cfmakeraw(&raw)
        raw.c_oflag |= tcflag_t(OPOST)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
        return original
    }

    static func restore(_ settings: termios) {
        var settings = settings
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &settings)
    }

    /// Stops the process the way ^Z does, then re-enters raw mode when it resumes.
    static func suspend() {
        raise(SIGTSTP)
    }

    static var isInteractive: Bool {
        isatty(STDIN_FILENO) == 1
    }
}
