import Foundation

/// What Crest will treat as a local document, and how a typed address becomes one.
///
/// Mirrors `AddressResolution.LocalFile` in the core so both engines resolve the
/// same three spellings — an explicit `file://` URL, an absolute path, and a
/// home-relative path — to the same URL. Nothing here touches the file system:
/// whether the document exists is the engine's answer to give, not the address
/// bar's, and keeping it out means the decision is the same on every device.
enum BrowserLocalFilePolicy {
    /// A local document Crest is willing to open. Remote authorities are refused;
    /// `file://localhost/…` is this device spelled the long way round.
    static func accepts(_ url: URL) -> Bool {
        guard url.isFileURL, url.user() == nil, !url.path().isEmpty else { return false }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return true }
        return host.lowercased() == "localhost"
    }

    /// The local document a typed address names, or nil when the address is not
    /// one. The result always has an empty authority so page identity, history
    /// and the sync scheme filter see one spelling.
    static func fileURL(from input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("~") {
            guard value.count == 1 || value[value.index(after: value.startIndex)] == "/" else { return nil }
            let home = NSHomeDirectory()
            guard !home.isEmpty else { return nil }
            return normalized(URL(fileURLWithPath: home + value.dropFirst()))
        }
        if value.hasPrefix("/") { return normalized(URL(fileURLWithPath: value)) }
        guard value.lowercased().hasPrefix("file:"), let url = URL(string: value), accepts(url) else { return nil }
        return normalized(url)
    }

    private static func normalized(_ url: URL) -> URL? {
        guard accepts(url) else { return nil }
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return url.standardizedFileURL }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = ""
        return components?.url?.standardizedFileURL
    }
}
