import Foundation

// MARK: - Types

/// Tidy ran before its models were downloaded and loaded.
struct TidyModelsUnavailable: Error {}

/// Groups a Space's loose open tabs under headers on this device. Nothing
/// leaves it.
///
/// The current `TidyMethod`'s models read each tab as a meaning vector,
/// `TidyTabGroups` clusters the vectors in milliseconds with no model call,
/// and the models then name the groups. Groups named for a kind of browsing
/// rather than a topic stay loose.
struct OnDeviceTabTidyingService {
    // MARK: - Static Variables

    /// Tidy is offered once the open section holds this many loose tabs.
    static let minimumLooseTabCount = 6

    /// Tabs are described in the background once the open section holds this
    /// many loose tabs, a little before Tidy is offered.
    static let minimumDescribedTabCount = 4

    /// Whether the person turned Tidy on and the models of the method this
    /// device runs now are loaded.
    @MainActor
    static var isReady: Bool {
        let downloads = TidyModelDownloads.shared
        return BrowserAppPreferenceStore.shared.offersTabTidying && downloads.models != nil
            && downloads.method == TidyMethod.current
    }

    /// Group names that are kinds of browsing or catch-alls rather than topics,
    /// whose groups stay loose.
    private static let looseGroupName = try! NSRegularExpression(
        pattern:
            "^(none|adult content|e-?mails?|mail|inbox|email inbox|calendars?|chat|messages?|messaging"
            + "|communication|social( media)?|music|videos?|news|.* news|general news|weather|sports?"
            + "|misc(ellaneous)?|others?|general|various|uncategori[sz]ed|browsing|websites?)$",
        options: [.caseInsensitive])

    /// The longest header name Tidy proposes, well inside the core's limit.
    private static let maximumHeaderNameLength = 40

    // MARK: - Actions - Candidates

    /// The Space's open tabs outside every folder and split that show a web
    /// page, in sidebar order.
    @MainActor
    static func candidates(in space: SpaceModel) -> [TidyTabCandidate] {
        looseWebPageTabs(in: space).compactMap { tab, address in
            TidyTabCandidate(tabID: tab.id, pageTitle: tab.title, address: address)
        }
    }

    /// `proposals` without the tabs that are no longer loose web pages in
    /// `space`, or whose title or address changed since `snapshot` was read,
    /// and without the headers left holding fewer than two tabs.
    @MainActor
    static func proposals(
        _ proposals: [TidyFolderProposal], unchangedSince snapshot: [TidyTabCandidate], in space: SpaceModel
    ) -> [TidyFolderProposal] {
        let current = Dictionary(uniqueKeysWithValues: candidates(in: space).map { ($0.tabID, $0) })
        let unchanged = Set(snapshot.filter { current[$0.tabID] == $0 }.map(\.tabID))
        return proposals.compactMap { proposal in
            let tabIDs = proposal.tabIDs.filter(unchanged.contains)
            return tabIDs.count >= 2 ? TidyFolderProposal(folderTitle: proposal.folderTitle, tabIDs: tabIDs) : nil
        }
    }

    /// How many tabs `candidates(in:)` would return, read without their
    /// titles, so a page changing its title doesn't redraw whoever asks.
    @MainActor
    static func candidateCount(in space: SpaceModel) -> Int {
        looseWebPageTabs(in: space).count
    }

    @MainActor
    private static func looseWebPageTabs(in space: SpaceModel) -> [(tab: TabStateModel, address: URL)] {
        space.tabs.models.compactMap { tab in
            guard tab.placement == .current, tab.folderID == nil, tab.splitGroupID == nil,
                let address = tab.url.flatMap(URL.init(string:)), address.host() != nil
            else { return nil }
            return (tab, address)
        }
    }

    // MARK: - Actions - Warming

    /// Loads what a likely Tidy will need first.
    @MainActor
    static func prewarm() {
        TidyModelDownloads.shared.models?.prewarm()
    }

    // MARK: - Actions - Headers

    /// The headers for `candidates`, each holding two or more of them in
    /// sidebar order. Every other tab stays loose. Background descriptions
    /// pause meanwhile. Throws `TidyModelsUnavailable` before the models are
    /// loaded, or the models' error when naming fails.
    @MainActor
    func headers(for candidates: [TidyTabCandidate]) async throws -> [TidyFolderProposal] {
        let downloads = TidyModelDownloads.shared
        guard let models = downloads.models, let method = downloads.method else { throw TidyModelsUnavailable() }
        return try await TidyTabDescriptions.shared.pausing {
            // Copies of one page group as one, so they never make a header of
            // their own, and join their page's header together.
            let copiesByDescription = Dictionary(grouping: candidates, by: \.modelDescription)
            var seenDescriptions: Set<String> = []
            let groupable = candidates.filter {
                !$0.isLooseSiteFrontPage && seenDescriptions.insert($0.modelDescription).inserted
            }
            let vectors = try await models.vectors(for: groupable)
            let groupedIndices = TidyTabGroups(
                vectors: vectors, centersVectors: method.centersVectors, cutHeights: method.cutHeights
            ).groups()
                .filter { !Self.isOnlyFrontPagesOfDifferentSites($0.map { groupable[$0] }) }
            guard !groupedIndices.isEmpty else { return [] }
            let groupVectors = groupedIndices.map { members in
                TidyTabEmbedder.unitLength(
                    members.map { vectors[$0] }.reduce(into: [Float](repeating: 0, count: vectors[0].count)) {
                        for index in $0.indices { $0[index] += $1[index] }
                    })
            }
            let named = try await models.named(
                groupedIndices.map { $0.map { groupable[$0] } }, meaning: groupVectors, among: candidates)
            return Self.proposals(
                groups: named.groups, names: named.names, copies: copiesByDescription, inOrderOf: candidates)
        }
    }

    /// News, social and app home pages pair up by kind, not by anything the
    /// person is working on.
    private static func isOnlyFrontPagesOfDifferentSites(_ group: [TidyTabCandidate]) -> Bool {
        group.allSatisfy { $0.pathDepth <= 1 } && Set(group.map(\.host)).count == group.count
    }

    /// `name` cut at a word to `maximumHeaderNameLength`, or at that length
    /// when no space is in reach. The models write a few words, but not always.
    private static func fittedName(_ name: String) -> String {
        guard name.count > maximumHeaderNameLength else { return name }
        let cut = name.prefix(maximumHeaderNameLength)
        guard let space = cut.lastIndex(of: " ") else { return String(cut) }
        return String(cut[..<space])
    }

    /// Whether `name` is a topic a header can carry, rather than empty, a kind
    /// of browsing or a catch-all.
    static func isTopic(_ name: String) -> Bool {
        name.contains(where: \.isLetter)
            && looseGroupName.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) == nil
    }

    /// A header for each group named for a topic, with its tabs and those
    /// tabs' `copies` in sidebar order. The core files groups named alike
    /// under one header.
    private static func proposals(
        groups: [[TidyTabCandidate]], names: [String], copies: [String: [TidyTabCandidate]],
        inOrderOf candidates: [TidyTabCandidate]
    ) -> [TidyFolderProposal] {
        zip(groups, names.map(fittedName)).compactMap { group, name in
            guard isTopic(name) else { return nil }
            let members = Set(group.flatMap { copies[$0.modelDescription] ?? [$0] }.map(\.tabID))
            return TidyFolderProposal(folderTitle: name, tabIDs: candidates.map(\.tabID).filter(members.contains))
        }
    }
}
