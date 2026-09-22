import Foundation
import SwiftUI
import TelnetKit

/// How one event is shown in the log: a category that fixes its color, the library case it
/// came from, and a one-line detail.
///
/// `demoCategory`, `demoName`, and `demoDetail` switch over every `TelnetEvent` case with no
/// `default` arm, so a case added to the library fails this build instead of disappearing
/// from the log.
extension TelnetEvent {
    var demoCategory: DemoEventCategory {
        switch self {
        case .data: .data
        case .negotiation: .negotiation
        case .subnegotiation: .subnegotiation
        case .command: .command
        case .terminalTypeRequested, .terminalType: .terminal
        case .environmentRequested, .environment: .environment
        case .localEchoChanged: .echo
        case .mssp: .mssp
        case .zmp: .zmp
        case .compressionEnabled: .compression
        case .pathChanged, .betterPathAvailable, .betterPathUnavailable,
             .viabilityChanged, .waitingForConnectivity: .path
        case .warning: .warning
        case .protocolError: .error
        }
    }

    var demoName: String {
        switch self {
        case .data: "data"
        case .negotiation: "negotiation"
        case .subnegotiation: "subnegotiation"
        case .command: "command"
        case .terminalTypeRequested: "terminalTypeRequested"
        case .terminalType: "terminalType"
        case .environmentRequested: "environmentRequested"
        case .environment: "environment"
        case .localEchoChanged: "localEchoChanged"
        case .mssp: "mssp"
        case .zmp: "zmp"
        case .compressionEnabled: "compressionEnabled"
        case .pathChanged: "pathChanged"
        case .betterPathAvailable: "betterPathAvailable"
        case .betterPathUnavailable: "betterPathUnavailable"
        case .viabilityChanged: "viabilityChanged"
        case .waitingForConnectivity: "waitingForConnectivity"
        case .warning: "warning"
        case .protocolError: "protocolError"
        }
    }

    var demoDetail: String {
        switch self {
        case .data:
            return "\(bytes?.count ?? 0) bytes"
        case .negotiation(let action, let option, let remote):
            return "\(action.demoName) \(option.displayName) (\(option.rawValue)) from \(remote ? "peer" : "local end")"
        case .subnegotiation(let option, let payload):
            return "\(option.displayName) \(payload.count) bytes \(DemoHex.string(payload))"
        case .command(let command):
            return command.demoName
        case .terminalTypeRequested:
            return "TERMINAL-TYPE SEND; answer with replyTerminalType(_:)"
        case .terminalType(let name):
            return name
        case .environmentRequested(let scope):
            return "SEND for \(scope.demoName) variables"
        case .environment(let scope, let values):
            return "\(scope.demoName): " + values.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: ", ")
        case .localEchoChanged(let enabled):
            return enabled ? "this end echoes typed input" : "the peer echoes typed input"
        case .mssp(let values):
            return values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        case .zmp(let arguments):
            return arguments.joined(separator: " ")
        case .compressionEnabled(let enabled):
            return enabled ? "compressed" : "uncompressed"
        case .pathChanged(let viable, let expensive, let constrained):
            return "viable=\(viable) expensive=\(expensive) constrained=\(constrained)"
        case .betterPathAvailable:
            return "a preferred path is available"
        case .betterPathUnavailable:
            return "the preferred path went away"
        case .viabilityChanged(let isViable):
            return isViable ? "the path is usable" : "the path is not usable"
        case .waitingForConnectivity(let error, let description):
            return "\(error ?? "no error"): \(description)"
        case .warning(let warning):
            return warning.demoDescription
        case .protocolError(let error):
            return error.demoDescription
        }
    }
}

/// The color family one event log row belongs to.
enum DemoEventCategory: String, CaseIterable, Identifiable {
    case data
    case negotiation
    case subnegotiation
    case command
    case terminal
    case environment
    case echo
    case mssp
    case zmp
    case compression
    case path
    case warning
    case error
    case lifecycle

    var id: String { rawValue }

    var title: String { rawValue }

    var color: Color {
        switch self {
        case .data: .primary
        case .negotiation: .blue
        case .subnegotiation: .indigo
        case .command: .teal
        case .terminal: .green
        case .environment: .mint
        case .echo: .cyan
        case .mssp: .purple
        case .zmp: .pink
        case .compression: .brown
        case .path: .orange
        case .warning: .yellow
        case .error: .red
        case .lifecycle: .secondary
        }
    }
}

/// One row in the event log.
struct DemoEventRecord: Identifiable, Sendable {
    let id = UUID()
    let sequence: Int
    let category: DemoEventCategory
    let name: String
    let detail: String
}

/// One row in the log panel.
struct DemoRow: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// A named sample of a public value, for the panels that show every case without needing
/// live traffic.
struct DemoValueEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let value: String
}

extension TelnetNegotiation {
    var demoName: String {
        switch self {
        case .will: "will"
        case .wont: "wont"
        case .do: "do"
        case .dont: "dont"
        }
    }
}

