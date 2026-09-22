import Foundation
import Logging

/// One log record the library emitted, captured for the demo's log panel.
struct DemoLogRecord: Identifiable, Sendable {
    let id = UUID()
    let level: DemoLoggerLevel
    let message: String
    let metadata: [String: String]
}

/// The demo's `swift-log` handler.
///
/// The demo installs it with `Logger(label:factory:)`, so it never bootstraps the global
/// `LoggingSystem` and two connections cannot share a handler by accident. `log(event:)` can
/// run on the connection's event loop, so the handler does no UI work itself: it hands the
/// record to a `@Sendable` sink that hops to the main actor.
struct DemoLogHandler: LogHandler {
    let label: String
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    private let sink: @Sendable (DemoLogRecord) -> Void

    init(label: String, sink: @escaping @Sendable (DemoLogRecord) -> Void) {
        self.label = label
        self.sink = sink
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        sink(
            DemoLogRecord(
                level: DemoLoggerLevel(level: event.level),
                message: "\(event.message)",
                metadata: (event.metadata ?? [:]).mapValues { "\($0)" }
            )
        )
    }
}
