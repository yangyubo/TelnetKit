import CLibTelnet
import Logging
import NIOConcurrencyHelpers
import NIOCore

/// One outbound operation the connection asks the core to perform on its EventLoop.
///
/// The public actor never calls a `telnet_*` function: it writes one of these through the
/// channel, and the handler runs it on the owning EventLoop so every C call stays on one
/// thread.
struct TelnetOutboundCommand: Sendable {
    enum Kind: Sendable {
        case send([UInt8])
        case sendText(String, TelnetLineEnding)
        case sendRaw([UInt8])
        case command(TelnetCommand)
        case negotiate(TelnetNegotiation, TelnetOption)
        case requestOption(TelnetOption)
        case subnegotiate(TelnetOption, [UInt8])
        case replyTerminalType(String)
        case sendEnvironment([EnvironmentVariable], EnvironmentScope)
        case sendWindowSize(columns: Int, rows: Int)
    }

    let kind: Kind
    let negotiationOutcome: NegotiationOutcome?

    init(_ kind: Kind, negotiationOutcome: NegotiationOutcome? = nil) {
        self.kind = kind
        self.negotiationOutcome = negotiationOutcome
    }
}

/// Carries `negotiate(_:option:)`'s result from the EventLoop back to the actor without
/// turning the write promise into a second type.
final class NegotiationOutcome: Sendable {
    private let box = NIOLockedValueBox<Bool>(false)

    var wasSent: Bool { box.withLockedValue { $0 } }
    func set(_ value: Bool) { box.withLockedValue { $0 = value } }
}

/// The bytes an outbound operation produced, plus its negotiation result.
struct TelnetCoreOutcome {
    var bytes: [UInt8]
    var negotiationSent: Bool
}

/// The Swift wrapper over one `telnet_t`.
///
/// Every method runs on the EventLoop that owns the channel. `@unchecked Sendable` names
/// that invariant: the core is created while the handler is added and is touched only from
/// that loop, so no concurrent access exists. The `concurrent_connections_are_isolated`
/// and `concurrent_sends_serialized` tests exercise it.
final class TelnetProtocolCore: @unchecked Sendable {
    private let options: TelnetOptions
    private let configuration: TelnetConfiguration
    private let ledger: TelnetOptionLedger
    private let logger: Logger?
    private let emit: @Sendable (TelnetEvent) -> Void

    private var handle: OpaquePointer?
    private var optionTable: UnsafeMutableBufferPointer<telnet_telopt_t>?
    private var outbound: [UInt8] = []
    private var truncation = TelnetTruncationTracker()
    private var bytesSinceDataEvent = 0
    private var sawDataEventThisFeed = false
    private var terminalTypeRequestPending = false
    private var pendingFatal: TelnetError?

    init(
        options: TelnetOptions,
        configuration: TelnetConfiguration,
        ledger: TelnetOptionLedger,
        logger: Logger?,
        emit: @escaping @Sendable (TelnetEvent) -> Void
    ) throws(TelnetError) {
        self.options = options
        self.configuration = configuration
        self.ledger = ledger
        self.logger = logger
        self.emit = emit

        let table = TelnetProtocolCore.optionTable(for: options)
        let buffer = UnsafeMutableBufferPointer<telnet_telopt_t>.allocate(capacity: table.count)
        _ = buffer.initialize(from: table)
        self.optionTable = buffer

        var flags: UInt8 = 0
        if configuration.newlinePolicy == .nvt {
            flags |= UInt8(TELNET_FLAG_NVT_EOL)
        }
        guard
            let handle = telnet_init(
                buffer.baseAddress,
                TelnetProtocolCore.eventCallback,
                flags,
                Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            buffer.deallocate()
            self.optionTable = nil
            throw TelnetError.protocolViolation(.outOfMemory)
        }
        self.handle = handle
    }

    /// Frees `telnet_t` on the owning EventLoop. Idempotent, so `deinit` is a safety net
    /// rather than the usual path.
    func destroy() {
        if let handle {
            telnet_free(handle)
        }
        handle = nil
        optionTable?.deallocate()
        optionTable = nil
    }

    deinit {
        if let handle {
            telnet_free(handle)
        }
        optionTable?.deallocate()
    }

    // MARK: Outbound

