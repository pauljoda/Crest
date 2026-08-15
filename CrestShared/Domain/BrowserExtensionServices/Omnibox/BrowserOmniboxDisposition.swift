import Foundation

/// Where an accepted omnibox suggestion should open.
///
/// Mirrors `chrome.omnibox.OnInputEnteredDisposition`. Crest decides this from
/// how the palette was opened — editing the current address versus starting a
/// new tab — rather than from a modifier key, because the palette has no
/// modifier-aware submit path today.
enum BrowserOmniboxDisposition: String, CaseIterable, Equatable, Hashable, Sendable {
    case currentTab
    case newForegroundTab
    case newBackgroundTab
}
