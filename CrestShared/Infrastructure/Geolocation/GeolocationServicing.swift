@MainActor
protocol BrowserGeolocationServicing: AnyObject {
    func currentAuthorization() -> BrowserGeolocationSystemAuthorization
    func requestAuthorization() async -> BrowserGeolocationSystemAuthorization
    func requestCurrentPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    )
    func startWatchingPosition(
        identifier: String,
        options: BrowserGeolocationRequestOptions,
        receive: @escaping @MainActor (Result<BrowserGeolocationPosition, BrowserGeolocationError>) -> Void
    )
    func cancel(identifier: String)
    func cancelAll()
}
