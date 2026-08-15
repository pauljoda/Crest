import SwiftUI

struct BrowserNavigationFailurePresentation {
    let failure: BrowserNavigationFailure

    var title: LocalizedStringResource {
        switch failure.kind {
        case .offline:
            "You’re offline"
        case .timedOut:
            "This site took too long to respond"
        case .cannotFindServer:
            "Server not found"
        case .cannotConnect:
            "This site can’t be reached"
        case .connectionLost:
            "The connection was interrupted"
        case .secureConnectionFailed:
            "A secure connection couldn’t be made"
        case .tooManyRedirects:
            "This page is redirecting incorrectly"
        case .unsupportedAddress:
            "Crest can’t open this address"
        case .blocked:
            "This page was blocked"
        case .unavailable:
            "This page isn’t available"
        case .webContentProcessStopped:
            "This page stopped responding"
        case .unknown:
            "This page couldn’t be opened"
        }
    }

    var message: Text {
        switch failure.kind {
        case .offline:
            Text("Crest can’t reach \(failure.displayHost) without a network connection.")
        case .timedOut:
            Text("\(failure.displayHost) didn’t respond in time.")
        case .cannotFindServer:
            Text("Crest couldn’t find the server for \(failure.displayHost).")
        case .cannotConnect:
            Text("\(failure.displayHost) refused the connection or isn’t accepting connections.")
        case .connectionLost:
            Text("The connection to \(failure.displayHost) ended before the page finished loading.")
        case .secureConnectionFailed:
            Text("Crest couldn’t verify a private, secure connection to \(failure.displayHost).")
        case .tooManyRedirects:
            Text("\(failure.displayHost) sent Crest through too many redirects.")
        case .unsupportedAddress:
            Text("The address uses a format or protocol Crest doesn’t support.")
        case .blocked:
            Text("A security or content policy prevented this page from loading.")
        case .unavailable:
            Text("\(failure.displayHost) returned a response Crest couldn’t load.")
        case .webContentProcessStopped:
            Text("The web content process stopped repeatedly. Your tab and address are safe.")
        case .unknown:
            Text("Crest encountered an unexpected problem while opening \(failure.displayHost).")
        }
    }

    var primarySuggestion: LocalizedStringResource {
        switch failure.kind {
        case .offline:
            "Reconnect to Wi-Fi or Ethernet, then try again."
        case .timedOut, .connectionLost:
            "Check your connection and try again in a moment."
        case .cannotFindServer, .unsupportedAddress:
            "Check the address for typing mistakes."
        case .cannotConnect, .unavailable:
            "Check whether the site is available in another browser or device."
        case .secureConnectionFailed:
            "Check that your device’s date and time are correct."
        case .tooManyRedirects:
            "Try again later; the site may be temporarily misconfigured."
        case .blocked:
            "Review this Space’s content and network settings."
        case .webContentProcessStopped:
            "Try reloading the page in a fresh web content process."
        case .unknown:
            "Try the address again or open a different page."
        }
    }

    var secondarySuggestion: LocalizedStringResource {
        switch failure.kind {
        case .offline, .timedOut, .connectionLost:
            "If you use a VPN or proxy, confirm that it is connected."
        case .cannotFindServer:
            "If the address is correct, check your DNS or VPN settings."
        case .cannotConnect, .unavailable:
            "For an intranet site, confirm that you are on the required network."
        case .secureConnectionFailed:
            "Avoid entering private information until the site fixes its certificate."
        case .tooManyRedirects:
            "Opening the site’s home page may avoid the redirect loop."
        case .unsupportedAddress:
            "Try an address beginning with http:// or https://."
        case .blocked:
            "A firewall, filter, or device policy may also be responsible."
        case .webContentProcessStopped:
            "If it happens again, try closing and reopening the tab."
        case .unknown:
            "The technical details below can help identify the cause."
        }
    }

    var symbolName: String {
        switch failure.kind {
        case .offline:
            "wifi.slash"
        case .timedOut:
            "clock.badge.exclamationmark"
        case .cannotFindServer:
            "network.slash"
        case .cannotConnect, .unavailable:
            "exclamationmark.icloud"
        case .connectionLost:
            "bolt.horizontal.icloud"
        case .secureConnectionFailed:
            "lock.trianglebadge.exclamationmark"
        case .tooManyRedirects:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .unsupportedAddress:
            "link.badge.plus"
        case .blocked:
            "hand.raised.slash"
        case .webContentProcessStopped:
            "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .unknown:
            "doc.badge.ellipsis"
        }
    }
}
