import Foundation
import WebKit

/// Why a page couldn't load, and what Try Again should load.
struct LoadFailure {
    let message: String
    let url: URL?
    var kind = PageFailureKind.unreachable
    /// Whether it may well load on its own later: the connection was down or dropped. A page whose process ended loads
    /// again by its own rule (`CrashRestoreBudget`), never on a network change.
    var passes = false

    /// Nil for navigations that were cut short rather than failed: superseded by another load, or turned into a download.
    init?(_ error: any Error) {
        let underlying: any Error
        switch error as? WebPage.NavigationError {
        case .failedProvisionalNavigation(let inner): underlying = inner
        case .webContentProcessTerminated:
            message = "Reload the page to continue."
            url = nil
            kind = .crashed
            return
        case .invalidURL:
            message = "The address isn't valid."
            url = nil
            return
        case .pageClosed: return nil
        default: underlying = error
        }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        // WebKitErrorFrameLoadInterruptedByPolicyChange: the response became a download.
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return nil }
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed:
                message = "Check your connection. The page loads again on its own when you're back online."
            case NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                message = "The connection was interrupted. Try again."
            case NSURLErrorCannotFindHost:
                message = "This website couldn't be found. Check the address and try again."
            case NSURLErrorUnsupportedURL:
                message = "No app is available to open this link."
            default:
                message = nsError.localizedDescription
            }
        } else {
            message = nsError.localizedDescription
        }
        url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        kind = PageFailureKind(nsError)
        passes = nsError.domain == NSURLErrorDomain && [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
            NSURLErrorDataNotAllowed, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
        ].contains(nsError.code)
    }

    /// WebKit refuses some ports (1, 9, 25 and so on) without any navigation error: it commits about:blank instead.
    init?(blocked requested: URL?, committed: URL?) {
        guard committed?.absoluteString == "about:blank", let requested, requested.scheme?.hasPrefix("http") == true
        else { return nil }
        message = "Boaz couldn't open this address."
        url = requested
    }
}
