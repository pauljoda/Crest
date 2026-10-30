import Foundation

struct BrowserAboutBuildInformation: Equatable, Sendable {
    let version: String
    let build: String
    let bundleIdentifier: String

    static let current = BrowserAboutBuildInformation(bundle: .main)

    init(bundle: Bundle) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    init(
        infoDictionary: [String: Any],
        bundleIdentifier: String?
    ) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
        self.bundleIdentifier =
            bundleIdentifier ?? ProductIdentity.bundleIdentifier
    }
}

enum BrowserAboutLinks {
    static var feedback: URL {
        url("https://www.reddit.com/r/CrestBrowser")
    }

    static var issues: URL {
        url("https://github.com/pauljoda/Crest/issues/new/choose")
    }

    /// Where to ask Crest to import from a browser it does not list.
    static var browserRequest: URL {
        url("https://github.com/pauljoda/Crest/issues/new?template=feature_request.yml&title=Import%20from%20")
    }

    static var roadmap: URL {
        url("https://github.com/users/pauljoda/projects/3")
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid About link: \(value)")
        }
        return url
    }
}

enum BrowserAboutReleaseNoteCategory: String, Decodable, Sendable {
    case new
    case improved
    case fixed
    case `internal`
}

struct BrowserAboutReleaseNote: Equatable, Identifiable, Sendable {
    let id: String
    let category: BrowserAboutReleaseNoteCategory
    let message: String
}

/// The release-note catalog Crest ships, in the order the catalog lists it.
///
/// The catalog only ever appends, so its order is its chronology: the last
/// entries are the newest. Entry ids are plain words, not dates, so sorting
/// them says nothing about age.
struct BrowserAboutReleaseNotes: Sendable {
    // MARK: - Types

    private struct Document: Decodable {
        let entries: [String: Entry]
    }

    private struct Entry: Decodable {
        let category: BrowserAboutReleaseNoteCategory
        let message: String
    }

    // MARK: - Static Variables

    /// How many of the newest public entries What's New lists.
    static let highlightLimit = 12

    static let bundled = loadBundled()

    // MARK: - Variables

    /// Every entry, oldest first.
    let entries: [BrowserAboutReleaseNote]

    /// The newest public entries, newest first, capped at `highlightLimit`.
    let currentHighlights: [BrowserAboutReleaseNote]

    // MARK: - Initializers

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        var remaining = document.entries
        var ordered = Self.entryOrder(in: data).compactMap { id in
            remaining.removeValue(forKey: id).map { entry in
                BrowserAboutReleaseNote(id: id, category: entry.category, message: entry.message)
            }
        }
        // Anything the scan missed still appears, after the ordered entries.
        for (id, entry) in remaining.sorted(by: { $0.key < $1.key }) {
            ordered.append(BrowserAboutReleaseNote(id: id, category: entry.category, message: entry.message))
        }
        self.init(entries: ordered)
    }

    init(entries: [BrowserAboutReleaseNote]) {
        self.entries = entries
        let publicEntries = entries.filter { $0.category != .internal }
        currentHighlights = publicEntries.suffix(Self.highlightLimit).reversed()
    }

    // MARK: - Actions - Order

    /// The ids of the `entries` object in the order the catalog text lists them.
    ///
    /// `JSONDecoder` returns the entries as a dictionary and forgets that order, so
    /// one pass over the text recovers it: it tracks strings and nesting, and
    /// records each key one level inside the root `entries` object.
    private static func entryOrder(in data: Data) -> [String] {
        let quote = UInt8(ascii: "\"")
        let escape = UInt8(ascii: "\\")
        let open = UInt8(ascii: "{")
        let close = UInt8(ascii: "}")
        let colon = UInt8(ascii: ":")
        let whitespace: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\t")]
        var keys: [String] = []
        var depth = 0
        var entriesDepth: Int?
        var awaitingEntriesObject = false
        var index = data.startIndex
        while index < data.endIndex {
            let byte = data[index]
            index += 1
            switch byte {
            case open:
                depth += 1
                if awaitingEntriesObject {
                    entriesDepth = depth
                    awaitingEntriesObject = false
                }
            case close:
                if depth == entriesDepth { return keys }
                depth -= 1
            case quote:
                let start = index
                while index < data.endIndex, data[index] != quote {
                    index += data[index] == escape ? 2 : 1
                }
                let end = min(index, data.endIndex)
                index = end + 1
                var next = index
                while next < data.endIndex, whitespace.contains(data[next]) { next += 1 }
                guard next < data.endIndex, data[next] == colon else { continue }
                let key = Self.stringValue(of: data[start..<end])
                if depth == entriesDepth {
                    keys.append(key)
                } else if depth == 1, key == "entries" {
                    awaitingEntriesObject = true
                }
            default:
                break
            }
        }
        return keys
    }

    /// The text a JSON string literal's contents spell.
    private static func stringValue(of contents: Data) -> String {
        guard contents.contains(UInt8(ascii: "\\")) else {
            return String(decoding: contents, as: UTF8.self)
        }
        var literal = Data([UInt8(ascii: "\"")])
        literal.append(contents)
        literal.append(UInt8(ascii: "\""))
        return (try? JSONDecoder().decode(String.self, from: literal)) ?? String(decoding: contents, as: UTF8.self)
    }

    // MARK: - Actions - Loading

    private static func loadBundled() -> BrowserAboutReleaseNotes {
        guard
            let url = Bundle.main.url(
                forResource: "ReleaseNotes",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let releaseNotes = try? BrowserAboutReleaseNotes(data: data)
        else {
            return BrowserAboutReleaseNotes(entries: [])
        }
        return releaseNotes
    }
}
