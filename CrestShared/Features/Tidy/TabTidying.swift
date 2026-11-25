import Foundation
import FoundationModels
import Observation

// MARK: - Types

/// Tidy ran before its word-vector table was downloaded and loaded, or where
/// Apple's on-device model cannot run.
struct TidyUnavailable: Error {}

/// Tidy on this device: whether the person turned it on and it can run, the
/// word table and the keyphrases it keeps meanwhile, and the topics it finds
/// among a Space's loose open tabs, which the core files into Groups.
///
/// It follows the setting for the life of the app, whatever the windows show.
/// Turning Tidy off stops describing tabs, forgets every keyphrase and deletes
/// the word table. While Apple Intelligence is unavailable Tidy only pauses:
/// describing stops, and the table and the keyphrases stay until the person
/// turns Tidy off. A private window's tabs are never described or tidied.
@MainActor
@Observable
final class TabTidying {
    // MARK: - Static Variables

    static let shared = TabTidying()

    /// Tidy is offered once a Space's open tabs hold this many loose web pages.
    static let minimumLooseTabCount = 6

    /// Tabs are described in the background once a Space holds this many
    /// loose web pages, a little before Tidy is offered.
    static let minimumDescribedTabCount = 4

    /// The most loose tabs one Tidy sorts, the first in the sidebar, which
    /// keeps a Space of hundreds quick to tidy.
    static let maximumTidiedTabCount = 200

    /// Whether this device can run Apple's on-device model now: Apple
    /// Intelligence is on and its model is ready.
    static var isModelAvailable: Bool {
        guard #available(macOS 26, *) else { return false }
        return SystemLanguageModel.default.isAvailable
    }

    // MARK: - Variables

    let wordTable: TidyWordTable
    private let descriptions = TidyTabDescriptions()
    @ObservationIgnored private var preferences: BrowserAppPreferenceStore?

    /// Whether the person turned Tidy on.
    var isOn: Bool { (preferences ?? .shared).offersTabTidying }

    /// Whether Tidy is on, the on-device model can run, and the word table is
    /// loaded.
    var isReady: Bool { isOn && Self.isModelAvailable && wordTable.embedder != nil }

    /// The Spaces a Tidy is under way in.
    private(set) var tidyingSpaceIDs: Set<UUID> = []

    /// The Spaces whose last Tidy failed, for a few seconds after, which the
    /// Tidy control says.
    private(set) var failedSpaceIDs: Set<UUID> = []

    // MARK: - Initializers

    init(wordTable: TidyWordTable = TidyWordTable()) {
        self.wordTable = wordTable
    }

    // MARK: - Actions - Following the setting

    /// Keeps the word table and the keyphrases in step with `preferences` and
    /// with Apple Intelligence from now on. Called once, at launch.
    func follow(_ preferences: BrowserAppPreferenceStore) {
        guard self.preferences == nil else { return }
        self.preferences = preferences
        keepInStep()
    }

