import Foundation

/// The echo server's log.
///
/// The log is the program's output rather than a diagnostic side channel: PRD §9.3 asks for a
/// client's window-size report to be visible in it. Peer-supplied text reaches a line only
/// after `TelnetWire.printable(_:)`, and echoed session data is never logged.
struct EchoLog: Sendable {
    func line(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
    }

    func failure(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