extension TelnetCommand {
    var demoName: String {
        switch self {
        case .endOfFile: "endOfFile"
        case .suspend: "suspend"
        case .abort: "abort"
        case .endOfRecord: "endOfRecord"
        case .subnegotiationEnd: "subnegotiationEnd"
        case .noOperation: "noOperation"
        case .dataMark: "dataMark"
        case .brk: "brk"
        case .interruptProcess: "interruptProcess"
        case .abortOutput: "abortOutput"
        case .areYouThere: "areYouThere"
        case .eraseCharacter: "eraseCharacter"
        case .eraseLine: "eraseLine"
        case .goAhead: "goAhead"
        case .subnegotiation: "subnegotiation"
        case .will: "will"
        case .wont: "wont"
        case .do_: "do_"
        case .dont: "dont"
        }
    }
}

extension TelnetLineEnding {
    var demoName: String {
        switch self {
        case .crlf: "CR LF"
        case .crNul: "CR NUL"
        case .lf: "LF"
        case .none: "none"
        }
    }
}

extension EnvironmentScope {
    var demoName: String {
        switch self {
        case .variable: "variable"
        case .userVariable: "userVariable"
        }
    }
}

extension TelnetWarning {
    var demoDescription: String {
        switch self {
        case .truncatedSequence(let bytes):
            "truncatedSequence \(DemoHex.string(bytes))"
        case .unexpectedByte(let byte, let context):
            "unexpectedByte \(DemoHex.byte(byte)) in \(context)"
        case .subnegotiationTruncated(let option):
            "subnegotiationTruncated \(option.displayName)"
        case .eventBufferOverflowDropped(let count):
            "eventBufferOverflowDropped \(count) events"
        case .compressionUnavailable:
            "compressionUnavailable (no zlib in this build)"
        }
    }
}

extension TelnetProtocolError {
    var demoDescription: String {
        switch self {
        case .stateMachineFailure(let code, let message):
            "stateMachineFailure \(code.demoName): \(message)"
        case .invalidSubnegotiation(let option):
            "invalidSubnegotiation \(option.displayName)"
        case .outOfMemory:
            "outOfMemory"
        }
    }
}

extension TelnetErrorCode {
    var demoName: String {
        switch self {
        case .badValue: "badValue"
        case .outOfMemory: "outOfMemory"
        case .overflow: "overflow"
        case .protocol: "protocol"
        case .compression: "compression"
        }
    }
}

extension TelnetTransportFailure {
    var demoDescription: String {
        "\(kind.demoName): \(message) (retryable: \(isRetryable))"
    }
}

extension TelnetTransportFailure.Kind {
    var demoName: String {
        switch self {
        case .dns: "dns"
        case .posix(let code): "posix(\(code))"
        case .tls: "tls"
        case .channelClosed: "channelClosed"
        case .writeTimeout: "writeTimeout"
        case .other: "other"
        }
    }
}

/// Renders every `TelnetError` case, including the ones this build can only produce as a
/// value: `close()` is idempotent, so `.alreadyClosed` has no trigger, an inbound overflow
/// arrives as `.protocolError(...)`, and `.unsupportedFeature` covers a v0.2 capability.
extension TelnetError {
    var demoDescription: String {
        switch self {
        case .invalidHost(let host): "invalidHost: could not resolve \(host)"
        case .connectionRefused(let host, let port): "connectionRefused: \(host):\(port)"
        case .connectTimeout(let timeout): "connectTimeout after \(timeout)"
        case .notConnected: "notConnected"
        case .alreadyClosed: "alreadyClosed"
        case .transportFailed(let failure): "transportFailed \(failure.demoDescription)"
        case .protocolViolation(let error): "protocolViolation \(error.demoDescription)"
        case .bufferOverflow(let limit): "bufferOverflow at \(limit) bytes"
        case .subnegotiationTooLarge(let option, let limit):
            "subnegotiationTooLarge \(option.displayName) at \(limit) bytes"
        case .unsupportedFeature(let feature): "unsupportedFeature: \(feature)"
        case .invalidConfiguration(let reason): "invalidConfiguration: \(reason)"
        case .cancelled: "cancelled"
        }
    }

    var demoName: String {
        switch self {
        case .invalidHost: "invalidHost"
        case .connectionRefused: "connectionRefused"
        case .connectTimeout: "connectTimeout"
        case .notConnected: "notConnected"
        case .alreadyClosed: "alreadyClosed"
        case .transportFailed: "transportFailed"
        case .protocolViolation: "protocolViolation"
        case .bufferOverflow: "bufferOverflow"
        case .subnegotiationTooLarge: "subnegotiationTooLarge"
        case .unsupportedFeature: "unsupportedFeature"
        case .invalidConfiguration: "invalidConfiguration"
        case .cancelled: "cancelled"
        }
    }
}

/// Byte, hexadecimal, and text formatting shared by the panels.
enum DemoHex {
    static func byte(_ value: UInt8) -> String {
        String(format: "0x%02X", value)
    }

    static func string(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// Parses whitespace-separated hexadecimal pairs; nil when a token is not one.
    static func bytes(from hex: String) -> [UInt8]? {
        let tokens = hex.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," })
        var result: [UInt8] = []
        result.reserveCapacity(tokens.count)
        for token in tokens {
            guard token.count <= 2, let value = UInt8(token, radix: 16) else { return nil }
            result.append(value)
        }
        return result
    }
}
