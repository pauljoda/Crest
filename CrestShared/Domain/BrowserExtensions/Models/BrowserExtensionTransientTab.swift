import Foundation

/// A page extensions can see and address that the browsing session does not
/// carry as a tab.
///
/// A Peek is the case this exists for. It is a real document in a Space,
/// created with that Space's extension controller attached, so WebKit injects
/// every granted content script into it. WebKit answers a content script's
/// `runtime` messages by mapping its web view back to a tab the host has
/// announced, so a page that is never announced leaves those scripts talking to
/// nobody: their opening question is rejected outright, and an extension that
/// styles pages keeps whatever partial state it applied before asking. The page
/// stays wrong until it is reloaded.
///
/// Announcing the page is what makes WebKit's two halves agree. It is also the
/// truthful description: the person is looking at a live page, so hiding it
/// from extensions while still running their code inside it is the dishonest
/// half of the current arrangement, not the disclosure.
struct BrowserExtensionTransientTab: Equatable, Sendable {
    let id: TabID
    let url: URL
}
