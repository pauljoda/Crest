import Foundation
import WebKit

/// Compiles the core's content rule lists into a WebKit rule-list store and
/// hands out the compiled lists. A list the store already holds under its
/// identifier is never compiled again, so a launch compiles only what changed,
/// and the lists Crest compiled that no set names any more are removed.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    // MARK: - Variables

    /// The identifiers of the lists Crest compiles, current and past, which
    /// tell its own lists apart from another client's in a shared store.
    private static let ownedPrefixes = ["com.pauldavis.crest.content-filter.", "com.pauldavis.crest.content-blocking."]

    private let core: CrestCore
    private let ruleListStore: WKContentRuleListStore?
    private let compiler: any BrowserContentRuleListCompiling
    private var cached: (set: ContentRuleListSet, lists: [WKContentRuleList])?

    // MARK: - Initializers

    init(
        core: CrestCore,
        ruleListStore: WKContentRuleListStore? = .default(),
        compiler: any BrowserContentRuleListCompiling =
            BrowserContentRuleListCompilerAdapter()
    ) {
        self.core = core
        self.ruleListStore = ruleListStore
        self.compiler = compiler
    }

    /// The provider a launch uses: an isolated launch compiles into a store of
    /// its own under the temporary folder, which no other launch reads.
    static func forLaunch(
        core: CrestCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        guard launchEnvironment.requiresIsolation else { return BrowserContentRuleListProvider(core: core) }
        let process = ProcessInfo.processInfo.processIdentifier
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrestIsolatedContentRules-\(process)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return BrowserContentRuleListProvider(core: core, ruleListStore: WKContentRuleListStore(url: folder))
    }

    // MARK: - Actions - Compiling

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        guard let ruleListStore else { return [] }
        let set: ContentRuleListSet
        if let published = core.state.contentRuleLists {
            set = published
        } else {
            // The core starts converting on the first ask and announces the
            // rules once they are ready; until then it answers what it has.
            guard let answered = try? core.query(ContentRuleLists()) else { return [] }
            if core.state.contentRuleLists == nil { core.state.contentRuleLists = answered }
            set = core.state.contentRuleLists ?? answered
        }
        if let cached, cached.set == set { return cached.lists }

        let lists = try await compiler.compile(
            identifiers: set.identifiers,
            source: { [core] identifier in try core.query(ContentRuleListSource(identifier: identifier)).source },
            store: ruleListStore
        )
        cached = (set, lists)
        await removeStaleLists(keeping: Set(set.identifiers), from: ruleListStore)
        return lists
    }

    /// Removes the lists Crest compiled earlier that `current` no longer names.
    private func removeStaleLists(keeping current: Set<String>, from store: WKContentRuleListStore) async {
        for identifier in await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
        where !current.contains(identifier) && Self.ownedPrefixes.contains(where: identifier.hasPrefix) {
            await BrowserContentRuleListCompiler.remove(identifier: identifier, store: store)
        }
    }
}
