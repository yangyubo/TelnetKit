import Darwin
import Foundation
import TelnetKit

/// The interactive Telnet session behind `telnetkit-client`.
///
/// One actor serializes the state that the event pump, the command mode, and the input
/// pump all touch. Server data goes to stdout untouched; diagnostics go to stderr.
actor TelnetClient {
    private let arguments: ClientArguments
    private var connection: TelnetConnection?
    private var eventsTask: Task<Void, Never>?
    private var terminalSettings: termios?
    private var escapeCharacter: UInt8?
    private var debug: Bool
    /// Typed input is echoed locally until the peer says it will echo; a terminal in raw
    /// mode has no echo of its own, so a silent peer would otherwise swallow every key.
    private var localEcho = true
    private var inCommandMode = false
    private var commandBuffer: [UInt8] = []

    init(arguments: ClientArguments) {
        self.arguments = arguments
        self.escapeCharacter = arguments.noEscape ? nil : arguments.escapeCharacter
        self.debug = arguments.debug
    }

    // MARK: Lifecycle

    func run() async {
        terminalSettings = Terminal.enterRawMode()
        if let host = arguments.host {
            await open(host: host, port: arguments.port)
        } else {
            inCommandMode = true
            prompt()
        }
        await readInput()
        await close()
        if let settings = terminalSettings {
            Terminal.restore(settings)
        }
    }

    // MARK: Connection

    private func open(host: String, port: Int) async {
        await close()
        writeError("Trying \(host)...")
        do {
            let connection = try await TelnetConnection.connect(
                host: host,
                port: port,
                options: arguments.options,
                configuration: arguments.configuration
            )
            self.connection = connection
            inCommandMode = false
            writeError("Connected to \(host).")
            if let remote = await connection.remoteAddress {
                writeError("Remote address \(remote).")
            }
            writeError("Escape character is '\(escapeName)'.")
            eventsTask = Task { [weak self] in
                guard let self else { return }
                await self.pumpEvents(connection)
            }
        } catch {
            // `connect` is typed `throws(TelnetError)`, so the error is already public.
            writeError("\(host): \(describe(error))")
            inCommandMode = true
            prompt()
        }
    }

    private func close() async {
        eventsTask?.cancel()
        eventsTask = nil
        if let connection {
            await connection.close()
        }
        connection = nil
    }

    private func pumpEvents(_ connection: TelnetConnection) async {
        for await event in connection.events {
            await handle(event, from: connection)
        }
        if self.connection === connection {
            writeError("Connection closed by foreign host.")
            self.connection = nil
            inCommandMode = true
            prompt()
        }
    }

    private func handle(_ event: TelnetEvent, from connection: TelnetConnection) async {
        switch event {
        case .data(let buffer):
            writeOutput(Array(buffer.readableBytesView))

        case .terminalTypeRequested:
            let type = ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color"
            do { try await connection.replyTerminalType(type) } catch { report(error) }

        case .environmentRequested(let scope):
            let user = arguments.user ?? NSUserName()
            let variables = [
                EnvironmentVariable(name: "USER", value: user, scope: scope),
                EnvironmentVariable(name: "TERM", value: ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color", scope: scope),
            ]
            do { try await connection.sendEnvironment(variables, scope: scope) } catch { report(error) }

        case .localEchoChanged(let enabled):
            // `enabled` is this end's echo duty: a peer that will echo turns it off.
            localEcho = enabled

        case .negotiation(let action, let option, _):
            if debug {
                writeError("negotiation \(action) \(option.displayName)")
            }

        case .command(let command):
            if debug {
                writeError("command \(command)")
            }

        case .subnegotiation(let option, let payload):
            if debug {
                writeError("subnegotiation \(option.displayName) \(payload.count) bytes")
            }

        case .terminalType(let name):
            if debug { writeError("terminal type \(name)") }

        case .environment(let scope, let values):
            if debug { writeError("environment \(scope) \(values.count) entries") }

        case .mssp(let values):
            if debug { writeError("mssp \(values.count) entries") }

        case .zmp(let arguments):
            if debug { writeError("zmp \(arguments.count) arguments") }

        case .compressionEnabled(let enabled):
            writeError("compression \(enabled ? "enabled" : "disabled")")

        case .pathChanged(let viable, let expensive, let constrained):
            if debug { writeError("path viable=\(viable) expensive=\(expensive) constrained=\(constrained)") }

        case .betterPathAvailable, .betterPathUnavailable, .viabilityChanged, .waitingForConnectivity:
            if debug { writeError("network event \(event)") }

        case .warning(let warning):
            writeError("warning: \(warning)")

        case .protocolError(let error):
            writeError("protocol error: \(error)")
        }
    }

    // MARK: Input

    private func readInput() async {
        do {
            for try await byte in FileHandle.standardInput.bytes {
                await handle(byte)
            }
        } catch {
            writeError("input error: \(error)")
        }
    }

    private func handle(_ byte: UInt8) async {
        if inCommandMode {
            await handleCommandByte(byte)
            return
        }
        if let escapeCharacter, byte == escapeCharacter {
            inCommandMode = true
            commandBuffer.removeAll(keepingCapacity: true)
            writeError("")
            prompt()
            return
        }
        switch byte {
        case 0x03:
            await send(command: .interruptProcess)
        case 0x04:
            await send(command: .endOfFile)
        case 0x0D:
            // A bare LF: the terminal's output post-processing adds the carriage return,
            // and an explicit CR here would double it.
            if localEcho { writeOutput([0x0A]) }
            // CR NUL, not CR LF: the peer's line discipline turns the CR into a newline,
            // and a following LF would end a second, empty line. `telnet(1)` sends CR NUL.
            await send(bytes: [0x0D, 0x00])
        default:
            if localEcho, byte >= 0x20 || byte == 0x7F {
                writeOutput([byte])
            }
            await send(bytes: [byte])
        }
    }

    private func handleCommandByte(_ byte: UInt8) async {
        switch byte {
        case 0x0D, 0x0A:
            // Command mode echoes typed input itself, so it must also end the line the
            // user submitted; otherwise the next diagnostic lands on the same line.
            writeOutput([0x0A])
            let line = String(decoding: commandBuffer, as: UTF8.self)
            commandBuffer.removeAll(keepingCapacity: true)
            await execute(line)
        case 0x7F, 0x08:
            if !commandBuffer.isEmpty {
                commandBuffer.removeLast()
                writeOutput([0x08, 0x20, 0x08])
            }
        case 0x15:
            while !commandBuffer.isEmpty {
                commandBuffer.removeLast()
                writeOutput([0x08, 0x20, 0x08])
            }
        default:
            if byte >= 0x20 {
                commandBuffer.append(byte)
                writeOutput([byte])
            }
        }
    }

    private func execute(_ line: String) async {
        let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = parts.first?.lowercased() else {
            finishCommand()
            return
        }
        let rest = Array(parts.dropFirst())

        switch command {
        case "open":
            guard let host = rest.first else {
                writeError("usage: open host-name [port]")
                break
            }
            let port = rest.count > 1 ? Int(rest[1]) ?? arguments.port : arguments.port
            await open(host: host, port: port)
            return

        case "close":
            guard connection != nil else {
                writeError("No connection open.")
                break
            }
            await close()
            writeError("Connection closed.")

        case "quit", "q":
            await close()
            exit(0)

        case "status", "st":
            await printStatus()

        case "display", "d":
            writeError("escape character is '\(escapeName)'")
            writeError("local echo is \(localEcho ? "on" : "off")")
            writeError("debug is \(debug ? "on" : "off")")

        case "set":
            guard rest.count >= 2 else {
                writeError("usage: set escape <char>")
                break
            }
            if rest[0].hasPrefix("esc") {
                if rest[1] == "off" {
                    escapeCharacter = nil
                } else {
                    escapeCharacter = rest[1].utf8.first
                }
                writeError("escape character is '\(escapeName)'")
            } else {
                writeError("unknown variable \(rest[0])")
            }

        case "toggle":
            guard let name = rest.first?.lowercased() else {
                writeError("usage: toggle debug | toggle localecho")
                break
            }
            switch name {
            case "debug":
                debug.toggle()
                writeError("debug is \(debug ? "on" : "off")")
            case "localecho", "echo":
                localEcho.toggle()
                writeError("local echo is \(localEcho ? "on" : "off")")
            default:
                writeError("unknown toggle \(name)")
            }

        case "send":
            guard let name = rest.first?.lowercased(), let command = TelnetClient.command(named: name) else {
                writeError("usage: send ayt | break | ip | ao | ec | el | ga | nop | eof | eor")
                break
            }
            await send(command: command)

        case "environ":
            let user = arguments.user ?? NSUserName()
            let term = ProcessInfo.processInfo.environment["TERM"] ?? "xterm-256color"
            do {
                try await connection?.sendEnvironment(
                    [
                        EnvironmentVariable(name: "USER", value: user, scope: .variable),
                        EnvironmentVariable(name: "TERM", value: term, scope: .variable),
                    ],
                    scope: .variable
                )
            } catch {
                report(error)
            }

        case "z":
            if let settings = terminalSettings {
                Terminal.restore(settings)
                Terminal.suspend()
                terminalSettings = Terminal.enterRawMode() ?? settings
            } else {
                writeError("z is only available on a terminal")
            }

        case "help", "?":
            printCommandHelp()

        default:
            writeError("?Invalid command")
        }
        finishCommand()
    }

    private func finishCommand() {
        if connection != nil {
            inCommandMode = false
        } else {
            inCommandMode = true
            prompt()
        }
    }

    private func prompt() {
        writeError("telnet> ")
    }

    private func printStatus() async {
        guard let connection else {
            writeError("No connection open.")
            return
        }
        let remote = await connection.remoteAddress ?? "unknown"
        writeError("Connected to \(remote).")
        writeError("Escape character is '\(escapeName)'.")
        for option in [TelnetOption.echo, .suppressGoAhead, .binary] {
            let status = await connection.optionStatus(option)
            writeError(
                "\(option.displayName): local \(status.locallyEnabled ? "on" : "off")"
                    + ", remote \(status.remotelyEnabled ? "on" : "off")"
            )
        }
    }

    private func printCommandHelp() {
        writeError(
            """
            Commands:
              open host-name [port]   connect to a host
              close                   close the current connection
              quit                    exit telnetkit-client
              status                  show the connection and option state
              display                 show the client settings
              set escape <char|off>   change or disable the escape character
              toggle debug            print negotiation and command events
              toggle localecho        echo typed characters locally
              send <command>          send ayt, break, ip, ao, ec, el, ga, nop, eof, or eor
              environ                 send USER and TERM through NEW-ENVIRON
              z                       suspend the client
              help, ?                 this list
            """
        )
    }

    // MARK: Output

    private func send(bytes: [UInt8]) async {
        guard let connection else { return }
        do {
            try await connection.send(bytes)
        } catch {
            report(error)
        }
    }

    private func send(command: TelnetCommand) async {
        guard let connection else { return }
        do {
            try await connection.send(command: command)
        } catch {
            report(error)
        }
    }

    private func report(_ error: any Error) {
        if let error = error as? TelnetError {
            writeError("telnet: \(describe(error))")
        } else {
            writeError("telnet: \(error)")
        }
    }

    private func describe(_ error: TelnetError) -> String {
        switch error {
        case .invalidHost(let host): "could not resolve \(host)"
        case .connectionRefused(let host, let port): "connect to \(host):\(port): Connection refused"
        case .connectTimeout(let timeout): "connect timed out after \(timeout)"
        case .notConnected: "not connected"
        case .alreadyClosed: "connection already closed"
        case .transportFailed(let failure): failure.message
        case .protocolViolation(let error): "protocol error: \(error)"
        case .bufferOverflow(let limit): "input exceeded \(limit) bytes"
        case .subnegotiationTooLarge(let option, let limit): "\(option.displayName) payload exceeded \(limit) bytes"
        case .unsupportedFeature(let feature): "unsupported: \(feature)"
        case .invalidConfiguration(let reason): "invalid configuration: \(reason)"
        case .cancelled: "cancelled"
        }
    }

    private var escapeName: String {
        guard let escapeCharacter else { return "off" }
        if escapeCharacter < 0x20 {
            return "^" + String(UnicodeScalar(escapeCharacter + 0x40))
        }
        return String(UnicodeScalar(escapeCharacter))
    }

    private func writeOutput(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        FileHandle.standardOutput.write(Data(bytes))
    }

    private func writeError(_ text: String) {
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }

    private static func command(named name: String) -> TelnetCommand? {
        switch name {
        case "ayt": .areYouThere
        case "break", "brk": .brk
        case "ip": .interruptProcess
        case "ao": .abortOutput
        case "ec": .eraseCharacter
        case "el": .eraseLine
        case "ga": .goAhead
        case "nop": .noOperation
        case "eof": .endOfFile
        case "eor": .endOfRecord
        case "dm": .dataMark
        case "susp": .suspend
        case "abort": .abort
        default: nil
        }
    }
}
