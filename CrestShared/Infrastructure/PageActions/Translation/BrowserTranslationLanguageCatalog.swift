import Foundation
import Observation
import Translation

/// Apple exposes downloaded pairs, not an inventory of individual downloads.
/// Only positive installed results are offered for automatic translation.
@Observable @MainActor
final class BrowserTranslationLanguageCatalog {
    struct Pair: Hashable, Sendable {
        let source: String
        let target: String
    }

    private(set) var installedPairs: Set<Pair> = []
    private(set) var isRefreshing = false
    private(set) var hasChecked = false

    var installedIDs: [String] {
        Set(installedPairs.flatMap { [$0.source, $0.target] }).sorted {
            Self.name($0).localizedStandardCompare(Self.name($1)) == .orderedAscending
        }
    }

    func targets(for source: String) -> [String] {
        installedIDs.filter { installedPairs.contains(Pair(source: source, target: $0)) }
    }

    static func name(_ id: String) -> String { Locale.current.localizedString(forIdentifier: id) ?? id }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let installed = await Self.loadInstalledPairs()
        guard !Task.isCancelled else { return }
        installedPairs = installed
        hasChecked = true
    }

    private nonisolated static func loadInstalledPairs() async -> Set<Pair> {
        let supported = await BrowserTranslationPreference.languageAvailability().supportedLanguages
        let languages = supported.isEmpty ? await LanguageAvailability().supportedLanguages : supported
        let ids = languages.map(\.minimalIdentifier)
        let candidates = ids.flatMap { source in
            ids.filter { !BrowserAutomaticTranslationRules.matches(source, $0) }
                .map { Pair(source: source, target: $0) }
        }
        return await check(candidates)
    }

    private nonisolated static func check(_ pairs: [Pair]) async -> Set<Pair> {
        await withTaskGroup(of: Pair?.self, returning: Set<Pair>.self) { group in
            var iterator = pairs.makeIterator()
            func enqueue(_ pair: Pair) {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    let status = await BrowserTranslationPreference.languageAvailability().status(
                        from: .init(identifier: pair.source), to: .init(identifier: pair.target))
                    return status == .installed ? pair : nil
                }
            }
            for _ in 0..<4 { if let pair = iterator.next() { enqueue(pair) } }
            var installed: Set<Pair> = []
            for await pair in group {
                if let pair { installed.insert(pair) }
                if !Task.isCancelled, let next = iterator.next() { enqueue(next) }
            }
            return installed
        }
    }
}
