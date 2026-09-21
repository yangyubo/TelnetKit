/// The options this end offers and the options this end asks the peer for.
///
/// `local` lists the options this end offers with `will`, and `remote` lists the options
/// this end asks the peer for with `do`. An option may appear in both lists; `echo` and
/// `suppressGoAhead` are commonly negotiated in both directions.
public struct TelnetOptions: Sendable {
    /// One option this end offers to the peer.
    public struct LocalOption: Sendable, Hashable {
        /// The option.
        public var option: TelnetOption
        /// Whether the option is offered at connect time.
        public var enabledByDefault: Bool

        /// Creates a local option entry.
        public init(_ option: TelnetOption, enabledByDefault: Bool = true) {
            self.option = option
            self.enabledByDefault = enabledByDefault
        }
    }

    /// One option this end wants from the peer.
    public struct RemoteOption: Sendable, Hashable {
        /// The option.
        public var option: TelnetOption
        /// Whether the option is requested at connect time.
        public var requestOnConnect: Bool

        /// Creates a remote option entry.
        public init(_ option: TelnetOption, requestOnConnect: Bool = true) {
            self.option = option
            self.requestOnConnect = requestOnConnect
        }
    }

    /// The options this end offers with `will`.
    public var local: [LocalOption]
    /// The options this end requests with `do`.
    public var remote: [RemoteOption]

    /// Creates an option set.
    public init(local: [LocalOption] = [], remote: [RemoteOption] = []) {
        self.local = local
        self.remote = remote
    }

    /// False for a combination the protocol rejects.
    ///
    /// Currently that is `binary` together with `lineMode` in `local`;
    /// `TelnetConnection.connect` throws `.invalidConfiguration` rather than negotiating
    /// an invalid set.
    public var isValid: Bool {
        let localOptions = local.filter(\.enabledByDefault).map(\.option)
        if localOptions.contains(.binary) && localOptions.contains(.lineMode) {
            return false
        }
        return true
    }

    /// BINARY, SGA, and ECHO offered locally, with SGA requested remotely.
    public static var standardClient: TelnetOptions {
        TelnetOptions(
            local: [
                LocalOption(.binary),
                LocalOption(.suppressGoAhead),
                LocalOption(.echo),
            ],
            remote: [
                RemoteOption(.suppressGoAhead),
            ]
        )
    }

    /// The peer-side set a server caller needs: each option is requested from the peer.
    public static func serverRequesting(_ options: [TelnetOption]) -> TelnetOptions {
        TelnetOptions(
            local: [
                LocalOption(.suppressGoAhead),
            ],
            remote: options.map { RemoteOption($0) }
        )
    }
}
