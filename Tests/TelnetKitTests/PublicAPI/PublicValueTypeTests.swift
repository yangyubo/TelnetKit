import NIOCore
import Testing

import TelnetKit

@Suite("Public value types")
struct PublicValueTypeTests {
    @Test("every modeled option keeps its RFC code and renders a name")
    func optionCodes() {
        #expect(TelnetOption.binary.rawValue == 0)
        #expect(TelnetOption.echo.rawValue == 1)
        #expect(TelnetOption.suppressGoAhead.rawValue == 3)
        #expect(TelnetOption.status.rawValue == 5)
        #expect(TelnetOption.timingMark.rawValue == 6)
        #expect(TelnetOption.terminalType.rawValue == 24)
        #expect(TelnetOption.endOfRecord.rawValue == 25)
        #expect(TelnetOption.windowSize.rawValue == 31)
        #expect(TelnetOption.terminalSpeed.rawValue == 32)
        #expect(TelnetOption.remoteFlowControl.rawValue == 33)
        #expect(TelnetOption.lineMode.rawValue == 34)
        #expect(TelnetOption.environment.rawValue == 36)
        #expect(TelnetOption.newEnvironment.rawValue == 39)
        #expect(TelnetOption.mssp.rawValue == 70)
        #expect(TelnetOption.compress.rawValue == 85)
        #expect(TelnetOption.compress2.rawValue == 86)
        #expect(TelnetOption.zmp.rawValue == 93)
        #expect(TelnetOption.extendedOptionsList.rawValue == 255)
        #expect(TelnetOption.allCases.count == 18)
        #expect(TelnetOption.echo.displayName == "echo")
        #expect(TelnetOption(rawValue: 200).displayName == "option(200)")
        #expect(TelnetOption(rawValue: 200) == TelnetOption(rawValue: 200))
    }

    @Test("every command keeps its wire code")
    func commandCodes() {
        #expect(TelnetCommand.endOfFile.rawValue == 236)
        #expect(TelnetCommand.suspend.rawValue == 237)
        #expect(TelnetCommand.abort.rawValue == 238)
        #expect(TelnetCommand.endOfRecord.rawValue == 239)
        #expect(TelnetCommand.subnegotiationEnd.rawValue == 240)
        #expect(TelnetCommand.noOperation.rawValue == 241)
        #expect(TelnetCommand.dataMark.rawValue == 242)
        #expect(TelnetCommand.brk.rawValue == 243)
        #expect(TelnetCommand.interruptProcess.rawValue == 244)
        #expect(TelnetCommand.abortOutput.rawValue == 245)
        #expect(TelnetCommand.areYouThere.rawValue == 246)
        #expect(TelnetCommand.eraseCharacter.rawValue == 247)
        #expect(TelnetCommand.eraseLine.rawValue == 248)
        #expect(TelnetCommand.goAhead.rawValue == 249)
        #expect(TelnetCommand.subnegotiation.rawValue == 250)
        #expect(TelnetCommand.will.rawValue == 251)
        #expect(TelnetCommand.wont.rawValue == 252)
        #expect(TelnetCommand.do_.rawValue == 253)
        #expect(TelnetCommand.dont.rawValue == 254)
        #expect(TelnetCommand.allCases.count == 19)
    }

    @Test("the four negotiation verbs are distinct")
    func negotiationVerbs() {
        #expect(TelnetNegotiation.allCases.count == 4)
        #expect(Set(TelnetNegotiation.allCases) == [.will, .wont, .do, .dont])
    }

    @Test("standardClient offers BINARY, SGA, and ECHO and requests SGA")
    func standardClient() {
        let options = TelnetOptions.standardClient
        #expect(options.local.map(\.option) == [.binary, .suppressGoAhead, .echo])
        #expect(options.local.allSatisfy { $0.enabledByDefault })
        #expect(options.remote.map(\.option) == [.suppressGoAhead])
        #expect(options.remote.allSatisfy { $0.requestOnConnect })
        #expect(options.isValid)
    }

