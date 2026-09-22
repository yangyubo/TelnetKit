import NIOCore

/// One accepted connection: the server half of the Telnet exchange.
///
/// The handler answers negotiation, answers TERMINAL-TYPE, records NAWS and NEW-ENVIRON, and
/// echoes session data back. Like the library's handler it is `Sendable` because its stored
/// properties are immutable; the parser, the option ledger, and the echo buffer live in a
/// `NIOLoopBoundBox`, which confines them to the EventLoop that owns the channel — the one
/// thread allowed to touch them.
final class EchoSessionHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = IOData

    /// Where the parser is inside an inbound sequence.
    private enum Parser: Sendable {
        case data
        case iac
        case negotiation
        case subnegotiationOption
        case subnegotiation(option: UInt8)
        case subnegotiationIAC(option: UInt8)
    }

    private struct State: Sendable {
        var parser = Parser.data
        var verb: UInt8 = 0
        var payload: [UInt8] = []
        var echo: [UInt8] = []
        var pendingCarriageReturn = false
        var peer = "peer"
        /// Options this side performs, options the peer performs, and the requests still
        /// awaiting an answer. The ledger keeps a repeated request from drawing a second
        /// answer, which is what a negotiation loop looks like on the wire.
        var wePerform: Set<UInt8> = []
        var peerPerforms: Set<UInt8> = []
        var ourOffersAwaitingAnswer: Set<UInt8> = []
        var ourRequestsAwaitingAnswer: Set<UInt8> = []
    }

    private let state: NIOLoopBoundBox<State>
    private let scenarios: [ServerArguments.Scenario]
    private let log: EchoLog

    init(scenarios: [ServerArguments.Scenario], log: EchoLog, eventLoop: EventLoop) {
        self.scenarios = scenarios
        self.log = log
        self.state = NIOLoopBoundBox.makeBoxSendingValue(Self.initialState(), eventLoop: eventLoop)
    }

    private static func initialState() -> State {
        var state = State()
        state.ourOffersAwaitingAnswer = [TelnetWire.echo, TelnetWire.suppressGoAhead]
        state.ourRequestsAwaitingAnswer = [TelnetWire.terminalType, TelnetWire.windowSize, TelnetWire.newEnviron]
        return state
    }

    // MARK: Lifecycle

    func channelActive(context: ChannelHandlerContext) {
        state.value.peer = PeerAddress.describe(context.channel.remoteAddress)
        log.line("\(state.value.peer) connected")

        var outbound: [UInt8] = []
        // Ask for the three capabilities this fixture demonstrates, and offer the two this side
        // performs.
        outbound += TelnetWire.negotiation(TelnetWire.doVerb, TelnetWire.terminalType)
        outbound += TelnetWire.negotiation(TelnetWire.doVerb, TelnetWire.windowSize)
        outbound += TelnetWire.negotiation(TelnetWire.doVerb, TelnetWire.newEnviron)
        outbound += TelnetWire.negotiation(TelnetWire.will, TelnetWire.echo)
        outbound += TelnetWire.negotiation(TelnetWire.will, TelnetWire.suppressGoAhead)
        for scenario in scenarios {
            let frame = Self.injection(scenario)
            log.line("\(state.value.peer) inject \(scenario.rawValue) \(TelnetWire.describe(frame))")
            outbound += frame
        }
        write(outbound, context: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        let inbound = Array(buffer.readableBytesView)
        var outbound: [UInt8] = []
        state.withValue { session in
            for byte in inbound {
                Self.step(byte, session: &session, outbound: &outbound, log: log)
            }
            Self.flushEcho(session: &session, outbound: &outbound)
        }
        write(outbound, context: context)
    }

    func channelInactive(context: ChannelHandlerContext) {
        log.line("\(state.value.peer) disconnected")
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        log.failure("\(state.value.peer) error: \(error)")
        context.close(promise: nil)
    }

    // MARK: Parsing

    private static func step(_ byte: UInt8, session: inout State, outbound: inout [UInt8], log: EchoLog) {
        switch session.parser {
        case .data:
            if byte == TelnetWire.iac {
                session.parser = .iac
            } else {
                appendData(byte, session: &session)
            }

        case .iac:
            switch byte {
            case TelnetWire.iac:
                appendData(TelnetWire.iac, session: &session)
                session.parser = .data
            case TelnetWire.will, TelnetWire.wont, TelnetWire.doVerb, TelnetWire.dont:
                session.verb = byte
                session.parser = .negotiation
            case TelnetWire.sb:
                session.parser = .subnegotiationOption
            default:
                // NOP, GA, AYT, DM, and the rest need no answer from this fixture.
                session.parser = .data
            }

        case .negotiation:
            let verb = session.verb
            session.parser = .data
            answer(verb: verb, option: byte, session: &session, outbound: &outbound, log: log)

        case .subnegotiationOption:
            session.payload.removeAll(keepingCapacity: true)
            session.parser = .subnegotiation(option: byte)

        case .subnegotiation(let option):
            if byte == TelnetWire.iac {
                session.parser = .subnegotiationIAC(option: option)
            } else {
                session.payload.append(byte)
            }

        case .subnegotiationIAC(let option):
            switch byte {
            case TelnetWire.se:
                session.parser = .data
                finishSubnegotiation(option: option, session: &session, outbound: &outbound, log: log)
            case TelnetWire.iac:
                session.payload.append(TelnetWire.iac)
                session.parser = .subnegotiation(option: option)
            default:
                // The peer escaped a byte that is neither IAC nor SE. Keep the byte rather than
                // truncating the frame, and stay inside the subnegotiation.
                session.payload.append(byte)
                session.parser = .subnegotiation(option: option)
            }
        }
    }

    /// Appends one application byte to the echo buffer, folding `CR NUL` and `CR LF` into one
    /// line ending.
    ///
    /// A client sends `CR NUL` for Enter, as `telnet(1)` does, and a terminal shows a line
    /// ending only when the server returns one, so the echo has to translate.
    private static func appendData(_ byte: UInt8, session: inout State) {
        if session.pendingCarriageReturn {
            session.pendingCarriageReturn = false
            if byte == 0x00 || byte == 0x0A {
                session.echo.append(0x0D)
                session.echo.append(0x0A)
                return
            }
            session.echo.append(0x0D)
        }
        if byte == 0x0D {
            session.pendingCarriageReturn = true
            return
        }
        session.echo.append(byte)
    }

    private static func flushEcho(session: inout State, outbound: inout [UInt8]) {
        guard !session.echo.isEmpty else { return }
        outbound += TelnetWire.escaping(session.echo)
        session.echo.removeAll(keepingCapacity: true)
    }

    // MARK: Negotiation

    /// Answers one `WILL`/`WONT`/`DO`/`DONT`, following RFC 1143 far enough that a request the
    /// peer already answered is not answered a second time.
    private static func answer(
        verb: UInt8,
        option: UInt8,
        session: inout State,
        outbound: inout [UInt8],
        log: EchoLog
    ) {
        switch verb {
        case TelnetWire.will:
            // The peer offers to perform the option. A `WILL` that answers this side's `DO`
            // needs no second `DO`; a fresh offer does.
            let answersOurRequest = session.ourRequestsAwaitingAnswer.remove(option) != nil
            guard performsRemotely(option) else {
                outbound += TelnetWire.negotiation(TelnetWire.dont, option)
                log.line("\(session.peer) WILL \(TelnetWire.name(of: option)) -> DONT")
                return
            }
            let isNew = session.peerPerforms.insert(option).inserted
            log.line("\(session.peer) WILL \(TelnetWire.name(of: option))")
            if isNew, !answersOurRequest {
                outbound += TelnetWire.negotiation(TelnetWire.doVerb, option)
            }
            if isNew { activate(option: option, outbound: &outbound) }

        case TelnetWire.doVerb:
            let answersOurOffer = session.ourOffersAwaitingAnswer.remove(option) != nil
            guard performsLocally(option) else {
                outbound += TelnetWire.negotiation(TelnetWire.wont, option)
                log.line("\(session.peer) DO \(TelnetWire.name(of: option)) -> WONT")
                return
            }
            let isNew = session.wePerform.insert(option).inserted
            log.line("\(session.peer) DO \(TelnetWire.name(of: option)) -> WILL")
            if isNew, !answersOurOffer {
                outbound += TelnetWire.negotiation(TelnetWire.will, option)
            }

        case TelnetWire.wont:
            session.ourRequestsAwaitingAnswer.remove(option)
            session.peerPerforms.remove(option)
            log.line("\(session.peer) WONT \(TelnetWire.name(of: option))")

        case TelnetWire.dont:
            session.ourOffersAwaitingAnswer.remove(option)
            let wasEnabled = session.wePerform.remove(option) != nil
            log.line("\(session.peer) DONT \(TelnetWire.name(of: option))")
            if wasEnabled { outbound += TelnetWire.negotiation(TelnetWire.wont, option) }

        default:
            break
        }
    }

    /// Starts the exchange that a just-enabled option needs from the peer. NAWS needs none: the
    /// peer reports its size as soon as the option is on, and again on every resize.
    private static func activate(option: UInt8, outbound: inout [UInt8]) {
        switch option {
        case TelnetWire.terminalType:
            outbound += TelnetWire.subnegotiation(option, [TelnetWire.terminalTypeSend])
        case TelnetWire.newEnviron:
            var payload: [UInt8] = [TelnetWire.environmentSend]
            for name in ["USER", "TERM"] {
                payload.append(TelnetWire.environmentVar)
                payload += Array(name.utf8)
            }
            outbound += TelnetWire.subnegotiation(option, payload)
        default:
            break
        }
    }

    /// Options this side performs when the peer asks with `DO`.
    private static func performsLocally(_ option: UInt8) -> Bool {
        option == TelnetWire.echo || option == TelnetWire.suppressGoAhead
    }

    /// Options this side wants the peer to perform, asked for with `DO`.
    private static func performsRemotely(_ option: UInt8) -> Bool {
        option == TelnetWire.terminalType
            || option == TelnetWire.windowSize
            || option == TelnetWire.newEnviron
            || option == TelnetWire.suppressGoAhead
    }

    // MARK: Subnegotiation

    private static func finishSubnegotiation(
        option: UInt8,
        session: inout State,
        outbound: inout [UInt8],
        log: EchoLog
    ) {
        let payload = session.payload
        session.payload.removeAll(keepingCapacity: true)

        switch option {
        case TelnetWire.terminalType:
            guard let command = payload.first else {
                log.line("\(session.peer) TTYPE empty subnegotiation")
                return
            }
            if command == TelnetWire.terminalTypeIs {
                log.line("\(session.peer) TTYPE \(TelnetWire.printable(Array(payload.dropFirst())))")
            } else if command == TelnetWire.terminalTypeSend {
                outbound += TelnetWire.subnegotiation(option, [TelnetWire.terminalTypeIs] + Array("XTERM-256COLOR".utf8))
            } else {
                log.line("\(session.peer) TTYPE unknown subcommand \(command)")
            }

        case TelnetWire.windowSize:
            guard payload.count == 4 else {
                log.line("\(session.peer) NAWS malformed (\(payload.count) bytes)")
                return
            }
            let columns = Int(payload[0]) << 8 | Int(payload[1])
            let rows = Int(payload[2]) << 8 | Int(payload[3])
            log.line("\(session.peer) NAWS \(columns)x\(rows)")

        case TelnetWire.newEnviron:
            let entries = TelnetWire.environmentEntries(from: payload)
            if entries.isEmpty {
                log.line("\(session.peer) NEW-ENVIRON \(payload.count) bytes")
            } else {
                let rendered = entries.map { "\($0.name)=\($0.value)" }.joined(separator: " ")
                log.line("\(session.peer) NEW-ENVIRON \(rendered)")
            }

        default:
            log.line("\(session.peer) subnegotiation \(TelnetWire.name(of: option)) \(payload.count) bytes")
        }
    }

    // MARK: Injection

    /// One malformed exchange the server sends after its initial negotiation.
    private static func injection(_ scenario: ServerArguments.Scenario) -> [UInt8] {
        switch scenario {
        case .negotiation:
            // WILL for an option the client never declared: libtelnet refuses it with DONT on
            // the wire and raises no negotiation event, because its option table has no entry
            // for the code.
            TelnetWire.negotiation(TelnetWire.will, 200)
        case .subnegotiation:
            // An unknown option's subnegotiation carrying an escaped 0xFF, so the caller's
            // unescaping is exercised rather than assumed.
            TelnetWire.subnegotiation(200, [0x01, TelnetWire.iac, 0x02])
        case .warning:
            // NEW-ENVIRON with an invalid command byte: libtelnet reports "telopt 39 subneg has
            // invalid command" as a warning and stays connected.
            TelnetWire.subnegotiation(TelnetWire.newEnviron, [0x7F])
        case .oversized:
            // Past the client's 8 KiB inbound subnegotiation limit, which is fatal.
            TelnetWire.subnegotiation(200, Array(repeating: 0x78, count: 9_000))
        }
    }

    // MARK: Output

    private func write(_ bytes: [UInt8], context: ChannelHandlerContext) {
        guard !bytes.isEmpty else { return }
        var buffer = context.channel.allocator.buffer(capacity: bytes.count)
        buffer.writeBytes(bytes)
        context.writeAndFlush(wrapOutboundOut(IOData.byteBuffer(buffer)), promise: nil)
    }
}
