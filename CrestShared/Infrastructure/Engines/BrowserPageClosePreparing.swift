/// An optional engine service for confirming a batch before changing the
/// session. Approval leaves every page alive; the accepted session change
/// determines which runtimes the native pool subsequently releases.
@MainActor
protocol BrowserPageClosePreparing: AnyObject {
    func prepareToClose(
        _ pages: [any BrowserPageEngine],
        completion: @escaping @MainActor (Bool) -> Void
    )
}
