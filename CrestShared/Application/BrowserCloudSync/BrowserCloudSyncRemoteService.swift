protocol BrowserCloudSyncRemoteService: Sendable {
    func hasRequiredEntitlement() async -> Bool
    func accountState() async throws -> BrowserCloudAccountState
    func loadSnapshot() async throws -> [BrowserSyncRecord]
    nonisolated func message(for error: any Error) -> String
}
