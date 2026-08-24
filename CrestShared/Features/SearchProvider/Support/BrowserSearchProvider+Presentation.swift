extension BrowserSearchProvider {
    var logoAssetName: String? {
        switch builtIn {
        case .google: "SearchProviderGoogle"
        case .duckDuckGo: "SearchProviderDuckDuckGo"
        case .bing: "SearchProviderBing"
        case .ecosia: "SearchProviderEcosia"
        case .brave: "SearchProviderBrave"
        case nil: nil
        }
    }
}
