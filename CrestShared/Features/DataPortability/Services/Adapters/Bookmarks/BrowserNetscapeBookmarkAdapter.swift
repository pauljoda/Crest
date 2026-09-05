import Foundation

enum BrowserNetscapeBookmarkAdapter {
    static func decode(
        _ data: Data,
        source: BrowserBookmarkMigrationSource,
        fallbackDate: Date
    ) throws -> [BrowserBookmarkSpaceDraft] {
        guard
            let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw BrowserBookmarkMigrationError.invalidContents
        }
        var parser = NetscapeBookmarkParser(source: source, fallbackDate: fallbackDate)
        try BrowserHTMLTokenizer.tokenize(html) { token in
            try parser.consume(token)
        }
        return parser.drafts
    }

    static func encode(
        session: BrowserSession,
        exportedAt: Date
    ) throws -> Data {
        var writer = BrowserBookmarkHTMLWriter()
        try writer.append("<!DOCTYPE NETSCAPE-Bookmark-file-1>\n")
        try writer.append("<!-- This is an automatically generated file. -->\n")
        try writer.append("<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">\n")
        try writer.append("<TITLE>Crest Bookmarks</TITLE>\n")
        try writer.append("<H1>Crest Bookmarks</H1>\n")
        try writer.append("<DL><p>\n")
        for space in session.spaces {
            try encodeSpace(
                space,
                exportedAt: exportedAt,
                indentation: 1,
                writer: &writer
            )
        }
        try writer.append("</DL><p>\n")
        return Data(writer.output.utf8)
    }

    private static func encodeSpace(
        _ space: BrowserSpace,
        exportedAt: Date,
        indentation: Int,
        writer: inout BrowserBookmarkHTMLWriter
    ) throws {
        let prefix = String(repeating: "    ", count: indentation)
        let timestamp = unixTimestamp(exportedAt)
        try writer.append(
            "\(prefix)<DT><H3 ADD_DATE=\"\(timestamp)\" CREST_SPACE=\"true\">"
                + "\(escapeText(space.name))</H3>\n"
        )
        try writer.append("\(prefix)<DL><p>\n")
        try encodeBookmarks(
            space.tabs.filter {
                ($0.placement == .pinned || $0.placement == .saved) && $0.folderID == nil
            },
            indentation: indentation + 1,
            writer: &writer
        )
        for folder in space.folderTree.children(of: nil) where folder.location == .saved {
            try encodeFolder(
                folder,
                space: space,
                indentation: indentation + 1,
                writer: &writer
            )
        }
        try writer.append("\(prefix)</DL><p>\n")
    }

    private static func encodeFolder(
        _ folder: BrowserFolder,
        space: BrowserSpace,
        indentation: Int,
        writer: inout BrowserBookmarkHTMLWriter
    ) throws {
        let prefix = String(repeating: "    ", count: indentation)
        try writer.append(
            "\(prefix)<DT><H3>\(escapeText(folder.title))</H3>\n"
        )
        try writer.append("\(prefix)<DL><p>\n")
        try encodeBookmarks(
            space.tabs.filter { $0.placement == .saved && $0.folderID == folder.id },
            indentation: indentation + 1,
            writer: &writer
        )
        for child in space.folderTree.children(of: folder.id) {
            try encodeFolder(
                child,
                space: space,
                indentation: indentation + 1,
                writer: &writer
            )
        }
        try writer.append("\(prefix)</DL><p>\n")
    }

    private static func encodeBookmarks(
        _ tabs: [BrowserTab],
        indentation: Int,
        writer: inout BrowserBookmarkHTMLWriter
    ) throws {
        let prefix = String(repeating: "    ", count: indentation)
        for tab in tabs {
            guard let sourceURL = tab.savedSiteURL ?? tab.url,
                let url = BrowserBookmarkValueSanitizer.url(
                    sourceURL.absoluteString
                )
            else { continue }
            try writer.append(
                "\(prefix)<DT><A HREF=\"\(escapeAttribute(url.absoluteString))\" "
                    + "ADD_DATE=\"\(unixTimestamp(tab.lastActivatedAt))\">"
                    + "\(escapeText(tab.title))</A>\n"
            )
        }
    }

    private static func unixTimestamp(_ date: Date) -> Int64 {
        let interval = date.timeIntervalSince1970
        guard interval.isFinite, interval > 0 else { return 0 }
        return Int64(min(interval.rounded(.down), Double(Int64.max)))
    }

    private static func escapeText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func escapeAttribute(_ source: String) -> String {
        escapeText(source).replacingOccurrences(of: "'", with: "&#39;")
    }
}
