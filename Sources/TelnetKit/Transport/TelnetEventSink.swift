import NIOConcurrencyHelpers

/// Delivers events to the caller's stream under the configured buffer policy.
///
/// `AsyncStream` reports a drop when its buffer is full; the sink turns that report into
/// the `.warning(.eventBufferOverflowDropped(count:))` the caller contract promises
/// instead of losing an event silently.
final class TelnetEventSink: Sendable {
    private struct State: Sendable {
        var finished = false
        var dropped = 0
    }

    private let continuation: AsyncStream<TelnetEvent>.Continuation
    private let policy: TelnetEventBufferPolicy
    private let state = NIOLockedValueBox(State())

    init(continuation: AsyncStream<TelnetEvent>.Continuation, policy: TelnetEventBufferPolicy) {
        self.continuation = continuation
        self.policy = policy
    }

    func yield(_ event: TelnetEvent) {
        guard !state.withLockedValue({ $0.finished }) else { return }
        switch continuation.yield(event) {
        case .enqueued:
            break
        case .dropped:
            handleDrop()
        case .terminated:
            state.withLockedValue { $0.finished = true }
        @unknown default:
            break
        }
    }

    func finish() {
        let alreadyFinished = state.withLockedValue { state -> Bool in
            let previous = state.finished
            state.finished = true
            return previous
        }
        if !alreadyFinished {
            continuation.finish()
        }
    }

    private func handleDrop() {
        switch policy {
        case .bounded:
            // The buffer holds the oldest events and refused this one: report the drop and
            // finish, as the caller contract states.
            _ = continuation.yield(.warning(.eventBufferOverflowDropped(count: 1)))
            state.withLockedValue { $0.finished = true }
            continuation.finish()
        case .dropOldest:
            let count = state.withLockedValue { state -> Int in
                state.dropped += 1
                return state.dropped
            }
            _ = continuation.yield(.warning(.eventBufferOverflowDropped(count: count)))
        case .unbounded:
            break
        }
    }
}
