import Foundation

/// The three ways a page fails to show, with one title and symbol on every build (docs/copy.md): a page that can't be
/// reached, no connection at all, and a page whose process ended.
enum PageFailureKind {
    case unreachable, offline, crashed

    init(_ error: NSError) {
        let offline = error.domain == NSURLErrorDomain
            && [NSURLErrorNotConnectedToInternet, NSURLErrorDataNotAllowed].contains(error.code)
        self = offline ? .offline : .unreachable
    }

    var title: String {
        switch self {
        case .unreachable: "Can't Open This Page"
        case .offline: "You're Offline"
        case .crashed: "This Page Stopped Responding"
        }
    }

    var symbol: String {
        switch self {
        case .unreachable: "exclamationmark.circle"
        case .offline: "wifi.slash"
        case .crashed: "exclamationmark.triangle"
        }
    }
}
