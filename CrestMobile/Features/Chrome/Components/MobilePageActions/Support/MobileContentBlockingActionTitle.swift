import Foundation

enum MobileContentBlockingActionTitle {
    static func resolve(
        policy: BrowserContentBlockingPolicy?
    ) -> LocalizedStringResource {
        switch policy {
        case .balanced:
            "Turn Off Content Blocking in This Space"
        case .off, nil:
            "Turn On Balanced Content Blocking in This Space"
        }
    }
}
