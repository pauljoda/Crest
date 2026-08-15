import Foundation

extension BrowserShortcutSection {
    var titleResource: LocalizedStringResource {
        switch self {
        case .everyday: "Everyday Use"
        case .tabs: "Tabs"
        case .spaces: "Spaces"
        case .page: "Page"
        case .view: "View & Tools"
        }
    }

    var title: String {
        title()
    }

    func title(locale: Locale = .current) -> String {
        BrowserShortcutLocalization.string(titleResource, locale: locale)
    }
}
