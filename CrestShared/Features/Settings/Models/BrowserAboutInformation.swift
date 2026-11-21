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

enum BrowserAboutReleasePlatform: String, Decodable, Sendable {
    case mac
    case ios

    static var current: BrowserAboutReleasePlatform {
        #if os(macOS)
            .mac
        #else
            .ios
        #endif
    }
}

struct BrowserAboutReleaseNote: Equatable, Identifiable, Sendable {
    let id: String
    let category: BrowserAboutReleaseNoteCategory
    let message: String
}

/// The release notes bundled with Crest: one file per version, under a folder
/// for each release line, as `Documentation/ReleaseNotes` keeps them.
struct BrowserAboutReleaseNotes: Sendable {
    // MARK: - Types

    private struct Document: Decodable {
        let entries: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let category: BrowserAboutReleaseNoteCategory
        let message: String
        let platforms: [BrowserAboutReleasePlatform]?
    }

    // MARK: - Static Variables

    static let bundled = BrowserAboutReleaseNotes(
        directory: Bundle.main.url(forResource: "ReleaseNotes", withExtension: nil)
    )

    // MARK: - Variables

    /// Each version's notes file, newest version first.
    private let versionFiles: [URL]

    // MARK: - Initializers

    init(directory: URL?) {
        let fileManager = FileManager.default
        let lines =
            directory.flatMap {
                try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
            } ?? []
        let files = lines.flatMap {
            (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? []
        }
        versionFiles =
            files
            .compactMap { file in Self.versionNumbers(of: file).map { (file, $0) } }
            .sorted { $1.1.lexicographicallyPrecedes($0.1) }
            .map(\.0)
    }

    // MARK: - Actions - Highlights

    /// The newest public notes that reach this platform, reading only as many
    /// version files as it takes.
    func currentHighlights(
        limit: Int = 12,
        platform: BrowserAboutReleasePlatform = .current
    ) -> [BrowserAboutReleaseNote] {
        var highlights: [BrowserAboutReleaseNote] = []
        for file in versionFiles where highlights.count < limit {
            guard
                let data = try? Data(contentsOf: file),
                let document = try? JSONDecoder().decode(Document.self, from: data)
            else { continue }
            highlights += document.entries
                .filter { entry in
                    entry.category != .internal && entry.platforms?.contains(platform) != false
                }
                .map { entry in
                    BrowserAboutReleaseNote(id: entry.id, category: entry.category, message: entry.message)
                }
        }
        return Array(highlights.prefix(limit))
    }

    // MARK: - Actions - Versions

    private static func versionNumbers(of file: URL) -> [Int]? {
        guard file.pathExtension == "json" else { return nil }
        let parts = file.deletingPathExtension().lastPathComponent.split(separator: ".")
        let numbers = parts.compactMap { Int($0) }
        return numbers.count == 3 && parts.count == 3 ? numbers : nil
    }
}
