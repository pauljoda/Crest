import Foundation

struct NetscapeBookmarkParser {
    private let source: BrowserBookmarkMigrationSource
    private let fallbackDate: Date
    private(set) var drafts: [BrowserBookmarkSpaceDraft]
    private var capture: NetscapeBookmarkParserCapture?
    private var pendingContainer: NetscapeBookmarkParserPendingContainer?
    private var contexts: [NetscapeBookmarkParserContext] = []
    private var definitionListPushes: [Bool] = []

    init(source: BrowserBookmarkMigrationSource, fallbackDate: Date) {
        self.source = source
        self.fallbackDate = fallbackDate
        drafts = [
            BrowserBookmarkSpaceDraft(
                name: String(localized: source.importedSpaceName)
            )
        ]
    }

    mutating func consume(_ token: BrowserHTMLToken) throws {
        switch token {
        case .startTag(let name, let attributes):
            try startTag(name, attributes: attributes)
        case .endTag(let name):
            try endTag(name)
        case .text(let text):
            appendCapturedText(text)
        }
    }

    private mutating func startTag(
        _ name: String,
        attributes: [String: String]
    ) throws {
        switch name {
        case "h3":
            capture = .folder(attributes: attributes, text: "")
        case "a":
            capture = .bookmark(attributes: attributes, text: "")
        case "dl":
            if let pendingContainer {
                switch pendingContainer {
                case .folder(let draftIndex, let id):
                    contexts.append(
                        NetscapeBookmarkParserContext(
                            draftIndex: draftIndex,
                            folderID: id
                        )
                    )
                case .space(let draftIndex):
                    contexts.append(
                        NetscapeBookmarkParserContext(
                            draftIndex: draftIndex,
                            folderID: nil
                        )
                    )
                }
                self.pendingContainer = nil
                definitionListPushes.append(true)
            } else {
                definitionListPushes.append(false)
            }
        default:
            break
        }
    }

    private mutating func endTag(_ name: String) throws {
        switch name {
        case "h3":
            try finishFolderCapture()
        case "a":
            try finishBookmarkCapture()
        case "dl":
            pendingContainer = nil
            if definitionListPushes.popLast() == true {
                _ = contexts.popLast()
            }
        default:
            break
        }
    }

    private mutating func appendCapturedText(_ text: String) {
        switch capture {
        case .folder(let attributes, let existing):
            capture = .folder(attributes: attributes, text: existing + text)
        case .bookmark(let attributes, let existing):
            capture = .bookmark(attributes: attributes, text: existing + text)
        case nil:
            break
        }
    }

    private mutating func finishFolderCapture() throws {
        guard case .folder(let attributes, let text) = capture else { return }
        capture = nil
        let title = BrowserHTMLEntities.decode(text)

        if attributes["crest_space"]?.lowercased() == "true", contexts.isEmpty {
            let normalizedTitle = try BrowserBookmarkValueSanitizer.title(
                title,
                fallback: String(localized: source.importedSpaceName),
                maximumLength: 200
            )
            drafts.append(BrowserBookmarkSpaceDraft(name: normalizedTitle))
            pendingContainer = .space(draftIndex: drafts.index(before: drafts.endIndex))
            return
        }

        let draftIndex = currentDraftIndex
        let parentID = contexts.last?.folderID
        let depth = contexts.reduce(into: 0) { count, context in
            if context.folderID != nil { count += 1 }
        }
        let id = try drafts[draftIndex].appendFolder(
            title: title,
            parentID: parentID,
            depth: depth
        )
        pendingContainer = .folder(draftIndex: draftIndex, id: id)
    }

    private mutating func finishBookmarkCapture() throws {
        guard case .bookmark(let attributes, let text) = capture else { return }
        capture = nil
        guard let href = attributes["href"] else { return }
        let draftIndex = currentDraftIndex
        try drafts[draftIndex].appendBookmark(
            title: BrowserHTMLEntities.decode(text),
            url: href,
            folderID: contexts.last?.folderID,
            addedAt: BrowserBookmarkValueSanitizer.date(
                attributes["add_date"],
                epoch: .unixSeconds,
                fallback: fallbackDate
            )
        )
    }

    private var currentDraftIndex: Int {
        contexts.last?.draftIndex ?? 0
    }
}
