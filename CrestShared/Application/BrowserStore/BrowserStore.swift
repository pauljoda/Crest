import Foundation
import Observation

@Observable
@MainActor
final class BrowserStore {
    var session: BrowserSession {
        didSet {
            sessionRevision &+= 1
            tabSelectionHistory.reconcile(session: session)
        }
    }
    private(set) var sessionRevision = 0
    var localSyncErrorDescription: String?
    let browsingMode: BrowserBrowsingMode
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()
    let family: BrowserStoreFamily
    @ObservationIgnored let persistence: any BrowserSessionPersisting
    @ObservationIgnored let credentialVault: any CredentialVault
    @ObservationIgnored let syncCoordinator: BrowserSyncCoordinator?
    @ObservationIgnored let syncCoalescingDelay: Duration
    @ObservationIgnored var cloudSyncChangeHandler: (@Sendable () -> Void)?
    @ObservationIgnored var syncStageGeneration = 0
    @ObservationIgnored var syncStageTask: Task<Void, Never>?
    @ObservationIgnored var credentialSaveOperations: [BrowserCredentialSaveKey: BrowserCredentialSaveOperation] = [:]
    @ObservationIgnored var tabSelectionHistory: BrowserTabSelectionHistory

    var deletingSpaceIDs: Set<SpaceID> { family.deletingSpaceIDs }
    var selectedSpace: BrowserSpace? {
        guard !deletingSpaceIDs.contains(session.selectedSpaceID) else {
            return nil
        }
        return session.selectedSpace
    }
    var selectedTab: BrowserTab? {
        guard selectedSpace != nil else { return nil }
        return session.selectedTab
    }
    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
    var pendingSyncRecordCount: Int {
        guard !session.hasDisposableSeedState else { return 0 }
        return syncCoordinator?.journal.pendingRecordIDs.count ?? 0
    }
    var localSyncCoordinatorStatus: BrowserSyncCoordinatorStatus? { syncCoordinator?.status }

    convenience init(
        session: BrowserSession,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault = InMemoryCredentialVault(),
        syncCoordinator: BrowserSyncCoordinator? = nil,
        syncCoalescingDelay: Duration = .milliseconds(150),
        browsingMode: BrowserBrowsingMode = .standard
    ) {
        self.init(
            session: session,
            persistence: persistence,
            credentialVault: credentialVault,
            syncCoordinator: syncCoordinator,
            syncCoalescingDelay: syncCoalescingDelay,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(session: session)
        )
    }

    init(
        session: BrowserSession,
        persistence: any BrowserSessionPersisting,
        credentialVault: any CredentialVault,
        syncCoordinator: BrowserSyncCoordinator?,
        syncCoalescingDelay: Duration,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        cloudSyncChangeHandler: (@Sendable () -> Void)? = nil
    ) {
        self.session = session
        tabSelectionHistory = BrowserTabSelectionHistory(session: session)
        self.persistence = persistence
        self.credentialVault = credentialVault
        self.syncCoordinator = syncCoordinator
        self.syncCoalescingDelay = syncCoalescingDelay
        self.browsingMode = browsingMode
        self.family = family
        self.cloudSyncChangeHandler = cloudSyncChangeHandler
        localSyncErrorDescription = nil
        family.register(self)
    }
}
