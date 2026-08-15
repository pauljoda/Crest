import Foundation

enum BrowserHTMLTokenizer {
    static func tokenize(
        _ html: String,
        receive: (BrowserHTMLToken) throws -> Void
    ) throws {
        var index = html.startIndex
        while index < html.endIndex {
            guard let tagStart = html[index...].firstIndex(of: "<") else {
                try receive(.text(String(html[index...])))
                return
            }
            if tagStart > index {
                try receive(.text(String(html[index..<tagStart])))
            }
            if html[tagStart...].hasPrefix("<!--") {
                guard let commentEnd = html[tagStart...].range(of: "-->")?.upperBound else {
                    throw BrowserBookmarkMigrationError.invalidContents
                }
                index = commentEnd
                continue
            }
            guard let tagEnd = endOfTag(in: html, after: tagStart) else {
                throw BrowserBookmarkMigrationError.invalidContents
            }
            let contentStart = html.index(after: tagStart)
            let content = String(html[contentStart..<tagEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try emitTag(content, receive: receive)
            index = html.index(after: tagEnd)
        }
    }

    private static func endOfTag(
        in html: String,
        after tagStart: String.Index
    ) -> String.Index? {
        var index = html.index(after: tagStart)
        var quote: Character?
        while index < html.endIndex {
            let character = html[index]
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            } else if character == ">", quote == nil {
                return index
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func emitTag(
        _ content: String,
        receive: (BrowserHTMLToken) throws -> Void
    ) throws {
        guard !content.isEmpty,
            !content.hasPrefix("!"),
            !content.hasPrefix("?")
        else { return }
        if content.hasPrefix("/") {
            let name = content.dropFirst()
                .prefix { !$0.isWhitespace && $0 != ">" }
                .lowercased()
            if !name.isEmpty {
                try receive(.endTag(name: name))
            }
            return
        }
        let parsed = parseStartTag(content)
        guard !parsed.name.isEmpty else { return }
        try receive(.startTag(name: parsed.name, attributes: parsed.attributes))
        if parsed.isSelfClosing {
            try receive(.endTag(name: parsed.name))
        }
    }

    private static func parseStartTag(
        _ content: String
    ) -> (name: String, attributes: [String: String], isSelfClosing: Bool) {
        var index = content.startIndex
        skipWhitespace(in: content, index: &index)
        let nameStart = index
        while index < content.endIndex, !content[index].isWhitespace,
            content[index] != "/"
        {
            index = content.index(after: index)
        }
        let name = content[nameStart..<index].lowercased()
        var attributes: [String: String] = [:]
        var isSelfClosing = false

        while index < content.endIndex {
            skipWhitespace(in: content, index: &index)
            guard index < content.endIndex else { break }
            if content[index] == "/" {
                isSelfClosing = true
                break
            }
            let keyStart = index
            while index < content.endIndex, !content[index].isWhitespace,
                content[index] != "=", content[index] != "/"
            {
                index = content.index(after: index)
            }
            let key = content[keyStart..<index].lowercased()
            skipWhitespace(in: content, index: &index)

            var value = ""
            if index < content.endIndex, content[index] == "=" {
                index = content.index(after: index)
                skipWhitespace(in: content, index: &index)
                value = parseAttributeValue(in: content, index: &index)
            }
            if !key.isEmpty {
                attributes[key] = BrowserHTMLEntities.decode(value)
            }
        }
        return (name, attributes, isSelfClosing)
    }

    private static func parseAttributeValue(
        in content: String,
        index: inout String.Index
    ) -> String {
        guard index < content.endIndex else { return "" }
        if content[index] == "\"" || content[index] == "'" {
            let quote = content[index]
            index = content.index(after: index)
            let start = index
            while index < content.endIndex, content[index] != quote {
                index = content.index(after: index)
            }
            let value = String(content[start..<index])
            if index < content.endIndex {
                index = content.index(after: index)
            }
            return value
        }
        let start = index
        while index < content.endIndex, !content[index].isWhitespace,
            content[index] != "/"
        {
            index = content.index(after: index)
        }
        return String(content[start..<index])
    }

    private static func skipWhitespace(
        in content: String,
        index: inout String.Index
    ) {
        while index < content.endIndex, content[index].isWhitespace {
            index = content.index(after: index)
        }
    }
}
