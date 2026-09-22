/// The command line `telnetkit-echo-server` accepts.
struct ServerArguments: Sendable {
    enum Outcome {
        case run(ServerArguments)
        case help(String)
        case refused(String)
    }

    /// A malformed exchange the server sends after its initial negotiation.
    ///
    /// Each one is a byte sequence a well-behaved peer never produces, so this fixture is the
    /// only local way to watch how a caller handles it. `oversized` closes the connection, and
    /// `parse` orders the scenarios so it is always sent last.
    enum Scenario: String, CaseIterable, Sendable {
        case negotiation
        case subnegotiation
        case warning
        case oversized
    }

    var host = "127.0.0.1"
    var port = 2323
    var scenarios: [Scenario] = []

    static let usage = """
        usage: telnetkit-echo-server [--host address] [--port port] [--inject scenario]...
        """

    static let help = """
        \(usage)

        A local Telnet echo server for `telnetkit-client` and the SwiftUI demo app. It answers
        the peer's negotiation, answers TERMINAL-TYPE, NAWS, and NEW-ENVIRON, prints what it
        receives, and echoes session data back with `0xFF` escaped. `CR NUL` and `CR LF` from
        the peer are echoed as one `CR LF`, so an interactive session shows its line endings.

        It binds `127.0.0.1` by default, which keeps the plaintext service off the local
        network; pass `--host` to change that deliberately. Port 0 binds an ephemeral port and
        prints the port it chose.

        Options:
          --host address      address to bind (default 127.0.0.1)
          --port port         port to bind, 0 for an ephemeral port (default 2323)
          --inject scenario   send a malformed exchange after the initial negotiation; may be
                              repeated. `all` selects every scenario
          -h, --help          this message

        Scenarios:
          negotiation     WILL for an option the client never declared; the client refuses it
                          with DONT and the library raises no event for the code
          subnegotiation  a subnegotiation for an unknown option, with an escaped 0xFF
          warning         NEW-ENVIRON with an invalid command byte, which the peer reports as
                          a warning and survives
          oversized       a subnegotiation past the peer's 8 KiB inbound limit, which the peer
                          reports as a protocol error and closes
        """

    /// Parses the command line.
    static func parse(_ arguments: [String]) -> Outcome {
        var result = ServerArguments()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            let (name, inlineValue) = optionParts(argument)

            switch name {
            case "-h", "--help":
                return .help(help)
            case "--host":
                guard let value = inlineValue ?? nextValue(arguments, &index) else {
                    return .refused("--host requires an address")
                }
                result.host = value
            case "--port":
                guard let value = inlineValue ?? nextValue(arguments, &index),
                      let port = Int(value), (0...65_535).contains(port) else {
                    return .refused("--port requires a number from 0 to 65535")
                }
                result.port = port
            case "--inject":
                guard let value = inlineValue ?? nextValue(arguments, &index) else {
                    return .refused("--inject requires a scenario")
                }
                if value == "all" {
                    result.scenarios = Scenario.allCases
                } else if let scenario = Scenario(rawValue: value) {
                    if !result.scenarios.contains(scenario) { result.scenarios.append(scenario) }
                } else {
                    return .refused("unknown scenario: \(value)")
                }
            default:
                return .refused("unknown argument: \(argument)")
            }
        }

        result.scenarios.sort { $0.order < $1.order }
        return .run(result)
    }

    private static func optionParts(_ argument: String) -> (name: String, inlineValue: String?) {
        guard let separator = argument.firstIndex(of: "=") else { return (argument, nil) }
        return (String(argument[argument.startIndex..<separator]), String(argument[argument.index(after: separator)...]))
    }

    private static func nextValue(_ arguments: [String], _ index: inout Int) -> String? {
        guard index < arguments.count else { return nil }
        let value = arguments[index]
        index += 1
        return value
    }
}

extension ServerArguments.Scenario {
    /// The position in which the server sends this scenario; `oversized` is last because it is
    /// the one that ends the connection.
    var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}
