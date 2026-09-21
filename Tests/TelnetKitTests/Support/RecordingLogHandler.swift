import Logging
import NIOConcurrencyHelpers

/// Captures every record a `Logger` emits, for the logging tests.
final class RecordingLogHandler: LogHandler, Sendable {
    struct Record: Sendable {
        let level: Logger.Level
        let message: String
        let metadata: [String: String]
    }

    private struct State: Sendable {
        var logLevel: Logger.Level = .trace
        var metadata: Logger.Metadata = [:]
        var records: [Record] = []
    }

    private let state = NIOLockedValueBox(State())

    var logLevel: Logger.Level {
        get { state.withLockedValue { $0.logLevel } }
        set { state.withLockedValue { $0.logLevel = newValue } }
    }

    var metadata: Logger.Metadata {
        get { state.withLockedValue { $0.metadata } }
        set { state.withLockedValue { $0.metadata = newValue } }
    }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { state.withLockedValue { $0.metadata[key] } }
        set { state.withLockedValue { $0.metadata[key] = newValue } }
    }

    func log(event: LogEvent) {
        var flattened: [String: String] = [:]
        if let metadata = event.metadata {
            for (key, value) in metadata {
                flattened[key] = "\(value)"
            }
        }
        let record = Record(level: event.level, message: event.message.description, metadata: flattened)
        state.withLockedValue { $0.records.append(record) }
    }

    var records: [Record] { state.withLockedValue { $0.records } }

    var levels: Set<Logger.Level> { Set(records.map(\.level)) }

    /// Every message and metadata value joined, for a redaction assertion.
    var allText: String {
        records
            .map { $0.message + " " + $0.metadata.values.joined(separator: " ") }
            .joined(separator: "\n")
    }
}
