@MainActor
protocol BrowserCloudSyncWorkflowGateway: BrowserCloudSyncModelGateway, AnyObject {
    var hasDisposableCloudSyncSeed: Bool { get }
    var cloudSyncLocalRecordCount: Int { get }
    var cloudSyncPendingRecordCount: Int { get }
    var cloudSyncLocalErrorDescription: String? { get }

    func replaceLocalWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws
    func replaceDisposableSeedWithCloud(_ remoteRecords: [BrowserSyncRecord]) throws
    func prepareToOverwriteCloud(with remoteRecords: [BrowserSyncRecord]) throws
}
