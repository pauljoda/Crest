import Foundation
import WebKit

/// Compiles the core's bundled rule lists once into this launch's own store.
@MainActor
final class BrowserContentRuleListProvider: BrowserContentRuleListProviding {
    // MARK: - Variables

    private let core: CrestCore
    private let ruleListStore: Result<WKContentRuleListStore, Error>
    private let compiler: any BrowserContentRuleListCompiling
    private let temporaryDirectory: URL?
    private let updates: BrowserContentRuleListUpdates?
    private var currentIdentifier: String?
    private var currentVersion: Int64 = 0
    private var preparation: Task<[WKContentRuleList], Error>?
    private var cachedRuleLists: [WKContentRuleList]?

    // MARK: - Initializers

    init(
        core: CrestCore,
        ruleListStore: WKContentRuleListStore = .default(),
        compiler: any BrowserContentRuleListCompiling = BrowserContentRuleListCompilerAdapter(),
        updates: BrowserContentRuleListUpdates? = nil
    ) {
        self.core = core
        self.updates = updates
        self.ruleListStore = .success(ruleListStore)
        self.compiler = compiler
        temporaryDirectory = nil
    }

    private init(core: CrestCore, directory: URL, removesDirectoryOnDeinit: Bool) {
        self.core = core
        updates = nil
        compiler = BrowserContentRuleListCompilerAdapter()
        temporaryDirectory = removesDirectoryOnDeinit ? directory : nil
        ruleListStore = Result {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let store = WKContentRuleListStore(url: directory) else {
                throw BrowserContentBlockingError.ruleListUnavailable
            }
            return store
        }
    }

    private init(previewCore: CrestCore) {
        core = previewCore
        updates = nil
        compiler = BrowserContentRuleListCompilerAdapter()
        ruleListStore = .failure(BrowserContentBlockingError.ruleListUnavailable)
        temporaryDirectory = nil
        cachedRuleLists = []
    }

    deinit {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    // MARK: - Actions - Launch

    /// Named profiles cache rules beside their own session. Anonymous isolated
    /// launches use a temporary store that disappears with the provider.
    static func forLaunch(
        core: CrestCore,
        launchEnvironment: BrowserLaunchEnvironment = .current
    ) -> BrowserContentRuleListProvider {
        // Canvas previews do not compile or open WebKit stores. Isolated app
        // and test launches still enforce the complete bundled protection.
        if launchEnvironment.isSwiftUIPreviewRuntime {
            return BrowserContentRuleListProvider(previewCore: core)
        }
        guard launchEnvironment.requiresIsolation else {
            let cacheURL = core.storageDirectory?
                .appendingPathComponent("ContentRules", isDirectory: true)
                .appendingPathComponent("snapshot.json.gz")
            return BrowserContentRuleListProvider(
                core: core, updates: BrowserContentRuleListUpdates(cacheURL: cacheURL))
        }
        if let directory = core.storageDirectory {
            return BrowserContentRuleListProvider(
                core: core, directory: directory.appendingPathComponent("ContentRules", isDirectory: true),
                removesDirectoryOnDeinit: false)
        }
        return BrowserContentRuleListProvider(
            core: core,
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "crest-content-rules-\(UUID().uuidString)", isDirectory: true),
            removesDirectoryOnDeinit: true)
    }

    // MARK: - Actions - Rules

    func balancedRuleLists() async throws -> [WKContentRuleList] {
        if let cachedRuleLists { return cachedRuleLists }
        if let preparation { return try await preparation.value }
        let task = Task { try await loadInitialRules() }
        preparation = task
        defer { preparation = nil }
        return try await task.value
    }

    func refreshedRuleLists() async throws -> [WKContentRuleList] {
        let previous = try await balancedRuleLists()
        guard let updates, let snapshot = try await updates.downloadIfDue() else { return previous }
        let rules = try core.query(BalancedProtectionRules(snapshot: snapshot))
        guard rules.version >= currentVersion else { return previous }
        if rules.identifier != currentIdentifier {
            let lists = try await compile(rules)
            try Task.checkCancellation()
            // Keep the last working rules if compilation or atomic cache write fails.
            try updates.accept(snapshot)
            cachedRuleLists = lists
            currentIdentifier = rules.identifier
            currentVersion = rules.version
            await removeSupersededRules()
        } else {
            try updates.accept(snapshot)
        }
        return cachedRuleLists ?? previous
    }

    private func loadInitialRules() async throws -> [WKContentRuleList] {
        let bundled = try core.query(BalancedProtectionRules(snapshot: nil))
        if let snapshot = updates?.cachedSnapshot(),
            let cached = try? core.query(BalancedProtectionRules(snapshot: snapshot)),
            cached.version >= bundled.version,
            let lists = try? await compile(cached)
        {
            currentIdentifier = cached.identifier
            currentVersion = cached.version
            cachedRuleLists = lists
            await removeSupersededRules()
            return lists
        }
        updates?.discardCachedSnapshot()
        let lists = try await compile(bundled)
        currentIdentifier = bundled.identifier
        currentVersion = bundled.version
        cachedRuleLists = lists
        await removeSupersededRules()
        return lists
    }

    private func compile(_ rules: ContentRuleList) async throws -> [WKContentRuleList] {
        try await compiler.compile(
            identifiers: [rules.identifier], sources: [rules.source], store: ruleListStore.get())
    }

    private func removeSupersededRules() async {
        guard let store = try? ruleListStore.get() else { return }
        for identifier in await BrowserContentRuleListCompiler.availableIdentifiers(store: store)
        where identifier.hasPrefix("com.pauldavis.crest.content-blocking.balanced.") && identifier != currentIdentifier
        {
            await BrowserContentRuleListCompiler.remove(identifier: identifier, store: store)
        }
    }
}
