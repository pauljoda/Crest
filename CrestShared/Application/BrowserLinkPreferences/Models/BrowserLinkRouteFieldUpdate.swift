/// The one route field a settings edit changes; the core applies it.
enum BrowserLinkRouteFieldUpdate: Equatable, Sendable {
    case isEnabled(Bool)
    case match(BrowserLinkRouteMatch)
    case pattern(String)
    case destinationSpaceID(SpaceID)
}
