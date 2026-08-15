enum BrowserReaderModeState: Equatable, Sendable {
    case unavailable
    case checking
    case available
    case activating
    case active

    var canToggle: Bool {
        switch self {
        case .available, .active:
            true
        case .unavailable, .checking, .activating:
            false
        }
    }

    var isActive: Bool {
        self == .active
    }

    /// Whether reader mode is known to be offerable for the current page. A
    /// state that has not been probed yet reports `false` rather than forcing a
    /// probe, so a caller reading this never blocks on the page.
    var isAvailable: Bool {
        switch self {
        case .available, .activating, .active:
            true
        case .unavailable, .checking:
            false
        }
    }
}
