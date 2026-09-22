import Foundation
import Observation
import TelnetKit

/// The demo's single source of truth.
///
/// Every public interface of `TelnetKit` is reached from here exactly as a caller would:
/// `TelnetConnection.connect`, the `events` stream, the sending and negotiation methods, the
/// capability helpers, `optionStatus(_:)`, and `close()`. The model is `@MainActor`, so the
/// views read it without synchronization while the connection actor does the socket work.
///
/// Every `do`/`catch` over a typed-throwing call sits in an ordinary method body. A closure
/// literal does not infer a typed thrown error, and a `do`/`catch` inside a `Task` closure
/// widens the caught error to `any Error`, so neither form can carry the `throws(TelnetError)`
/// contract into this layer.
@MainActor
@Observable
final class DemoModel {
    // MARK: Form
    /// The connection form, including every `TelnetConfiguration` parameter and both
    /// `TelnetOptions` lists.
    var settings = DemoConnectionSettings()

    // MARK: Connection state
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var remoteAddress: String?
    private(set) var localAddress: String?
    private(set) var statusText = "Not connected"
    private(set) var optionStatuses: [TelnetOption: TelnetOptionStatus] = [:]
    private(set) var lastError: TelnetError?
    private(set) var lastErrorText: String?
    private(set) var terminalTypeRequestPending = false
    private(set) var windowSizeArmed = false
    private(set) var lastReportedSize: String?
    private(set) var localEchoEnabled = true

    // MARK: Terminal panel
    var inputText = ""
    var lineEnding = TelnetLineEnding.crlf
    var hexBytes = "68 65 6C 6C 6F"
    var terminalType = "xterm-256color"
    var environmentRows: [DemoEnvironmentRow] = DemoEnvironmentRow.defaults
    var environmentScope = EnvironmentScope.variable
    var manualColumns = 80
    var manualRows = 24
    private(set) var output = ""

    // MARK: Protocol operations
    var negotiationAction = TelnetNegotiation.will
    var negotiationOption = TelnetOption.echo
    var requestOptionSelection = TelnetOption.terminalType
    var subnegotiationOption = TelnetOption.newEnvironment
    var subnegotiationHex = "01 00"
    var selectedCommand = TelnetCommand.areYouThere
    /// A decimal option code that overrides the option pickers while it is set, so the manual
    /// operations can reach a code the library models with no constant (`init(rawValue:)`).
    var customOptionCode = ""

    // MARK: Automatic answers
    /// Answer a `TERMINAL-TYPE SEND` at once, the way `telnet(1)` does.
    ///
    /// A telnetd commonly withholds its login prompt until the terminal type is answered, so
    /// a caller that leaves the answer to a button sees no server output at all.
    var autoAnswerTerminalType = true
    /// Answer a `NEW-ENVIRON SEND` with the rows above.
    var autoAnswerEnvironment = true

    // MARK: Records
    private(set) var eventRecords: [DemoEventRecord] = []
    private(set) var logRecords: [DemoLogRecord] = []

    private var connection: TelnetConnection?
    private var connectTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var eventSequence = 0
    private var measuredSize: (columns: Int, rows: Int)?

    /// Upper bounds on what the panels keep, so a chatty peer cannot grow the UI without end.
    private let maximumRecords = 2_000
    private let maximumOutputCharacters = 200_000

    // MARK: Lifecycle

    /// Opens the connection described by the form.
    func connect() {
        beginConnect(host: settings.host, port: settings.port, settings: settings)
    }

    /// Cancels an in-flight connect attempt. The awaiting `connect` throws `.cancelled`.
    func cancelConnectAttempt() {
        guard isConnecting else { return }
        connectTask?.cancel()
    }

    /// Closes the connection and stops the event pump. `close()` is idempotent, so calling
    /// this twice is safe.
    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        eventTask?.cancel()
        eventTask = nil
        terminalTypeRequestPending = false
        windowSizeArmed = false
        isConnecting = false

