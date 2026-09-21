import NIOConcurrencyHelpers

/// The negotiation state the library tracks in Swift.
///
/// libtelnet 0.23 exports no query for negotiated option state, so `optionStatus(_:)` is
/// derived from the negotiations the core observes, never read from C state. The ledger is
/// written on the connection's EventLoop and read by `TelnetConnection` from any thread,
/// which is why it carries its own small lock instead of relying on the EventLoop.
final class TelnetOptionLedger: Sendable {
    private let entries = NIOLockedValueBox<[TelnetOption: TelnetOptionStatus]>([:])

    /// The ledger entry for one option; an unmentioned option reports all-false.
    func status(for option: TelnetOption) -> TelnetOptionStatus {
        entries.withLockedValue { $0[option] ?? TelnetOptionStatus() }
    }

    /// Records that this end sent a negotiation and its answer is outstanding.
    func markOutstanding(_ action: TelnetNegotiation, option: TelnetOption) {
        mutate(option) { status in
            switch action {
            case .will, .wont:
                status.localRequested = true
                status.locallyEnabled = false
            case .do, .dont:
                status.remoteRequested = true
                status.remotelyEnabled = false
            }
        }
    }

    /// Records a negotiation the peer sent.
    func recordInbound(_ action: TelnetNegotiation, option: TelnetOption) {
        mutate(option) { status in
            switch action {
            case .will:
                status.remotelyEnabled = true
                status.remoteRequested = false
            case .wont:
                status.remotelyEnabled = false
                status.remoteRequested = false
            case .do:
                status.locallyEnabled = true
                status.localRequested = false
            case .dont:
                status.locallyEnabled = false
                status.localRequested = false
            }
        }
    }

    /// Records a negotiation libtelnet emitted on its own, which is an answer that already
    /// settled the option in that direction.
    func recordAutomaticReply(_ action: TelnetNegotiation, option: TelnetOption) {
        mutate(option) { status in
            switch action {
            case .will:
                status.locallyEnabled = true
                status.localRequested = false
            case .wont:
                status.locallyEnabled = false
                status.localRequested = false
            case .do:
                status.remotelyEnabled = true
                status.remoteRequested = false
            case .dont:
                status.remotelyEnabled = false
                status.remoteRequested = false
            }
        }
    }

    private func mutate(_ option: TelnetOption, _ body: (inout TelnetOptionStatus) -> Void) {
        entries.withLockedValue { entries in
            var status = entries[option] ?? TelnetOptionStatus()
            body(&status)
            entries[option] = status
        }
    }
}
