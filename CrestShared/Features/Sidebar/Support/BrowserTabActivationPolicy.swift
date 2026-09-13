import Foundation

/// Selects the tab before presenting its destination.
enum BrowserTabActivationPolicy {
    enum SettingsPresentation {
        case embedded
        case sheet
    }

    enum Destination {
        case page
        case settings
    }

    static func destination(for tab: BrowserTab, settingsPresentation: SettingsPresentation) -> Destination {
        switch settingsPresentation {
        case .embedded:
            .page
        case .sheet:
            tab.nativeContent == .settings ? .settings : .page
        }
    }

    static func activate(
        _ tabID: TabID,
        selectTab: (TabID) -> Void,
        presentPage: () -> Void
    ) {
        selectTab(tabID)
        presentPage()
    }
}