    func perform(_ kind: TelnetOutboundCommand.Kind) throws(TelnetError) -> TelnetCoreOutcome {
        switch kind {
        case .send(let bytes):
            return TelnetCoreOutcome(bytes: send(bytes), negotiationSent: true)
        case .sendText(let text, let lineEnding):
            return TelnetCoreOutcome(bytes: sendText(text, lineEnding: lineEnding), negotiationSent: true)
        case .sendRaw(let bytes):
            return TelnetCoreOutcome(bytes: sendRaw(bytes), negotiationSent: true)
        case .command(let command):
            return TelnetCoreOutcome(bytes: send(command: command), negotiationSent: true)
        case .negotiate(let action, let option):
            let bytes = negotiate(action, option: option)
            return TelnetCoreOutcome(bytes: bytes, negotiationSent: !bytes.isEmpty)
        case .requestOption(let option):
            return TelnetCoreOutcome(bytes: try requestOption(option), negotiationSent: true)
        case .subnegotiate(let option, let payload):
            return TelnetCoreOutcome(bytes: try subnegotiate(option: option, payload: payload), negotiationSent: true)
        case .replyTerminalType(let type):
            return TelnetCoreOutcome(bytes: try replyTerminalType(type), negotiationSent: true)
        case .sendEnvironment(let values, let scope):
            return TelnetCoreOutcome(bytes: try sendEnvironment(values, scope: scope), negotiationSent: true)
        case .sendWindowSize(let columns, let rows):
            return TelnetCoreOutcome(bytes: try sendWindowSize(columns: columns, rows: rows), negotiationSent: true)
        }
    }

    /// Sends the connect-time `will`/`do` set from `TelnetOptions`.
    func sendInitialNegotiation() -> [UInt8] {
        guard let handle else { return [] }
        outbound.removeAll(keepingCapacity: true)
        for local in options.local where local.enabledByDefault {
            ledger.markOutstanding(.will, option: local.option)
            telnet_negotiate(handle, UInt8(TELNET_WILL), local.option.rawValue)
        }
        for remote in options.remote where remote.requestOnConnect {
            ledger.markOutstanding(.do, option: remote.option)
            telnet_negotiate(handle, UInt8(TELNET_DO), remote.option.rawValue)
        }
        return drainOutbound()
    }

    /// Sends `will` for an option this end provides or `do` for one it wants from the peer.
    func requestOption(_ option: TelnetOption) throws(TelnetError) -> [UInt8] {
        if options.local.contains(where: { $0.option == option }) {
            return negotiate(.will, option: option)
        }
        if options.remote.contains(where: { $0.option == option }) {
            return negotiate(.do, option: option)
        }
        throw TelnetError.invalidConfiguration(
            "option \(option.displayName) is in neither the local nor the remote option list"
        )
    }

    // MARK: Inbound

