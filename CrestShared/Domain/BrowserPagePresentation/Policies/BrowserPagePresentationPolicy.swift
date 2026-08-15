enum BrowserPagePresentationPolicy {
    static func resolve(
        _ input: BrowserPagePresentationInput
    ) -> BrowserPagePresentation {
        switch input.selection {
        case .none:
            return .noSelection
        case .startPage:
            return .startPage
        case .webPage:
            guard input.hasActivePage else {
                return switch input.unloadedBehavior {
                case .remainUnloaded:
                    .unloaded
                case .restoreAutomatically:
                    .automaticRestore
                }
            }

            if input.hasNavigationFailure {
                return .navigationFailure
            }
            if input.hasProcessFailure {
                return .processFailure
            }
            return .livePage
        }
    }
}
