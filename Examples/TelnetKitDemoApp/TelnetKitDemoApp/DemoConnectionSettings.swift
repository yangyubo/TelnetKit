import Foundation
import Logging
import TelnetKit

/// The connection form, and the conversion from form values to the library's option set and
/// configuration.
///
/// Every parameter of `TelnetConfiguration.init` and every option list of `TelnetOptions`
/// appears here, so the settings panel can reach all of them.
struct DemoConnectionSettings {
    // MARK: Endpoint
    var host = "127.0.0.1"
    var port = 2323

    // MARK: TelnetConfiguration.connectTimeout
    var connectTimeoutSeconds = 10.0
    // MARK: TelnetConfiguration.idleTimeout
    var idleTimeoutEnabled = false
    var idleTimeoutSeconds = 30.0
    // MARK: TelnetConfiguration.inboundBufferLimit
    var inboundBufferLimit = 65_536
    // MARK: TelnetConfiguration.subnegotiationLimit
    var subnegotiationLimit = 8_192
    // MARK: TelnetConfiguration.eventBufferPolicy
    var eventBufferPolicy = DemoEventBufferPolicy.bounded
    var eventBufferCount = 1_024
    // MARK: TelnetConfiguration.newlinePolicy
    var newlinePolicy = DemoNewlinePolicy.nvt
    // MARK: TelnetConfiguration.waitForConnectivity
    var waitForConnectivity = true
    // MARK: TelnetConfiguration.logger
    var loggingEnabled = false
    var logLevel = DemoLoggerLevel.debug

    // MARK: TelnetOptions
    /// Options this end offers with `will`. The initial set is `TelnetOptions.standardClient`.
    var localOptions: Set<TelnetOption> = DemoConnectionSettings.standardLocalOptions
    /// Options this end requests with `do`. The initial set is `TelnetOptions.standardClient`.
    var remoteOptions: Set<TelnetOption> = DemoConnectionSettings.standardRemoteOptions

    private static var standardLocalOptions: Set<TelnetOption> {
        Set(TelnetOptions.standardClient.local.filter(\.enabledByDefault).map(\.option))
    }

    private static var standardRemoteOptions: Set<TelnetOption> {
        Set(TelnetOptions.standardClient.remote.filter(\.requestOnConnect).map(\.option))
    }

    /// The option set the connection is opened with.
    var telnetOptions: TelnetOptions {
        TelnetOptions(
            local: localOptions.sorted { $0.rawValue < $1.rawValue }
                .map { TelnetOptions.LocalOption($0) },
            remote: remoteOptions.sorted { $0.rawValue < $1.rawValue }
                .map { TelnetOptions.RemoteOption($0) }
        )
    }

    /// Replaces both lists with `TelnetOptions.standardClient`, the `telnet(1)` client role.
    mutating func applyStandardClient() {
        let options = TelnetOptions.standardClient
        localOptions = Set(options.local.filter(\.enabledByDefault).map(\.option))
        remoteOptions = Set(options.remote.filter(\.requestOnConnect).map(\.option))
    }

    /// Replaces both lists with `TelnetOptions.serverRequesting(_:)`, the peer-side set a
    /// server caller declares so the client answers them.
    mutating func applyServerRequesting(_ requested: [TelnetOption]) {
        let options = TelnetOptions.serverRequesting(requested)
        localOptions = Set(options.local.filter(\.enabledByDefault).map(\.option))
        remoteOptions = Set(options.remote.filter(\.requestOnConnect).map(\.option))
    }

    /// The configuration the connection is opened with.
    ///
    /// `sink` receives the library's log records; the handler is installed per connection
    /// through `Logger(label:factory:)` rather than through a global `LoggingSystem` bootstrap.
    func configuration(sink: @escaping @Sendable (DemoLogRecord) -> Void) -> TelnetConfiguration {
        var logger: Logger?
        if loggingEnabled {
            var configured = Logger(label: "TelnetKitDemoApp") { label in
                DemoLogHandler(label: label, sink: sink)
            }
            configured.logLevel = logLevel.loggerLevel
            logger = configured
        }
        return TelnetConfiguration(
            connectTimeout: .seconds(connectTimeoutSeconds),
            idleTimeout: idleTimeoutEnabled ? .seconds(idleTimeoutSeconds) : nil,
            inboundBufferLimit: inboundBufferLimit,
            subnegotiationLimit: subnegotiationLimit,
            eventBufferPolicy: eventBufferPolicy.policy(count: eventBufferCount),
            newlinePolicy: newlinePolicy.policy,
            waitForConnectivity: waitForConnectivity,
            logger: logger
        )
    }
}

/// The `TelnetEventBufferPolicy` cases, as a picker can iterate them.
enum DemoEventBufferPolicy: String, CaseIterable, Identifiable {
    case bounded
    case unbounded
    case dropOldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bounded: "bounded"
        case .unbounded: "unbounded"
        case .dropOldest: "dropOldest"
        }
    }

    func policy(count: Int) -> TelnetEventBufferPolicy {
        switch self {
        case .bounded: .bounded(count)
        case .unbounded: .unbounded
        case .dropOldest: .dropOldest(count)
        }
    }
}

/// The `TelnetNewlinePolicy` cases, as a picker can iterate them.
enum DemoNewlinePolicy: String, CaseIterable, Identifiable {
    case nvt
    case raw

    var id: String { rawValue }
    var title: String { rawValue }

    var policy: TelnetNewlinePolicy {
        switch self {
        case .nvt: .nvt
        case .raw: .raw
        }
    }
}

/// The log levels the demo exposes, mapped to `Logger.Level`.
enum DemoLoggerLevel: String, CaseIterable, Identifiable {
    case trace
    case debug
    case info
    case notice
    case warning
    case error
    case critical

    var id: String { rawValue }

    var loggerLevel: Logger.Level {
        switch self {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
    }

    init(level: Logger.Level) {
        self = switch level {
        case .trace: .trace
        case .debug: .debug
        case .info: .info
        case .notice: .notice
        case .warning: .warning
        case .error: .error
        case .critical: .critical
        }
    }
}
