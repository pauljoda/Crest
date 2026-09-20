/// Page search options shared by native engine adapters.
struct BrowserFindConfiguration {
    var backwards = false
    var caseSensitive = false
    var wraps = true
}

@MainActor
protocol BrowserFindExecuting: AnyObject {
    func performFind(
        _ query: String,
        configuration: BrowserFindConfiguration,
        completion: @escaping @MainActor (Bool) -> Void
    )
}
