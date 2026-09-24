import Foundation

struct BrowserModifiedLinkRegistration {
    let tab: BrowserTab
    let space: BrowserSpace
    /// The opening window's session as it renders it, including its selection.
    let session: BrowserPresentedSession
}
