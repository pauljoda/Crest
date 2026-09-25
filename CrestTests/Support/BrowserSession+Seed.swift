import Foundation

@testable import Crest

extension BrowserSession {
    /// The session as the core opens it from a seed: repaired as the file's
    /// session is when it loads. Each tab wears the image it carried, and a
    /// tab the repair gave a new identity wears its source's.
    @MainActor func openedAsSeed() throws -> BrowserSession {
        let opened = try BrowserCoreSessionAuthority.open(.persistent, seed: self, in: CrestCore())
        defer { opened.close() }
        return opened.projection
    }
}
