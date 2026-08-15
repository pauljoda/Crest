import SwiftUI

extension View {
    func browserOnMiddleClick(
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        gesture(BrowserMiddleClickGesture(perform: perform))
    }
}
