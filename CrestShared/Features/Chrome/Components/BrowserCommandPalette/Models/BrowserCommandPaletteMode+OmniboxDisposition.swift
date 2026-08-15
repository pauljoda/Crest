import Foundation

extension BrowserCommandPaletteMode {
    /// Where an accepted keyword suggestion should open.
    ///
    /// The palette has no modifier-aware submit path, so disposition follows
    /// how the palette was opened: editing the address bar of a tab keeps the
    /// result in that tab, while the new-tab launcher opens a new one.
    var omniboxDisposition: BrowserOmniboxDisposition {
        switch self {
        case .newTab: .newForegroundTab
        case .editLocation: .currentTab
        }
    }
}
