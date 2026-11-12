import Foundation

/// An address on its way out of Crest: to the pasteboard, a share sheet, or
/// anything else another app reads.
///
/// Only the core makes one, through `CrestCore.linkToCopy(_:)`, and every
/// path that hands an address out takes one, so none can skip Super Copy:
/// while it is on, the address arrives unwrapped from a redirect and without
/// the parameters that track who followed it.
struct BrowserCopiedLink: Hashable, Sendable {
    // MARK: - Variables

    let url: URL

    // MARK: - Initializers

    fileprivate init(_ url: URL) {
        self.url = url
    }

    // MARK: - Actions - Markdown

    /// The link as Markdown, labelled `title`, or its host when the title is
    /// blank. Brackets in the label and parentheses in the address are
    /// escaped, so a Markdown reader neither splits the label nor ends the
    /// destination early.
    func markdown(title: String) -> String {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = label.isEmpty ? (url.host() ?? url.absoluteString) : label
        let escaped = resolved.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let destination = url.absoluteString.replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(
            of: ")", with: "\\)")
        return "[\(escaped)](\(destination))"
    }
}

extension CrestCore {
    /// `url` as Crest hands it out: as Super Copy leaves it while it is on,
    /// and as it is otherwise or if the core cannot say.
    func linkToCopy(_ url: URL) -> BrowserCopiedLink {
        guard let copied = try? query(LinkToCopy(url: url.absoluteString)), let link = URL(string: copied) else {
            return BrowserCopiedLink(url)
        }
        return BrowserCopiedLink(link)
    }
}