        guard let connection else {
            isConnected = false
            statusText = "Not connected"
            return
        }
        self.connection = nil
        isConnected = false
        statusText = "Closed by the app"
        appendRecord(category: .lifecycle, name: "close", detail: "close() called by the app")
        Task { await connection.close() }
    }

    private func beginConnect(host: String, port: Int, settings: DemoConnectionSettings) {
        guard !isConnecting else { return }
        lastError = nil
        lastErrorText = nil
        isConnecting = true
        statusText = "Connecting to \(host):\(port)…"

        let options = settings.telnetOptions
        let configuration = settings.configuration { [weak self] record in
            // The panel is the in-app view; the console keeps the same records visible in
            // Xcode, and the library never logs payload bytes at any level.
            let metadata = record.metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            print("[telnetkit] \(record.level.rawValue) \(record.message) \(metadata)")
            Task { @MainActor in self?.append(logRecord: record) }
        }

        connectTask = Task { [weak self] in
            await self?.openConnection(host: host, port: port, options: options, configuration: configuration)
        }
    }

    private func openConnection(
        host: String,
        port: Int,
        options: TelnetOptions,
        configuration: TelnetConfiguration
    ) async {
        do {
            let connection = try await TelnetConnection.connect(
                host: host,
                port: port,
                options: options,
                configuration: configuration
            )
            await didConnect(connection, host: host, port: port)
        } catch {
            didFailConnect(error, host: host, port: port)
        }
    }

    private func didConnect(_ connection: TelnetConnection, host: String, port: Int) async {
        self.connection = connection
        connectTask = nil
        isConnecting = false
        isConnected = true
        remoteAddress = await connection.remoteAddress
        localAddress = await connection.localAddress
        statusText = "Connected to \(remoteAddress ?? "\(host):\(port)")"
        appendRecord(
            category: .lifecycle,
            name: "connect",
            detail: "connected to \(remoteAddress ?? "\(host):\(port)") from \(localAddress ?? "unknown")"
        )
        await refreshOptionStatuses()
        startEventPump(connection)
    }

    private func didFailConnect(_ error: TelnetError, host: String, port: Int) {
        connection = nil
        connectTask = nil
        isConnecting = false
        isConnected = false
        statusText = "Not connected"
        record(error, context: "connect(host: \"\(host)\", port: \(port))")
    }

    // MARK: Event stream

    private func startEventPump(_ connection: TelnetConnection) {
        eventTask = Task { [weak self] in
            for await event in connection.events {
                await self?.handle(event, from: connection)
            }
            await self?.streamFinished(connection)
        }
    }

    private func handle(_ event: TelnetEvent, from connection: TelnetConnection) async {
        appendRecord(category: event.demoCategory, name: event.demoName, detail: event.demoDetail)
        switch event {
        case .data:
            appendOutput(event.text ?? "")
        case .negotiation(let action, let option, let remote):
            if option == .windowSize {
                // The peer asked this end to report NAWS, or withdrew it. RFC 1073 sends the
                // size only while the option is enabled in this direction.
                if remote, action == .do {
                    windowSizeArmed = true
                    sendMeasuredWindowSize()
                } else if action == .dont {
                    windowSizeArmed = false
                }
            }
            await refreshOptionStatuses()
        case .localEchoChanged(let enabled):
            localEchoEnabled = enabled
        case .terminalTypeRequested:
            terminalTypeRequestPending = true
            if autoAnswerTerminalType {
                // The peer is waiting for the terminal type before it says anything; answer
                // now, and leave the manual button for a repeated SEND.
                perform(.replyTerminalType(terminalType))
            }
        case .environmentRequested(let scope):
            if autoAnswerEnvironment {
                let values = environmentRows
                    .filter { !$0.name.isEmpty }
                    .map { EnvironmentVariable(name: $0.name, value: $0.value.isEmpty ? nil : $0.value, scope: scope) }
                if !values.isEmpty {
                    perform(.sendEnvironment(values, scope))
                }
            }
        case .terminalType, .environment, .subnegotiation, .command,
             .mssp, .zmp, .compressionEnabled, .pathChanged, .betterPathAvailable,
             .betterPathUnavailable, .viabilityChanged, .waitingForConnectivity, .warning,
             .protocolError:
            break
        }
    }

    private func streamFinished(_ connection: TelnetConnection) async {
        guard self.connection === connection else { return }
        self.connection = nil
        eventTask = nil
        isConnected = false
        isConnecting = false
        terminalTypeRequestPending = false
        windowSizeArmed = false
        statusText = "The connection closed"
        appendRecord(category: .lifecycle, name: "events", detail: "the event stream finished")
    }

    /// Refreshes `optionStatuses` for every modeled option.
    func refreshOptionStatuses() async {
        guard let connection else {
            optionStatuses = [:]
            return
        }
        var statuses: [TelnetOption: TelnetOptionStatus] = [:]
        for option in TelnetOption.allCases {
            statuses[option] = await connection.optionStatus(option)
        }
        optionStatuses = statuses
    }

    // MARK: Sending

    /// `send(text:lineEnding:)` with the selected line ending.
    ///
    /// `send(text:lineEnding:)` translates the line endings a string already carries; it does
    /// not add one, so the demo appends the newline that ends the line the user typed. Without
    /// it a telnetd never sees a complete line: it echoes the name and waits for the terminator
    /// instead of prompting for the password.
    func sendCurrentLine() {
        let text = inputText
        guard !text.isEmpty else { return }
        let ending = lineEnding
        inputText = ""
        if localEchoEnabled {
            appendOutput(text + "\n")
        }
        perform(.sendText(text + "\n", lineEnding: ending))
    }

    /// `send(text:)`, which always uses `TelnetLineEnding.crlf`.
    func sendWithDefaultLineEnding() {
        let text = inputText
        guard !text.isEmpty else { return }
        inputText = ""
        if localEchoEnabled {
            appendOutput(text + "\n")
        }
        perform(.sendTextDefault(text + "\n"))
    }

    /// `send(_:)` with the bytes parsed from the hexadecimal field.
    func sendHexBytes() {
        guard let bytes = DemoHex.bytes(from: hexBytes) else {
            record(.invalidConfiguration("not a hexadecimal byte list: \(hexBytes)"), context: "send(_:)")
            return
        }
        perform(.sendBytes(bytes))
    }

    /// `sendRaw(_:)` with the bytes parsed from the hexadecimal field.
    func sendHexBytesRaw() {
        guard let bytes = DemoHex.bytes(from: hexBytes) else {
            record(.invalidConfiguration("not a hexadecimal byte list: \(hexBytes)"), context: "sendRaw(_:)")
            return
        }
        perform(.sendRawBytes(bytes))
    }

    /// `send(command:)` with the selected command.
    func sendSelectedCommand() {
        perform(.sendCommand(selectedCommand))
    }

    // MARK: Negotiation and capabilities

    /// `negotiate(_:option:)`; the result reports whether RFC 1143 state suppressed it.
    func negotiateSelection() {
        guard let connection else {
            record(.notConnected, context: "negotiate(_:option:)")
            return
        }
        let action = negotiationAction
        let option = effectiveNegotiationOption
        Task { [weak self] in
            await self?.runNegotiate(action, option: option, connection: connection)
        }
    }

    private func runNegotiate(
        _ action: TelnetNegotiation,
        option: TelnetOption,
        connection: TelnetConnection
    ) async {
        do {
            let sent = try await connection.negotiate(action, option: option)
            appendRecord(
                category: .lifecycle,
                name: "negotiate(_:option:)",
                detail: sent
                    ? "sent \(action.demoName) \(option.displayName)"
                    : "suppressed by RFC 1143 state: \(action.demoName) \(option.displayName)"
            )
        } catch {
            record(error, context: "negotiate(_:option:)")
        }
        await refreshOptionStatuses()
    }

    /// `requestOption(_:)` with the selected option.
    func requestSelectedOption() {
        perform(.requestOption(effectiveRequestOption))
    }

    /// `subnegotiate(option:payload:)` with the bytes parsed from the hexadecimal field.
    func sendSubnegotiation() {
        guard let payload = DemoHex.bytes(from: subnegotiationHex) else {
            record(
                .invalidConfiguration("not a hexadecimal byte list: \(subnegotiationHex)"),
                context: "subnegotiate(option:payload:)"
            )
            return
        }
        perform(.subnegotiate(effectiveSubnegotiationOption, payload))
    }

    /// The option the manual operations act on: an unmodeled code when one is typed, and the
    /// picker selection otherwise.
    private var effectiveNegotiationOption: TelnetOption {
        unmodeledOption ?? negotiationOption
    }

    private var effectiveRequestOption: TelnetOption {
        unmodeledOption ?? requestOptionSelection
    }

    private var effectiveSubnegotiationOption: TelnetOption {
        unmodeledOption ?? subnegotiationOption
    }

    /// The option built from `customOptionCode` through `TelnetOption(rawValue:)`, or nil when
    /// the field is empty or not a byte.
    private var unmodeledOption: TelnetOption? {
        guard !customOptionCode.isEmpty, let code = UInt8(customOptionCode) else { return nil }
        return TelnetOption(rawValue: code)
    }

    /// `replyTerminalType(_:)`; valid only while a `.terminalTypeRequested` event is pending.
    func replyTerminalType() {
        perform(.replyTerminalType(terminalType))
    }

    /// `sendEnvironment(_:scope:)` with the editable rows.
    func sendEnvironmentValues() {
        let scope = environmentScope
        let values = environmentRows
            .filter { !$0.name.isEmpty }
            .map { EnvironmentVariable(name: $0.name, value: $0.value.isEmpty ? nil : $0.value, scope: scope) }
        perform(.sendEnvironment(values, scope))
    }

    /// `sendWindowSize(columns:rows:)` with the manual fields.
    func sendManualWindowSize() {
        perform(.sendWindowSize(columns: manualColumns, rows: manualRows))
    }

    // MARK: Automatic window size

    /// Called by the terminal view whenever its size changes. The size becomes the NAWS
    /// report once the peer has enabled the option.
    func terminalSizeChanged(width: CGFloat, height: CGFloat) {
        let columns = DemoWindowMetrics.columns(forWidth: width)
        let rows = DemoWindowMetrics.rows(forHeight: height)
        guard measuredSize?.columns != columns || measuredSize?.rows != rows else { return }
        measuredSize = (columns, rows)
        sendMeasuredWindowSize()
    }

    private func sendMeasuredWindowSize() {
        guard windowSizeArmed, let size = measuredSize, connection != nil else { return }
        perform(.sendWindowSize(columns: size.columns, rows: size.rows))
    }

    // MARK: Error injection

    /// Runs one error-injection case. Each case reaches a real failure path rather than
    /// fabricating an error value.
    func inject(_ injection: DemoErrorInjection) {
        switch injection {
        case .unresolvableHost:
            beginConnect(host: "no-such-host.invalid", port: 23, settings: settings)

        case .refusedPort:
            beginConnect(host: "127.0.0.1", port: 1, settings: settings)

        case .connectTimeout:
            var fast = settings
            fast.connectTimeoutSeconds = 1
            beginConnect(host: "10.255.255.1", port: 23, settings: fast)

        case .invalidOptionSet:
            // BINARY together with LINEMODE in `local` is the combination `isValid` rejects.
            var invalid = settings
            invalid.localOptions.insert(.binary)
            invalid.localOptions.insert(.lineMode)
            beginConnect(host: settings.host, port: settings.port, settings: invalid)

        case .oversizedSubnegotiation:
            let oversized = [UInt8](repeating: 0x41, count: settings.subnegotiationLimit + 1)
            perform(.subnegotiate(effectiveSubnegotiationOption, oversized))

        case .terminalTypeWithoutRequest:
            // `replyTerminalType` throws `.invalidConfiguration` when nothing is pending.
            replyTerminalType()

        case .badWindowSize:
            perform(.sendWindowSize(columns: 70_000, rows: 24))

        case .sendAfterClose:
            guard let connection else {
                record(.notConnected, context: "send(text:)")
                return
            }
            Task { [weak self] in
                await self?.runSendAfterClose(connection)
            }

        case .cancelConnect:
            var blackHole = settings
            blackHole.connectTimeoutSeconds = 30
            beginConnect(host: "10.255.255.1", port: 23, settings: blackHole)
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                self?.cancelConnectAttempt()
            }
        }
    }

    private func runSendAfterClose(_ connection: TelnetConnection) async {
        await connection.close()
        do {
            try await connection.send(text: "after close")
        } catch {
            record(error, context: "send(text:) after close()")
        }
    }

    // MARK: Clearing

    func clearEventLog() {
        eventRecords.removeAll()
        eventSequence = 0
    }

    func clearOutput() {
        output = ""
    }

    func clearLogRecords() {
        logRecords.removeAll()
    }

    // MARK: Private

    /// One library operation, so `perform` can switch over it and call the library with a
    /// directly visible `throws(TelnetError)` contract.
    private enum DemoOperation: Sendable {
        case sendText(String, lineEnding: TelnetLineEnding)
        case sendTextDefault(String)
        case sendBytes([UInt8])
        case sendRawBytes([UInt8])
        case sendCommand(TelnetCommand)
        case requestOption(TelnetOption)
        case subnegotiate(TelnetOption, [UInt8])
        case replyTerminalType(String)
        case sendEnvironment([EnvironmentVariable], EnvironmentScope)
        case sendWindowSize(columns: Int, rows: Int)

        var label: String {
            switch self {
            case .sendText: "send(text:lineEnding:)"
            case .sendTextDefault: "send(text:)"
            case .sendBytes: "send(_:)"
            case .sendRawBytes: "sendRaw(_:)"
            case .sendCommand: "send(command:)"
            case .requestOption: "requestOption(_:)"
            case .subnegotiate: "subnegotiate(option:payload:)"
            case .replyTerminalType: "replyTerminalType(_:)"
            case .sendEnvironment: "sendEnvironment(_:scope:)"
            case .sendWindowSize: "sendWindowSize(columns:rows:)"
            }
        }

        var detail: String {
            switch self {
            case .sendText(let text, let ending): "\(text) \(ending.demoName)"
            case .sendTextDefault(let text): "\(text) CR LF"
            case .sendBytes(let bytes), .sendRawBytes(let bytes): DemoHex.string(bytes)
            case .sendCommand(let command): command.demoName
            case .requestOption(let option): option.displayName
            case .subnegotiate(let option, let payload): "\(option.displayName) \(DemoHex.string(payload))"
            case .replyTerminalType(let type): type
            case .sendEnvironment(let values, let scope): "\(scope.demoName): \(values.count) variables"
            case .sendWindowSize(let columns, let rows): "\(columns)x\(rows)"
            }
        }
    }

    private func perform(_ operation: DemoOperation) {
        guard let connection else {
            record(.notConnected, context: operation.label)
            return
        }
        Task { [weak self] in
            await self?.run(operation, connection: connection)
        }
    }

    private func run(_ operation: DemoOperation, connection: TelnetConnection) async {
        do {
            switch operation {
            case .sendText(let text, let ending):
                try await connection.send(text: text, lineEnding: ending)
            case .sendTextDefault(let text):
                try await connection.send(text: text)
            case .sendBytes(let bytes):
                try await connection.send(bytes)
            case .sendRawBytes(let bytes):
                try await connection.sendRaw(bytes)
            case .sendCommand(let command):
                try await connection.send(command: command)
            case .requestOption(let option):
                try await connection.requestOption(option)
            case .subnegotiate(let option, let payload):
                try await connection.subnegotiate(option: option, payload: payload)
            case .replyTerminalType(let type):
                try await connection.replyTerminalType(type)
                terminalTypeRequestPending = false
            case .sendEnvironment(let values, let scope):
                try await connection.sendEnvironment(values, scope: scope)
            case .sendWindowSize(let columns, let rows):
                try await connection.sendWindowSize(columns: columns, rows: rows)
                lastReportedSize = "\(columns)x\(rows)"
            }
            appendRecord(category: .lifecycle, name: operation.label, detail: operation.detail)
        } catch {
            record(error, context: operation.label)
        }
    }

    private func record(_ error: TelnetError, context: String) {
        lastError = error
        lastErrorText = "\(context) → \(error.demoDescription)"
        appendRecord(category: .error, name: error.demoName, detail: "\(context) → \(error.demoDescription)")
    }

    private func appendRecord(category: DemoEventCategory, name: String, detail: String) {
        eventSequence += 1
        eventRecords.append(
            DemoEventRecord(sequence: eventSequence, category: category, name: name, detail: detail)
        )
        if eventRecords.count > maximumRecords {
            eventRecords.removeFirst(eventRecords.count - maximumRecords)
        }
    }

    private func append(logRecord: DemoLogRecord) {
        logRecords.append(logRecord)
        if logRecords.count > maximumRecords {
            logRecords.removeFirst(logRecords.count - maximumRecords)
        }
    }

    private func appendOutput(_ text: String) {
        guard !text.isEmpty else { return }
        output += text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if output.count > maximumOutputCharacters {
            output.removeFirst(output.count - maximumOutputCharacters)
        }
    }
}