    @Test("serverRequesting builds the requested peer set")
    func serverRequesting() {
        let options = TelnetOptions.serverRequesting([.terminalType, .windowSize, .newEnvironment])
        #expect(options.remote.map(\.option) == [.terminalType, .windowSize, .newEnvironment])
        #expect(options.isValid)
    }

    @Test("binary together with lineMode is invalid")
    func invalidOptionCombination() {
        let options = TelnetOptions(local: [.init(.binary), .init(.lineMode)])
        #expect(!options.isValid)
    }

    @Test("configuration defaults match the documented bounds")
    func configurationDefaults() {
        let configuration = TelnetConfiguration()
        #expect(configuration.connectTimeout == .seconds(10))
        #expect(configuration.idleTimeout == nil)
        #expect(configuration.inboundBufferLimit == 65_536)
        #expect(configuration.subnegotiationLimit == 8_192)
        #expect(configuration.waitForConnectivity)
        #expect(configuration.logger == nil)
        if case .bounded(let count) = configuration.eventBufferPolicy {
            #expect(count == 1024)
        } else {
            Issue.record("default event buffer policy is not .bounded")
        }
        if case .nvt = configuration.newlinePolicy {} else {
            Issue.record("default newline policy is not .nvt")
        }
    }

    @Test("configuration keeps every field it is given")
    func configurationFields() {
        let configuration = TelnetConfiguration(
            connectTimeout: .seconds(3),
            idleTimeout: .seconds(30),
            inboundBufferLimit: 1024,
            subnegotiationLimit: 256,
            eventBufferPolicy: .dropOldest(16),
            newlinePolicy: .raw,
            waitForConnectivity: false
        )
        #expect(configuration.connectTimeout == .seconds(3))
        #expect(configuration.idleTimeout == .seconds(30))
        #expect(configuration.inboundBufferLimit == 1024)
        #expect(configuration.subnegotiationLimit == 256)
        #expect(configuration.waitForConnectivity == false)
        if case .dropOldest(let count) = configuration.eventBufferPolicy {
            #expect(count == 16)
        } else {
            Issue.record("event buffer policy did not keep .dropOldest")
        }
        if case .raw = configuration.newlinePolicy {} else {
            Issue.record("newline policy did not keep .raw")
        }
    }

    @Test("every event buffer policy and line ending case exists")
    func policyAndLineEndingCases() {
        let policies: [TelnetEventBufferPolicy] = [.bounded(1), .unbounded, .dropOldest(1)]
        #expect(policies.count == 3)
        #expect(TelnetLineEnding.allCases == [.crlf, .crNul, .lf, .none])
    }

