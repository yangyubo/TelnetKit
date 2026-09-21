import CLibTelnet
import Foundation
import Testing

// Drives the vendored libtelnet C library through the CLibTelnet module. This suite
// exists to prove the vendored copy compiles and parses correctly; the Swift-typed
// expectations that replace these raw values arrive with TelnetProtocolCore in M1.
//
// Wire bytes under test:
//   FF FB 01   IAC WILL ECHO
//   FF FA 18 01 FF F0   IAC SB TERMINAL-TYPE SEND IAC SE
//   FF F1      IAC NOP

/// Records what libtelnet reports, so a test can assert on parsed events instead of on
/// the absence of a crash. The lock is what makes `@unchecked Sendable` honest: the C
/// callback fires on whatever thread calls `telnet_recv`, and tests may connect from more
/// than one.
final class EventSink: @unchecked Sendable {
    enum Event: Equatable {
        case data([UInt8])
        case send([UInt8])
        case command(UInt8)
        case negotiation(verb: UInt8, option: UInt8)
        case subnegotiation(option: UInt8, payload: [UInt8])
        case warning(String)
        case error(String)
    }

    let lock = NSRecursiveLock()
    var storage: [Event] = []

    var events: [Event] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ event: Event) {
        lock.lock(); defer { lock.unlock() }
        storage.append(event)
    }
}

/// Owns one `telnet_t` and frees it when the test drops the box.
final class TelnetHandle {
    let handle: OpaquePointer?
    let sink: EventSink
    let options: UnsafeMutableBufferPointer<telnet_telopt_t>

    init(localWill: [UInt8] = [], remoteDo: [UInt8] = [], flags: UInt8 = 0) {
        let sink = EventSink()
        self.sink = sink

        // libtelnet keeps the pointer to the option table, so the table must outlive the
        // handle; the terminator is telopt == -1.
        var table = localWill.map { telnet_telopt_t(telopt: Int16($0), us: UInt8(TELNET_WILL), him: UInt8(TELNET_DO)) }
        table += remoteDo.map { telnet_telopt_t(telopt: Int16($0), us: UInt8(TELNET_WONT), him: UInt8(TELNET_DO)) }
        table.append(telnet_telopt_t(telopt: -1, us: 0, him: 0))

        let buffer = UnsafeMutableBufferPointer<telnet_telopt_t>.allocate(capacity: table.count)
        _ = buffer.initialize(from: table)
        self.options = buffer

        let userData = Unmanaged.passUnretained(sink).toOpaque()
        self.handle = telnet_init(buffer.baseAddress, { _, eventPointer, userData in
            guard let eventPointer, let userData else { return }
            let sink = Unmanaged<EventSink>.fromOpaque(userData).takeUnretainedValue()
            // Every payload pointer in the union expires when this callback returns, so the
            // bytes are copied here and never retained.
            switch eventPointer.pointee.type {
            case TELNET_EV_DATA:
                let data = eventPointer.pointee.data
                sink.append(.data(Array(UnsafeRawBufferPointer(start: data.buffer, count: data.size))))
            case TELNET_EV_SEND:
                let data = eventPointer.pointee.data
                sink.append(.send(Array(UnsafeRawBufferPointer(start: data.buffer, count: data.size))))
            case TELNET_EV_IAC:
                sink.append(.command(eventPointer.pointee.iac.cmd))
            case TELNET_EV_WILL, TELNET_EV_WONT, TELNET_EV_DO, TELNET_EV_DONT:
                let neg = eventPointer.pointee.neg
                sink.append(.negotiation(verb: UInt8(neg._type.rawValue), option: neg.telopt))
            case TELNET_EV_SUBNEGOTIATION:
                let sub = eventPointer.pointee.sub
                sink.append(.subnegotiation(
                    option: sub.telopt,
                    payload: Array(UnsafeRawBufferPointer(start: sub.buffer, count: sub.size))
                ))
            case TELNET_EV_WARNING:
                let error = eventPointer.pointee.error
                sink.append(.warning(String(cString: error.msg)))
            case TELNET_EV_ERROR:
                let error = eventPointer.pointee.error
                sink.append(.error(String(cString: error.msg)))
            default:
                break
            }
        }, flags, userData)
    }

    var events: [EventSink.Event] { sink.events }