/// One editable NEW-ENVIRON row.
struct DemoEnvironmentRow: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var value: String

    static var defaults: [DemoEnvironmentRow] {
        [
            DemoEnvironmentRow(
                name: "USER",
                value: ProcessInfo.processInfo.environment["USER"] ?? "demo"
            ),
            DemoEnvironmentRow(name: "TERM", value: "xterm-256color"),
        ]
    }
}

/// The failures the demo can provoke without a cooperating peer.
enum DemoErrorInjection: String, CaseIterable, Identifiable {
    case unresolvableHost
    case refusedPort
    case connectTimeout
    case invalidOptionSet
    case oversizedSubnegotiation
    case terminalTypeWithoutRequest
    case badWindowSize
    case sendAfterClose
    case cancelConnect

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unresolvableHost: "Unresolvable host"
        case .refusedPort: "Refused port"
        case .connectTimeout: "Connect timeout"
        case .invalidOptionSet: "Invalid option set"
        case .oversizedSubnegotiation: "Oversized subnegotiation"
        case .terminalTypeWithoutRequest: "Terminal type without a request"
        case .badWindowSize: "Window size out of range"
        case .sendAfterClose: "Send after close"
        case .cancelConnect: "Cancel a connect attempt"
        }
    }

    var expectedError: String {
        switch self {
        case .unresolvableHost: ".invalidHost"
        case .refusedPort: ".connectionRefused"
        case .connectTimeout: ".connectTimeout"
        case .invalidOptionSet: ".invalidConfiguration"
        case .oversizedSubnegotiation: ".subnegotiationTooLarge"
        case .terminalTypeWithoutRequest: ".invalidConfiguration"
        case .badWindowSize: ".invalidConfiguration"
        case .sendAfterClose: ".notConnected"
        case .cancelConnect: ".cancelled"
        }
    }
}
