import Foundation
import WebKit

/// The tab a popup was adopted into, together with the Space that owns it, so a
/// page pool can build the adopting page without reaching for session state.
struct BrowserPopupTabRegistration: Equatable, Sendable {
    let tab: BrowserTab
    let space: BrowserSpace
}
