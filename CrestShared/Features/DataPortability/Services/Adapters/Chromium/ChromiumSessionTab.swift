import Foundation

struct ChromiumSessionTab {
    var windowID: Int32?
    var visualIndex = Int.max
    var selectedNavigationIndex = 0
    var navigations: [Int: ChromiumSessionNavigation] = [:]
    var isPinned = false
    var lastActivatedAt: Date
}
