import Foundation
import TelnetKit

/// One sample of every public error, warning, and code value.
///
/// Some cases have no trigger in this build: `close()` is idempotent so `.alreadyClosed`
/// never arrives, an inbound overflow is reported as `.protocolError`, and MCCP2 is out of
/// scope so `.unsupportedFeature` and `.compressionUnavailable` are reserved. The panel
/// shows them as values, and the injection menu produces the rest for real.
enum DemoCatalogs {
    static let errors: [DemoValueEntry] = [
        entry(.invalidHost("no-such-host.invalid")),
        entry(.connectionRefused(host: "127.0.0.1", port: 1)),
        entry(.connectTimeout(.seconds(1))),
        entry(.notConnected),
        entry(.alreadyClosed),
        entry(
            .transportFailed(
                TelnetTransportFailure(kind: .dns, message: "name resolution failed", isRetryable: true)
            )
        ),
        entry(.protocolViolation(.invalidSubnegotiation(option: .windowSize))),
        entry(.bufferOverflow(limit: 65_536)),
        entry(.subnegotiationTooLarge(option: .newEnvironment, limit: 8_192)),
        entry(.unsupportedFeature("MCCP2 compression")),
        entry(.invalidConfiguration("binary and lineMode are both local")),
        entry(.cancelled),
    ]

    static let warnings: [DemoValueEntry] = [
        entry(TelnetWarning.truncatedSequence([0xFF, 0xFB])),
        entry(TelnetWarning.unexpectedByte(0x00, context: "subnegotiation")),
        entry(TelnetWarning.subnegotiationTruncated(option: .terminalType)),
        entry(TelnetWarning.eventBufferOverflowDropped(count: 12)),
        entry(TelnetWarning.compressionUnavailable),
    ]

    static let protocolErrors: [DemoValueEntry] = [
        entry(TelnetProtocolError.stateMachineFailure(code: .overflow, message: "subnegotiation too long")),
        entry(TelnetProtocolError.invalidSubnegotiation(option: .windowSize)),
        entry(TelnetProtocolError.outOfMemory),
    ]

    static let errorCodes: [DemoValueEntry] = TelnetErrorCode.allCases.map {
        DemoValueEntry(name: $0.demoName, value: "TelnetErrorCode.\($0.demoName)")
    }

    static let transportKinds: [DemoValueEntry] = [
        entry(TelnetTransportFailure.Kind.dns),
        entry(TelnetTransportFailure.Kind.posix(code: 61)),
        entry(TelnetTransportFailure.Kind.tls),
        entry(TelnetTransportFailure.Kind.channelClosed),
        entry(TelnetTransportFailure.Kind.writeTimeout),
        entry(TelnetTransportFailure.Kind.other),
    ]

    private static func entry(_ error: TelnetError) -> DemoValueEntry {
        DemoValueEntry(name: error.demoName, value: error.demoDescription)
    }

    private static func entry(_ warning: TelnetWarning) -> DemoValueEntry {
        DemoValueEntry(name: "\(warning)".prefix(while: { $0 != "(" }).description, value: warning.demoDescription)
    }

    private static func entry(_ error: TelnetProtocolError) -> DemoValueEntry {
        DemoValueEntry(name: "\(error)".prefix(while: { $0 != "(" }).description, value: error.demoDescription)
    }

    private static func entry(_ kind: TelnetTransportFailure.Kind) -> DemoValueEntry {
        DemoValueEntry(name: kind.demoName, value: "TelnetTransportFailure.Kind.\(kind.demoName)")
    }
}
