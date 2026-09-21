import Foundation
import Network
import NIOCore
import NIOTransportServices

/// Turns Network.framework facts into Swift values at the one place that sees them.
///
/// `NWPath`, `NWError`, and `nw_*` names stop here, so no Apple framework type reaches the
/// public API and a future change to one cannot alter a public signature.
enum TelnetNetworkEventMapping {
    /// Maps a `NIOTSNetworkEvents` value, or nil for an event that is not a path report.
    static func telnetEvent(from event: Any) -> TelnetEvent? {
        switch event {
        case let pathChanged as NIOTSNetworkEvents.PathChanged:
            let path = pathChanged.newPath
            return .pathChanged(
                viable: path.status == .satisfied,
                expensive: path.isExpensive,
                constrained: path.isConstrained
            )
        case is NIOTSNetworkEvents.BetterPathAvailable:
            return .betterPathAvailable
        case is NIOTSNetworkEvents.BetterPathUnavailable:
            return .betterPathUnavailable
        case let viability as NIOTSNetworkEvents.ViabilityUpdate:
            return .viabilityChanged(isViable: viability.isViable)
        case let waiting as NIOTSNetworkEvents.WaitingForConnectivity:
            return .waitingForConnectivity(
                error: String(describing: waiting.transientError),
                description: String(describing: waiting.transientError)
            )
        default:
            return nil
        }
    }

    /// Maps an underlying error into the structured transport failure the public API keeps.
    static func transportFailure(from error: any Error) -> TelnetTransportFailure {
        if let networkError = error as? NWError {
            switch networkError {
            case .posix(let code):
                return TelnetTransportFailure(
                    kind: .posix(code: code.rawValue),
                    message: String(describing: networkError),
                    isRetryable: isRetryablePOSIX(code.rawValue)
                )
            case .dns:
                return TelnetTransportFailure(
                    kind: .dns,
                    message: String(describing: networkError),
                    isRetryable: true
                )
            case .tls:
                return TelnetTransportFailure(
                    kind: .tls,
                    message: String(describing: networkError),
                    isRetryable: false
                )
            case .wifiAware:
                return TelnetTransportFailure(
                    kind: .other,
                    message: String(describing: networkError),
                    isRetryable: false
                )
            @unknown default:
                return TelnetTransportFailure(
                    kind: .other,
                    message: String(describing: networkError),
                    isRetryable: false
                )
            }
        }
        if let channelError = error as? ChannelError {
            switch channelError {
            case .eof, .inputClosed, .outputClosed, .ioOnClosedChannel, .alreadyClosed:
                return TelnetTransportFailure(
                    kind: .channelClosed,
                    message: String(describing: channelError),
                    isRetryable: false
                )
            default:
                return TelnetTransportFailure(
                    kind: .other,
                    message: String(describing: channelError),
                    isRetryable: false
                )
            }
        }
        return TelnetTransportFailure(
            kind: .other,
            message: String(describing: error),
            isRetryable: false
        )
    }

    /// Maps a connect failure into the typed error `connect(host:port:...)` throws.
    static func connectError(
        from error: any Error,
        host: String,
        port: Int,
        timeout: Duration
    ) -> TelnetError {
        if error is CancellationError {
            return .cancelled
        }
        if let channelError = error as? ChannelError, case .connectTimeout = channelError {
            return .connectTimeout(timeout)
        }
        if let networkError = error as? NWError {
            switch networkError {
            case .posix(let code) where code.rawValue == ECONNREFUSED:
                return .connectionRefused(host: host, port: port)
            case .dns:
                return .invalidHost(host)
            default:
                return .transportFailed(transportFailure(from: error))
            }
        }
        return .transportFailed(transportFailure(from: error))
    }

    private static func isRetryablePOSIX(_ code: Int32) -> Bool {
        switch code {
        case ECONNREFUSED, ETIMEDOUT, EHOSTUNREACH, ENETUNREACH, ECONNRESET, ENETDOWN:
            return true
        default:
            return false
        }
    }
}