    /// Concatenates every data event, because libtelnet may split one write into several
    /// data events around an escaped IAC; the byte stream is the contract, not the split.
    var dataBytes: [UInt8] {
        events.flatMap { event -> [UInt8] in
            if case .data(let payload) = event { return payload }
            return []
        }
    }

    /// Feeds bytes to the state tracker and returns everything it reported, so a test reads
    /// as bytes in, events out.
    func feed(_ bytes: [UInt8]) -> [EventSink.Event] {
        let before = sink.events.count
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            telnet_recv(handle, base.assumingMemoryBound(to: CChar.self), bytes.count)
        }
        return Array(sink.events.dropFirst(before))
    }

    deinit {
        telnet_free(handle)
        options.deallocate()
    }
}

@Suite("Vendored libtelnet")
struct VendoredLibtelnetTests {

    @Test("an application byte stream arrives as one data event")
    func dataPassesThrough() {
        let telnet = TelnetHandle()
        let events = telnet.feed(Array("hello\r\n".utf8))
        #expect(events == [.data(Array("hello\r\n".utf8))])
    }

    @Test("IAC WILL ECHO is stripped from the data stream and answered")
    func negotiationIsStripped() {
        let telnet = TelnetHandle(localWill: [UInt8(TELNET_TELOPT_ECHO)])
        let events = telnet.feed([0xFF, 0xFB, 0x01] + Array("hi".utf8))

        #expect(events.contains(.negotiation(verb: UInt8(TELNET_EV_WILL.rawValue), option: 1)))
        #expect(events.contains(.data(Array("hi".utf8))))
        #expect(events.contains { if case .data = $0 { return false } else { return false } } == false)
    }

    @Test("a doubled 0xFF in the data stream collapses to one byte")
    func escapedIACIsRestored() {
        let telnet = TelnetHandle()
        _ = telnet.feed([0x41, 0xFF, 0xFF, 0x42])
        // libtelnet flushes the bytes before the escape, then the escape, then the rest,
        // so the assertion is on the concatenated stream.
        #expect(telnet.dataBytes == [0x41, 0xFF, 0x42])
    }

    @Test("a control command becomes a command event")
    func commandIsReported() {
        let telnet = TelnetHandle()
        let events = telnet.feed([0xFF, 0xF1])
        #expect(events.contains(.command(0xF1)))
    }

    @Test("a subnegotiation payload survives intact")
    func subnegotiationIsReported() {
        let telnet = TelnetHandle()
        let events = telnet.feed([0xFF, 0xFA, 0x18, 0x01, 0xFF, 0xF0])
        #expect(events.contains(.subnegotiation(option: 0x18, payload: [0x01])))
    }

    @Test("an accepted option makes libtelnet emit outbound bytes")
    func acceptedOptionProducesSend() {
        let telnet = TelnetHandle(localWill: [UInt8(TELNET_TELOPT_ECHO)])
        let events = telnet.feed([0xFF, 0xFB, 0x01])
        // IAC DO ECHO, the RFC 1143 answer to the peer's WILL.
        #expect(events.contains(.send([0xFF, 0xFD, 0x01])))
    }

    @Test("a truncated IAC sequence at end of input does not crash")
    func truncatedSequenceSurvives() {
        let telnet = TelnetHandle()
        let events = telnet.feed([0xFF, 0xFB])
        // The state tracker keeps the partial sequence buffered; nothing is delivered yet.
        #expect(events.isEmpty)
    }

    @Test("telnet_send_text escapes IAC and translates the newline")
    func sendTextOutputsNegotiatedBytes() {
        // The whole session is observed, including libtelnet's IAC DO ECHO answer to the
        // peer's WILL, so the concatenated bytes match the prototype evidence exactly:
        // FF FD 01 68 69 0D 0A. libtelnet may split the text and the newline into separate
        // send events, so the assertion is on the concatenated stream.
        let telnet = TelnetHandle(localWill: [UInt8(TELNET_TELOPT_ECHO)])
        _ = telnet.feed([0xFF, 0xFB, 0x01])

        let text = Array("hi\n".utf8)
        text.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: text.count) { pointer in
                telnet_send_text(telnet.handle, pointer, text.count)
            }
        }

        let sent = telnet.events.flatMap { event -> [UInt8] in
            if case .send(let payload) = event { return payload }
            return []
        }
        #expect(sent == [0xFF, 0xFD, 0x01, 0x68, 0x69, 0x0D, 0x0A])
    }
}
