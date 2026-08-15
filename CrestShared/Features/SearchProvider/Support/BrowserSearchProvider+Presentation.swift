extension BrowserSearchProvider {
    var logoAssetName: String {
        switch self {
        case .google: "SearchProviderGoogle"
        case .duckDuckGo: "SearchProviderDuckDuckGo"
        case .bing: "SearchProviderBing"
        case .ecosia: "SearchProviderEcosia"
        case .brave: "SearchProviderBrave"
        }
    }
}