    /// Applies the setting and the model's availability now, and again
    /// whenever either changes.
    private func keepInStep() {
        let (isOn, canRun) = withObservationTracking {
            (self.isOn, Self.isModelAvailable)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.keepInStep() }
        }
        if !isOn {
            descriptions.forgetAll()
            wordTable.remove()
        } else if canRun {
            wordTable.load()
        } else {
            descriptions.stopDescribing()
        }
    }

    // MARK: - Actions - Candidates

    /// The loose web pages of `space` Tidy may sort, in sidebar order: its
    /// open tabs outside every folder, Group and split that show a page with
    /// a host. None in a private window.
    static func candidates(in space: SpaceModel, of browser: BrowserStore) -> [TidyTabCandidate] {
        looseWebPageTabs(in: space, of: browser).compactMap { tab, address in
            TidyTabCandidate(tabID: tab.id, pageTitle: tab.title, address: address)
        }
    }

    /// How many tabs `candidates(in:of:)` would answer, read without their
    /// titles, so a page changing its title doesn't redraw whoever asks.
    static func candidateCount(in space: SpaceModel, of browser: BrowserStore) -> Int {
        looseWebPageTabs(in: space, of: browser).count
    }

    private static func looseWebPageTabs(
        in space: SpaceModel, of browser: BrowserStore
    ) -> [(tab: TabStateModel, address: URL)] {
        guard !browser.isPrivateBrowsing else { return [] }
        return space.tabs.models.compactMap { tab in
            guard tab.placement == .current, tab.folderID == nil, tab.splitGroupID == nil,
                let address = tab.url.flatMap(URL.init(string:)), address.host() != nil
            else { return nil }
            return (tab, address)
        }
    }

    // MARK: - Actions - Describing

    /// Has the model describe `candidates` in the background while Tidy is
    /// on and can run, ahead of tabs asked for earlier.
    func describe(_ candidates: [TidyTabCandidate]) {
        guard isOn, Self.isModelAvailable, candidates.count >= Self.minimumDescribedTabCount else { return }
        descriptions.describe(candidates)
    }

    /// Forgets every keyphrase, which describe what the person browsed, as
    /// when history is cleared.
    func forgetDescriptions() {
        descriptions.forgetAll()
    }

    /// Loads the model ahead of a likely Tidy.
    func prewarm() {
        guard #available(macOS 26, *), isReady else { return }
        TidyTopicFinder.prewarm()
    }

    // MARK: - Actions - Tidying

    /// Runs `tidy` for the Space `spaceID` unless a Tidy is already under way
    /// there, and marks the Space failed for a few seconds when it throws.
    func run(in spaceID: UUID, _ tidy: @escaping @MainActor () async throws -> Void) {
        guard !tidyingSpaceIDs.contains(spaceID) else { return }
        tidyingSpaceIDs.insert(spaceID)
        failedSpaceIDs.remove(spaceID)
        Task {
            do {
                try await tidy()
                tidyingSpaceIDs.remove(spaceID)
            } catch {
                DiagnosticLog.tidy.error("Tidy couldn't sort tabs: \(TidyTabDescriptions.loggedName(of: error))")
                tidyingSpaceIDs.remove(spaceID)
                failedSpaceIDs.insert(spaceID)
                try? await Task.sleep(for: .seconds(4))
                failedSpaceIDs.remove(spaceID)
            }
        }
    }

    /// The topics among `candidates`, the first `maximumTidiedTabCount` of
    /// them, each holding two or more in sidebar order, with background
    /// descriptions paused meanwhile. Throws `TidyUnavailable` while Tidy
    /// isn't ready, or the model's error when naming fails.
    func topics(for candidates: [TidyTabCandidate]) async throws -> [TidyTopic] {
        guard #available(macOS 26, *), isReady, let embedder = wordTable.embedder else { throw TidyUnavailable() }
        let tidied = Array(candidates.prefix(Self.maximumTidiedTabCount))
        let written = tidied.compactMap { candidate in
            descriptions.keyphrases(for: candidate).map { (candidate.modelDescription, $0) }
        }
        let finder = TidyTopicFinder(
            embedder: embedder, keyphrases: Dictionary(written, uniquingKeysWith: { first, _ in first }))
        return try await descriptions.pausing { try await finder.topics(for: tidied) }
    }

    /// `topics` without the tabs that are no longer loose web pages in
    /// `space`, or whose title or address changed since `snapshot` was read,
    /// and without the topics left holding fewer than two tabs.
    static func topics(
        _ topics: [TidyTopic], unchangedSince snapshot: [TidyTabCandidate], in space: SpaceModel,
        of browser: BrowserStore
    ) -> [TidyTopic] {
        let current = Dictionary(
            candidates(in: space, of: browser).map { ($0.tabID, $0) }, uniquingKeysWith: { first, _ in first })
        let unchanged = Set(snapshot.filter { current[$0.tabID] == $0 }.map(\.tabID))
        return topics.compactMap { topic in
            let tabIDs = topic.tabIDs.filter(unchanged.contains)
            return tabIDs.count >= 2 ? TidyTopic(title: topic.title, tabIDs: tabIDs) : nil
        }
    }
}
