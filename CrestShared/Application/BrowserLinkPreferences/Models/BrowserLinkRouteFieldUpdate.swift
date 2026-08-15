enum BrowserLinkRouteFieldUpdate: Equatable, Sendable {
    case isEnabled(Bool)
    case match(BrowserLinkRouteMatch)
    case pattern(String)
    case destinationSpaceID(SpaceID)

    func apply(to route: inout BrowserLinkRoute) {
        switch self {
        case .isEnabled(let isEnabled):
            route.isEnabled = isEnabled
        case .match(let match):
            route.match = match
        case .pattern(let pattern):
            route.pattern = pattern
        case .destinationSpaceID(let spaceID):
            route.destinationSpaceID = spaceID
        }
    }
}
