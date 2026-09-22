import Foundation
import TelnetKit

/// The command line `telnetkit-client` accepts.
///
/// The flag set mirrors the `telnet(1)` that Homebrew installs, so an existing command
/// line keeps working. A flag whose capability this library cannot honor is reported
/// instead of being ignored silently: a refusal exits, and a caveat prints a warning.
struct ClientArguments {
    enum Outcome {
        case run(ClientArguments)
        case help(String)
        case refused(String)
    }

    var forceIPv4 = false
    var forceIPv6 = false
    var eightBit = false
    var noEscape = false
    var noAutoLogin = false
    var eightBitOutput = false
    var noNameLookup = false
    var noTelnetrc = false
    var debug = false
    var rloginMode = false
    var unixSocketOnly = false
    var encryptionRequested = false
    var suppressEncryption = false
    var forwardCredentials = false
    var tos: String?
    var disabledAuthType: String?
    var kerberosRealm: String?
    var user: String?
    var sourceAddress: String?
    var policy: String?
    var traceFile: String?
    var escapeCharacter: UInt8? = 0x1D
    var host: String?
    var port: Int = 23
    /// Capabilities that are accepted but not enforced, in the order encountered.
    var warnings: [String] = []

    static let usage = """
        usage: telnetkit-client [-4] [-6] [-8] [-E] [-K] [-L] [-N] [-S tos] [-X atype] [-c] [-d]
        \t[-e char] [-k realm] [-l user] [-f/-F] [-n tracefile] [-r] [-s src_addr] [-u] [-P policy] [host-name [port]]
        """

    static let help = """
        \(usage)

        A Telnet client built on the TelnetKit library. It accepts the telnet(1) flags so an
        existing command line keeps working; the flags below are accepted but not enforced
        because TelnetKit does not expose the capability:

          -4, -6        address family preference
          -N            reverse name lookup
          -S tos        IP type-of-service
          -s src_addr   source address
          -X atype      disabled authentication type
          -P policy     encryption policy
          -x            stream encryption: TelnetKit carries plaintext only

        These are refused outright because honoring them is impossible and pretending
        otherwise would misrepresent security:

          -f, -F, -k    Kerberos credential forwarding or realm
          -u, /path     AF_UNIX socket

        Once connected, the escape character (initially ^]) enters command mode; type
        `help` there for the available commands.
        """

    /// Parses `telnet(1)`-style arguments.
    static func parse(_ arguments: [String]) -> Outcome {
        var result = ClientArguments()
        var index = 0
        var operands: [String] = []

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                operands.append(contentsOf: arguments[(index + 1)...])
                break
            }
            if argument == "--help" || argument == "-h" {
                return .help(help)
            }
            guard argument.hasPrefix("-"), argument.count > 1 else {
                operands.append(argument)
                index += 1
                continue
            }

