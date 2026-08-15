import CloudKit

actor CloudKitBrowserCloudSyncRemoteService: BrowserCloudSyncRemoteService {
    private let configuration: BrowserCloudSyncConfiguration
    private var container: CKContainer?
    private var database: CKDatabase?

    init(configuration: BrowserCloudSyncConfiguration) {
        self.configuration = configuration
    }

    func hasRequiredEntitlement() -> Bool {
        BrowserPlatformCloudContainerEntitlementPolicy.currentProcessContainsContainer(
            configuration.containerIdentifier
        )
    }

    func accountState() async throws -> BrowserCloudAccountState {
        let container = cloudContainer()
        database = container.privateCloudDatabase
        let status = try await container.accountStatus()
        return Self.accountState(for: status)
    }

    func loadSnapshot() async throws -> [BrowserSyncRecord] {
        let database = database ?? cloudContainer().privateCloudDatabase
        self.database = database
        do {
            return try await BrowserCloudSnapshotLoader(database: database).load()
        } catch let error as CKError where error.code == .zoneNotFound {
            return []
        }
    }

    nonisolated func message(for error: any Error) -> String {
        if let syncError = error as? BrowserSyncError,
            case .remoteChangeNotApplied = syncError
        {
            return "Crest couldn’t apply the latest changes from iCloud."
        }
        guard let cloudError = error as? CKError else {
            return String(describing: error)
        }
        switch cloudError.code {
        case .notAuthenticated:
            return "Sign in to iCloud to sync Crest."
        case .networkUnavailable, .networkFailure:
            return "Crest can’t reach iCloud right now."
        case .quotaExceeded:
            return "Your iCloud storage is full."
        case .permissionFailure:
            return "This build is not permitted to use Crest’s iCloud container."
        default:
            return cloudError.localizedDescription
        }
    }

    private func cloudContainer() -> CKContainer {
        if let container { return container }
        let result = CKContainer(identifier: configuration.containerIdentifier)
        container = result
        return result
    }

    private static func accountState(for status: CKAccountStatus) -> BrowserCloudAccountState {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }
}