    @Test("error values compare by their payload")
    func errorValues() {
        #expect(TelnetError.notConnected == TelnetError.notConnected)
        #expect(TelnetError.alreadyClosed == TelnetError.alreadyClosed)
        #expect(TelnetError.cancelled == TelnetError.cancelled)
        #expect(TelnetError.invalidHost("x") != TelnetError.invalidHost("y"))
        #expect(TelnetError.connectionRefused(host: "h", port: 1) == TelnetError.connectionRefused(host: "h", port: 1))
        #expect(TelnetError.connectTimeout(.seconds(1)) == TelnetError.connectTimeout(.seconds(1)))
        #expect(TelnetError.bufferOverflow(limit: 4) == TelnetError.bufferOverflow(limit: 4))
        #expect(
            TelnetError.subnegotiationTooLarge(option: .zmp, limit: 8)
                == TelnetError.subnegotiationTooLarge(option: .zmp, limit: 8)
        )
        #expect(TelnetError.unsupportedFeature("zlib") == TelnetError.unsupportedFeature("zlib"))
        #expect(TelnetError.invalidConfiguration("x") == TelnetError.invalidConfiguration("x"))
        #expect(
            TelnetError.protocolViolation(.outOfMemory) == TelnetError.protocolViolation(.outOfMemory)
        )
    }

    @Test("transport failures keep their kind, message, and retryability")
    func transportFailure() {
        let failure = TelnetTransportFailure(kind: .posix(code: 61), message: "refused", isRetryable: true)
        #expect(failure.kind == .posix(code: 61))
        #expect(failure.message == "refused")
        #expect(failure.isRetryable)
        #expect(TelnetTransportFailure.Kind.dns == .dns)
        #expect(TelnetTransportFailure.Kind.tls == .tls)
        #expect(TelnetTransportFailure.Kind.channelClosed == .channelClosed)
        #expect(TelnetTransportFailure.Kind.writeTimeout == .writeTimeout)
        #expect(TelnetTransportFailure.Kind.other == .other)
    }

    @Test("warnings, protocol errors, and error codes are comparable")
    func errorTaxonomy() {
        #expect(TelnetWarning.truncatedSequence([0xFF]) == TelnetWarning.truncatedSequence([0xFF]))
        #expect(TelnetWarning.unexpectedByte(1, context: "c") == TelnetWarning.unexpectedByte(1, context: "c"))
        #expect(TelnetWarning.subnegotiationTruncated(option: .zmp) == TelnetWarning.subnegotiationTruncated(option: .zmp))
        #expect(TelnetWarning.eventBufferOverflowDropped(count: 2) == TelnetWarning.eventBufferOverflowDropped(count: 2))
        #expect(TelnetWarning.compressionUnavailable == TelnetWarning.compressionUnavailable)

        #expect(
            TelnetProtocolError.stateMachineFailure(code: .protocol, message: "m")
                == TelnetProtocolError.stateMachineFailure(code: .protocol, message: "m")
        )
        #expect(TelnetProtocolError.invalidSubnegotiation(option: .zmp) == TelnetProtocolError.invalidSubnegotiation(option: .zmp))
        #expect(TelnetProtocolError.outOfMemory == TelnetProtocolError.outOfMemory)
        #expect(TelnetErrorCode.allCases == [.badValue, .outOfMemory, .overflow, .protocol, .compression])
    }

    @Test("environment values carry name, optional value, and scope")
    func environmentValues() {
        let variable = EnvironmentVariable(name: "TERM", value: "xterm", scope: .variable)
        #expect(variable.name == "TERM")
        #expect(variable.value == "xterm")
        #expect(variable.scope == .variable)
        #expect(EnvironmentScope.userVariable != EnvironmentScope.variable)
        let withoutValue = EnvironmentVariable(name: "USER")
        #expect(withoutValue.value == nil)
        #expect(withoutValue.scope == .variable)
    }

    @Test("bytes and text are exposed only for a data event")
    func eventAccessors() {
        let data = TelnetEvent.data(ByteBuffer(bytes: Array("hello".utf8)))
        #expect(data.bytes == Array("hello".utf8))
        #expect(data.text == "hello")

        let invalidUTF8 = TelnetEvent.data(ByteBuffer(bytes: [0xFF, 0xFE]))
        #expect(invalidUTF8.bytes == [0xFF, 0xFE])
        #expect(invalidUTF8.text != nil)

        let nonData: [TelnetEvent] = [
            .negotiation(.will, option: .echo, remote: true),
            .subnegotiation(option: .zmp, payload: []),
            .command(.noOperation),
            .terminalTypeRequested,
            .terminalType("xterm"),
            .environmentRequested(.variable),
            .environment(.variable, []),
            .localEchoChanged(enabled: true),
            .mssp([:]),
            .zmp([]),
            .compressionEnabled(false),
            .pathChanged(viable: true, expensive: false, constrained: false),
            .betterPathAvailable,
            .betterPathUnavailable,
            .viabilityChanged(isViable: true),
            .waitingForConnectivity(error: nil, description: "d"),
            .warning(.compressionUnavailable),
            .protocolError(.outOfMemory),
        ]
        for event in nonData {
            #expect(event.bytes == nil)
            #expect(event.text == nil)
        }
    }
}
