enum BrowserExtensionStatus: Equatable {
    case on
    case off
    case needsAttention

    init(_ summary: BrowserExtensionSummary) {
        switch (
            summary.isEnabled,
            !summary.needsAttention,
            summary.isLoaded
        ) {
        case (false, _, _):
            self = .off
        case (true, false, _), (true, true, false):
            self = .needsAttention
        case (true, true, true):
            self = .on
        }
    }

}
