import Foundation

extension BrowserOmniboxRegistry {
    /// The registry the shipped palette consults.
    ///
    /// Keyword ownership is process-wide rather than per-window or per-Space:
    /// a keyword resolves to the same provider from whichever address bar it is
    /// typed into. The registry starts empty, so until something registers a
    /// keyword this is inert and the palette behaves exactly as before.
    static let shared = BrowserOmniboxRegistry()
}
