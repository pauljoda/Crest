import CoreML
import Foundation

// MARK: - Types

/// How often each word appears in one document, and the order words first
/// appear in, which breaks ties.
private struct WordCounts {
    var counts: [String: Int] = [:]
    var order: [String] = []
    var total = 0

    init(_ words: [String]) {
        for word in words {
            if counts[word] == nil { order.append(word) }
            counts[word, default: 0] += 1
            total += 1
        }
    }
}

/// Tidy with open models, for devices without Apple Intelligence.
/// all-MiniLM-L6-v2 embeds each tab's cleaned title, and Mozilla's
/// smart-tab-topic names each group from three of its titles and three
/// keywords, fed as Firefox feeds it. Nothing runs in the background; the
/// models run only when the person presses Tidy.
@MainActor
final class OpenTidyModels: TidyTabModels {
    // MARK: - Static Variables

    /// Words too common in titles to tell groups apart.
    private static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "has", "have", "how", "in", "is", "it",
        "its", "of", "on", "or", "that", "the", "this", "to", "was", "what", "when", "where", "which", "who", "why",
        "will", "with", "you", "your", "vs", "not", "new", "best", "top", "guide", "home", "page", "official", "site",
        "com", "www", "wikipedia", "free", "online", "documentation", "docs", "login", "sign", "up", "search",
        "google",
    ]
    private static let word = try! NSRegularExpression(pattern: "[a-z][a-z'-]+")
    private static let keywordCount = 3
    private static let promptTitleCount = 3
    /// The most titles of one group the keywords are counted over.
    private static let keywordTitleCount = 10

    // MARK: - Variables

    private let embedder: TidySentenceEmbedder
    private let namer: TidyTopicNamer

    // MARK: - Initializers

    /// Compiles the downloaded Core ML packages in `directory` for this device
    /// and loads them.
    init(directory: URL) async throws {
        func compiled(_ name: String) async throws -> URL {
            let destination = directory.appendingPathComponent("\(name).mlmodelc", isDirectory: true)
            let temporary = try await MLModel.compileModel(
                at: directory.appendingPathComponent("\(name).mlpackage", isDirectory: true))
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        }
        embedder = try await TidySentenceEmbedder(
            vocabularyURL: directory.appendingPathComponent("vocab.txt"), modelURL: compiled("MiniLM"))
        namer = try await TidyTopicNamer(
            tokenizerURL: directory.appendingPathComponent("tokenizer.json"),
            encoderURL: compiled("TopicEncoder"), decoderURL: compiled("TopicDecoder"))
    }

    // MARK: - Actions - Warming

    func prewarm() {}

    // MARK: - Actions - Embedding

    func vectors(for candidates: [TidyTabCandidate]) async throws -> [[Float]] {
        try await embedder.vectors(for: candidates.map(\.cleanedTitle))
    }

    // MARK: - Actions - Naming

    /// A name for each group from its first three cleaned titles in sidebar
    /// order and its three keywords, starting with a capital. The model names
    /// a group "None" when it finds no topic, which leaves it loose.
    func named(
        _ groups: [[TidyTabCandidate]], meaning groupVectors: [[Float]], among candidates: [TidyTabCandidate]
    ) async throws -> (groups: [[TidyTabCandidate]], names: [String]) {
        let order = Dictionary(uniqueKeysWithValues: candidates.enumerated().map { ($1.tabID, $0) })
        let inSidebarOrder = groups.map { group in
            group.sorted { order[$0.tabID, default: 0] < order[$1.tabID, default: 0] }
        }
        let keywords = Self.keywords(for: inSidebarOrder, among: candidates)
        var names: [String] = []
        for (group, groupKeywords) in zip(inSidebarOrder, keywords) {
            let titles = group.prefix(Self.promptTitleCount).map(\.cleanedTitle).joined(separator: "\n")
            let name = try await namer.name(
                for: "Topic from keywords: \(groupKeywords.joined(separator: ",")). titles: \n\(titles)")
            names.append(name.prefix(1).uppercased() + name.dropFirst())
        }
        return (groups, names)
    }

    /// Each group's three most distinctive words, by class TF-IDF: each
    /// group's titles form one document, and the tabs in no group one more.
    private static func keywords(
        for groups: [[TidyTabCandidate]], among candidates: [TidyTabCandidate]
    ) -> [[String]] {
        let grouped = Set(groups.flatMap { $0.map(\.tabID) })
        let documents =
            groups.map { group in WordCounts(group.prefix(keywordTitleCount).flatMap { words(in: $0.pageTitle) }) }
            + [WordCounts(candidates.filter { !grouped.contains($0.tabID) }.flatMap { words(in: $0.pageTitle) })]
        let averageLength = Double(documents.reduce(0) { $0 + $1.total }) / Double(documents.count)
        var corpusCounts: [String: Int] = [:]
        for document in documents {
            for (word, count) in document.counts { corpusCounts[word, default: 0] += count }
        }
        return documents.dropLast().map { document in
            let total = Double(max(document.total, 1))
            func score(_ word: String) -> Double {
                Double(document.counts[word] ?? 0) / total
                    * log(1 + averageLength / Double(corpusCounts[word] ?? 1))
            }
            return document.order.indices.sorted { first, second in
                let (firstScore, secondScore) = (score(document.order[first]), score(document.order[second]))
                return firstScore != secondScore ? firstScore > secondScore : first < second
            }.prefix(keywordCount).map { document.order[$0] }
        }
    }

    private static func words(in title: String) -> [String] {
        let lowered = title.lowercased()
        return word.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)).compactMap { match in
            guard let range = Range(match.range, in: lowered) else { return nil }
            let found = String(lowered[range])
            return found.count > 2 && !stopWords.contains(found) ? found : nil
        }
    }
}
