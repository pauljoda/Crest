import SwiftUI

extension View {
    func browserSpaceSwipeGesture(
        _ handleSwipe: @escaping (BrowserSpaceSwipeDirection) -> Void
    ) -> some View {
        modifier(BrowserSpaceSwipeModifier(handleSwipe: handleSwipe))
    }
}
