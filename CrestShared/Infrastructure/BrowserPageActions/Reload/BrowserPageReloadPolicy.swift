enum BrowserPageReloadPolicy {
    static func action(
        isLoading: Bool,
        mode: BrowserPageReloadMode
    ) -> BrowserPageReloadAction {
        switch mode {
        case .standard:
            isLoading ? .stop : .reload
        case .fromOrigin:
            .reloadFromOrigin
        }
    }
}