            let flags = Array(argument.dropFirst())
            var cursor = 0
            while cursor < flags.count {
                let flag = flags[cursor]
                cursor += 1

                func value(_ name: Character) -> String? {
                    if cursor < flags.count {
                        let rest = String(flags[cursor...])
                        cursor = flags.count
                        return rest
                    }
                    guard index + 1 < arguments.count else { return nil }
                    index += 1
                    return arguments[index]
                }

                switch flag {
                case "4": result.forceIPv4 = true
                case "6": result.forceIPv6 = true
                case "8": result.eightBit = true
                case "E": result.noEscape = true
                case "K": result.noAutoLogin = true
                case "L": result.eightBitOutput = true
                case "N": result.noNameLookup = true
                case "c": result.noTelnetrc = true
                case "d": result.debug = true
                case "r": result.rloginMode = true
                case "u": result.unixSocketOnly = true
                case "x": result.encryptionRequested = true
                case "y": result.suppressEncryption = true
                case "a":
                    // Automatic login is the default in telnet(1); accept and ignore.
                    break
                case "f", "F": result.forwardCredentials = true
                case "k":
                    guard let realm = value(flag) else { return .refused("option -k requires a realm") }
                    result.kerberosRealm = realm
                case "l":
                    guard let user = value(flag) else { return .refused("option -l requires a user") }
                    result.user = user
                case "e":
                    if cursor >= flags.count && index + 1 >= arguments.count {
                        // `-e` with no argument means no escape character.
                        result.escapeCharacter = nil
                    } else {
                        guard let text = value(flag), let byte = firstByte(of: text) else {
                            return .refused("option -e requires one character")
                        }
                        result.escapeCharacter = byte
                    }
                case "n":
                    guard let file = value(flag) else { return .refused("option -n requires a tracefile") }
                    result.traceFile = file
                case "s":
                    guard let address = value(flag) else { return .refused("option -s requires an address") }
                    result.sourceAddress = address
                case "S":
                    guard let tos = value(flag) else { return .refused("option -S requires a type-of-service") }
                    result.tos = tos
                case "X":
                    guard let type = value(flag) else { return .refused("option -X requires an authentication type") }
                    result.disabledAuthType = type
                case "P":
                    guard let policy = value(flag) else { return .refused("option -P requires a policy name") }
                    result.policy = policy
                default:
                    return .refused("illegal option -- \(flag)")
                }
            }
            index += 1
        }

        if result.rloginMode, !result.noEscape {
            result.escapeCharacter = UInt8(ascii: "~")
        }

        if let host = operands.first {
            if host.hasPrefix("/") {
                return .refused("AF_UNIX sockets are not supported by TelnetKit")
            }
            result.host = host
        }
        if operands.count > 1 {
            guard let port = Int(operands[1]), (1...65_535).contains(port) else {
                return .refused("invalid port: \(operands[1])")
            }
            result.port = port
        }

        if result.forwardCredentials || result.kerberosRealm != nil {
            return .refused("Kerberos authentication is not supported by TelnetKit")
        }
        if result.unixSocketOnly {
            return .refused("AF_UNIX sockets are not supported by TelnetKit")
        }

        if result.forceIPv4 && result.forceIPv6 {
            result.warnings.append("-4 and -6 together: the address family preference is not enforced")
        } else if result.forceIPv4 {
            result.warnings.append("-4: the address family preference is not enforced by TelnetKit")
        } else if result.forceIPv6 {
            result.warnings.append("-6: the address family preference is not enforced by TelnetKit")
        }
        if result.noNameLookup {
            result.warnings.append("-N: TelnetKit never reverse-resolves the peer")
        }
        if let tos = result.tos {
            result.warnings.append("-S \(tos): the IP type-of-service is not settable through TelnetKit")
        }
        if let address = result.sourceAddress {
            result.warnings.append("-s \(address): the source address is not settable through TelnetKit")
        }
        if let type = result.disabledAuthType {
            result.warnings.append("-X \(type): this client performs no authentication")
        }
        if let policy = result.policy {
            result.warnings.append("-P \(policy): TelnetKit sets no encryption policy")
        }
        if result.encryptionRequested {
            result.warnings.append("-x: TelnetKit carries plaintext Telnet only; no encryption is available")
        }
        return .run(result)
    }

    private static func firstByte(of text: String) -> UInt8? {
        if text == "^]" { return 0x1D }
        if text.hasPrefix("^"), text.count == 2, let scalar = text.last?.asciiValue {
            return scalar & 0x1F
        }
        return text.utf8.first
    }

    var configuration: TelnetConfiguration {
        // The client prints protocol activity itself, to stderr, so the library logger
        // stays off and server data on stdout is never interleaved with diagnostics.
        TelnetConfiguration(waitForConnectivity: true)
    }

    var options: TelnetOptions {
        var options = TelnetOptions.standardClient
        if eightBit || eightBitOutput {
            if !options.local.contains(where: { $0.option == .binary }) {
                options.local.append(.init(.binary))
            }
            if !options.remote.contains(where: { $0.option == .binary }) {
                options.remote.append(.init(.binary))
            }
        }
        // A client asks the peer to echo and does not offer to echo itself: `telnet(1)`
        // sends DO ECHO, so a telnetd keeps echoing. Offering WILL ECHO makes the peer
        // delegate echo to this end, which then has nothing to display.
        options.local.removeAll { $0.option == .echo }
        if !options.remote.contains(where: { $0.option == .echo }) {
            options.remote.append(.init(.echo))
        }
        return options
    }
}
