import Foundation

extension BrowserBlockedPopupNotice {
    var title: String {
        switch status {
        case .blocked:
            String(localized: "Pop-up blocked for \(origin.host)")
        case .allowedAwaitingRetry:
            String(localized: "Pop-ups allowed for \(origin.host)")
        }
    }

    var guidance: String {
        switch status {
        case .blocked:
            String(
                localized:
                    "Automatic pop-ups are blocked. Allow them for this site, then retry the action on the page."
            )
        case .allowedAwaitingRetry:
            String(
                localized:
                    "Retry the action on the page. Crest did not reopen the blocked pop-up."
            )
        }
    }

    var allowActionAccessibilityLabel: String {
        String(localized: "Allow automatic pop-ups for \(origin.host)")
    }

    var allowActionAccessibilityHint: String {
        String(
            localized:
                "Saves this permission in the current Space. Retry the action on the site afterward"
        )
    }

    func chromeAccessibilityLabel(surfaceName: String) -> String {
        "\(title). \(surfaceName)"
    }
}