    /// Feeds peer bytes to the state machine and returns a fatal error when the machine
    /// cannot continue. Recoverable anomalies arrive as `.warning` events.
    func feed(_ bytes: [UInt8]) -> TelnetError? {
        guard let handle, !bytes.isEmpty else { return nil }
        sawDataEventThisFeed = false
        truncation.feed(bytes)
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            telnet_recv(handle, base.assumingMemoryBound(to: CChar.self), bytes.count)
        }
        if sawDataEventThisFeed {
            bytesSinceDataEvent = 0
        } else {
            bytesSinceDataEvent += bytes.count
        }
        recordAutomaticReplies(in: outbound)
        if bytesSinceDataEvent > configuration.inboundBufferLimit {
            let limit = configuration.inboundBufferLimit
            emit(.protocolError(.stateMachineFailure(code: .overflow, message: "inbound buffer limit exceeded")))
            logger?.error("inbound buffer limit exceeded", metadata: ["limit": "\(limit)"])
            return .bufferOverflow(limit: limit)
        }
        if let fatal = pendingFatal {
            pendingFatal = nil
            return fatal
        }
        return nil
    }

    /// Emits the end-of-stream truncation warning the peer's close would otherwise hide.
    func finish() {
        if let trailing = truncation.truncatedSequence {
            emit(.warning(.truncatedSequence(trailing)))
        }
    }

    func drainOutbound() -> [UInt8] {
        defer { outbound.removeAll(keepingCapacity: true) }
        return outbound
    }

    // MARK: Sending primitives

    private func send(_ bytes: [UInt8]) -> [UInt8] {
        guard let handle, !bytes.isEmpty else { return [] }
        outbound.removeAll(keepingCapacity: true)
        // `telnet_send` performs the NVT `0xFF` escaping itself, so the bytes go in raw.
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            telnet_send(handle, base.assumingMemoryBound(to: CChar.self), bytes.count)
        }
        return drainOutbound()
    }

    private func sendText(_ text: String, lineEnding: TelnetLineEnding) -> [UInt8] {
        let raw = Array(text.utf8)
        let translated: [UInt8]
        if configuration.newlinePolicy == .nvt, !ledger.status(for: .binary).locallyEnabled {
            translated = TelnetWireCoding.applyLineEnding(raw, ending: lineEnding)
        } else {
            translated = raw
        }
        return send(translated)
    }

    private func sendRaw(_ bytes: [UInt8]) -> [UInt8] {
        guard !bytes.isEmpty else { return [] }
        // No escaping and no line-ending translation: the bytes go out exactly as given.
        outbound.removeAll(keepingCapacity: true)
        outbound.append(contentsOf: bytes)
        return drainOutbound()
    }

    private func send(command: TelnetCommand) -> [UInt8] {
        guard let handle else { return [] }
        outbound.removeAll(keepingCapacity: true)
        telnet_iac(handle, command.rawValue)
        return drainOutbound()
    }

    private func negotiate(_ action: TelnetNegotiation, option: TelnetOption) -> [UInt8] {
        guard let handle else { return [] }
        outbound.removeAll(keepingCapacity: true)
        ledger.markOutstanding(action, option: option)
        telnet_negotiate(handle, action.wireCode, option.rawValue)
        return drainOutbound()
    }

    private func subnegotiate(option: TelnetOption, payload: [UInt8]) throws(TelnetError) -> [UInt8] {
        guard let handle else { return [] }
        guard payload.count <= configuration.subnegotiationLimit else {
            throw TelnetError.subnegotiationTooLarge(option: option, limit: configuration.subnegotiationLimit)
        }
        outbound.removeAll(keepingCapacity: true)
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            telnet_subnegotiation(
                handle,
                option.rawValue,
                base.assumingMemoryBound(to: CChar.self),
                payload.count
            )
        }
        return drainOutbound()
    }

    private func replyTerminalType(_ type: String) throws(TelnetError) -> [UInt8] {
        guard terminalTypeRequestPending else {
            throw TelnetError.invalidConfiguration("no terminal-type request is pending")
        }
        guard let handle else { return [] }
        outbound.removeAll(keepingCapacity: true)
        type.withCString { pointer in
            telnet_ttype_is(handle, pointer)
        }
        terminalTypeRequestPending = false
        return drainOutbound()
    }

    private func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) throws(TelnetError) -> [UInt8] {
        let payload = TelnetWireCoding.encodeEnvironment(values, scope: scope)
        return try subnegotiate(option: .newEnvironment, payload: payload)
    }

    private func sendWindowSize(columns: Int, rows: Int) throws(TelnetError) -> [UInt8] {
        guard (0...65_535).contains(columns), (0...65_535).contains(rows) else {
            throw TelnetError.invalidConfiguration("window size \(columns)x\(rows) is outside 0...65535")
        }
        let payload = TelnetWireCoding.encodeWindowSize(columns: columns, rows: rows)
        return try subnegotiate(option: .windowSize, payload: payload)
    }

    // MARK: Event handling

    private static let eventCallback: telnet_event_handler_t = { _, eventPointer, userData in
        guard let eventPointer, let userData else { return }
        let core = Unmanaged<TelnetProtocolCore>.fromOpaque(userData).takeUnretainedValue()
        // Every payload pointer in the union expires when this callback returns; the core
        // copies bytes and strings into Swift values here and never stores a pointer.
        core.handle(eventPointer.pointee)
    }

    private func handle(_ event: telnet_event_t) {
        switch event.type {
        case TELNET_EV_DATA:
            let data = event.data
            let bytes = Array(UnsafeRawBufferPointer(start: data.buffer, count: data.size))
            guard !bytes.isEmpty else { return }
            sawDataEventThisFeed = true
            emit(.data(ByteBuffer(bytes: bytes)))

        case TELNET_EV_SEND:
            let data = event.data
            outbound.append(contentsOf: UnsafeRawBufferPointer(start: data.buffer, count: data.size))

        case TELNET_EV_IAC:
            let code = event.iac.cmd
            if let command = TelnetCommand(rawValue: code) {
                emit(.command(command))
            } else {
                emit(.warning(.unexpectedByte(code, context: "unknown command")))
            }

        case TELNET_EV_WILL, TELNET_EV_WONT, TELNET_EV_DO, TELNET_EV_DONT:
            handleNegotiation(event)

        case TELNET_EV_SUBNEGOTIATION:
            handleSubnegotiation(event)

        case TELNET_EV_TTYPE:
            handleTerminalType(event)

        case TELNET_EV_ENVIRON:
            handleEnvironment(event)

        case TELNET_EV_MSSP:
            handleMSSP(event)

        case TELNET_EV_ZMP:
            handleZMP(event)

        case TELNET_EV_COMPRESS:
            emit(.compressionEnabled(event.compress.state == 1))

        case TELNET_EV_WARNING:
            handleWarning(event)

        case TELNET_EV_ERROR:
            handleError(event)

        default:
            // libtelnet 0.23 defines 15 event types; a value outside them is a library
            // defect rather than peer input, and it must not crash the connection.
            emit(.warning(.unexpectedByte(0, context: "unknown libtelnet event")))
        }
    }

    private func handleNegotiation(_ event: telnet_event_t) {
        let option = TelnetOption(rawValue: event.neg.telopt)
        let action: TelnetNegotiation
        switch event.type {
        case TELNET_EV_WILL: action = .will
        case TELNET_EV_WONT: action = .wont
        case TELNET_EV_DO: action = .do
        default: action = .dont
        }
        ledger.recordInbound(action, option: option)
        emit(.negotiation(action, option: option, remote: true))
        if option == .echo, action == .will || action == .wont {
            emit(.localEchoChanged(enabled: action == .will))
        }
    }

    private func handleSubnegotiation(_ event: telnet_event_t) {
        let sub = event.sub
        let option = TelnetOption(rawValue: sub.telopt)
        let payload = Array(UnsafeRawBufferPointer(start: sub.buffer, count: sub.size))
        if payload.count > configuration.subnegotiationLimit {
            emit(.protocolError(.invalidSubnegotiation(option: option)))
            pendingFatal = .protocolViolation(.invalidSubnegotiation(option: option))
            return
        }
        // TTYPE, NEW-ENVIRON/ENVIRON, MSSP, and ZMP each get a structured case below; the
        // generic case exists for every other option.
        switch option {
        case .terminalType, .environment, .newEnvironment, .mssp, .zmp:
            return
        default:
            emit(.subnegotiation(option: option, payload: payload))
        }
    }

    private func handleTerminalType(_ event: telnet_event_t) {
        let ttype = event.ttype
        if ttype.cmd == UInt8(TELNET_TTYPE_IS) {
            guard let name = ttype.name else { return }
            emit(.terminalType(String(cString: name)))
        } else {
            terminalTypeRequestPending = true
            emit(.terminalTypeRequested)
        }
    }

    private func handleEnvironment(_ event: telnet_event_t) {
        let environ = event.environ
        if environ.cmd == UInt8(TELNET_ENVIRON_SEND) {
            emit(.environmentRequested(.variable))
            return
        }
        guard let pointer = environ.values, environ.size > 0 else {
            emit(.environment(.variable, []))
            return
        }
        var values: [EnvironmentVariable] = []
        values.reserveCapacity(environ.size)
        var scope: EnvironmentScope = .variable
        for index in 0..<environ.size {
            let entry = pointer[index]
            let entryScope: EnvironmentScope =
                entry.type == UInt8(TELNET_ENVIRON_USERVAR) ? .userVariable : .variable
            if index == 0 { scope = entryScope }
            guard let namePointer = entry.`var` else { continue }
            let name = String(cString: namePointer)
            var value: String?
            if let valuePointer = entry.value {
                let decoded = String(cString: valuePointer)
                value = decoded.isEmpty ? nil : decoded
            }
            values.append(EnvironmentVariable(name: name, value: value, scope: entryScope))
        }
        emit(.environment(scope, values))
    }

    private func handleMSSP(_ event: telnet_event_t) {
        let mssp = event.mssp
        guard let pointer = mssp.values, mssp.size > 0 else {
            emit(.mssp([:]))
            return
        }
        var dictionary: [String: String] = [:]
        for index in 0..<mssp.size {
            let entry = pointer[index]
            guard let namePointer = entry.`var` else { continue }
            dictionary[String(cString: namePointer)] = entry.value.map { String(cString: $0) } ?? ""
        }
        emit(.mssp(dictionary))
    }

    private func handleZMP(_ event: telnet_event_t) {
        let zmp = event.zmp
        guard let argv = zmp.argv else {
            emit(.zmp([]))
            return
        }
        var arguments: [String] = []
        arguments.reserveCapacity(zmp.argc)
        for index in 0..<zmp.argc {
            if let argument = argv[index] {
                arguments.append(String(cString: argument))
            }
        }
        emit(.zmp(arguments))
    }

    private func handleWarning(_ event: telnet_event_t) {
        let error = event.error
        let message = error.msg.map { String(cString: $0) } ?? ""
        logger?.warning("libtelnet warning", metadata: ["message": "\(message)"])
        switch error.errcode {
        case TELNET_ECOMPRESS:
            emit(.warning(.compressionUnavailable))
        case TELNET_ENOMEM:
            pendingFatal = .protocolViolation(.outOfMemory)
            emit(.protocolError(.outOfMemory))
        default:
            emit(.warning(.unexpectedByte(0, context: message)))
        }
    }

    private func handleError(_ event: telnet_event_t) {
        let error = event.error
        let message = error.msg.map { String(cString: $0) } ?? ""
        let protocolError: TelnetProtocolError
        switch error.errcode {
        case TELNET_EBADVAL:
            protocolError = .stateMachineFailure(code: .badValue, message: message)
        case TELNET_ENOMEM:
            protocolError = .outOfMemory
        case TELNET_EOVERFLOW:
            protocolError = .stateMachineFailure(code: .overflow, message: message)
        case TELNET_EPROTOCOL:
            protocolError = .stateMachineFailure(code: .protocol, message: message)
        case TELNET_ECOMPRESS:
            protocolError = .stateMachineFailure(code: .compression, message: message)
        default:
            protocolError = .stateMachineFailure(code: .badValue, message: message)
        }
        pendingFatal = .protocolViolation(protocolError)
        emit(.protocolError(protocolError))
    }

    // MARK: Option table

    private static func optionTable(for options: TelnetOptions) -> [telnet_telopt_t] {
        var entries: [UInt8: (us: UInt8, him: UInt8)] = [:]
        for local in options.local {
            var entry = entries[local.option.rawValue] ?? (us: UInt8(TELNET_WONT), him: UInt8(TELNET_DONT))
            entry.us = local.enabledByDefault ? UInt8(TELNET_WILL) : UInt8(TELNET_WONT)
            entries[local.option.rawValue] = entry
        }
        for remote in options.remote {
            var entry = entries[remote.option.rawValue] ?? (us: UInt8(TELNET_WONT), him: UInt8(TELNET_DONT))
            entry.him = remote.requestOnConnect ? UInt8(TELNET_DO) : UInt8(TELNET_DONT)
            entries[remote.option.rawValue] = entry
        }
        let sorted = entries.sorted { $0.key < $1.key }
        var table = sorted.map { telnet_telopt_t(telopt: Int16($0.key), us: $0.value.us, him: $0.value.him) }
        table.append(telnet_telopt_t(telopt: -1, us: 0, him: 0))
        return table
    }

    /// Records negotiation bytes libtelnet emitted on its own during `telnet_recv`, which
    /// is the ground truth for an answer it sent without the caller asking.
    private func recordAutomaticReplies(in bytes: [UInt8]) {
        var index = 0
        while index + 2 < bytes.count {
            guard bytes[index] == TelnetWireCoding.iac else {
                index += 1
                continue
            }
            let code = bytes[index + 1]
            if code == TelnetWireCoding.iac {
                index += 2
                continue
            }
            if let action = TelnetNegotiation(wireCode: code) {
                ledger.recordAutomaticReply(action, option: TelnetOption(rawValue: bytes[index + 2]))
                index += 3
                continue
            }
            index += 1
        }
    }
}
