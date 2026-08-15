import CoreGraphics

enum MobileRegularWindowLayout: Equatable, Sendable {
    case sideBySide(sidebarWidth: CGFloat)
    case overlay(sidebarWidth: CGFloat)

    var sidebarWidth: CGFloat {
        switch self {
        case .sideBySide(let sidebarWidth), .overlay(let sidebarWidth):
            sidebarWidth
        }
    }

    var reservesSidebarWidth: Bool {
        switch self {
        case .sideBySide: true
        case .overlay: false
        }
    }
}
