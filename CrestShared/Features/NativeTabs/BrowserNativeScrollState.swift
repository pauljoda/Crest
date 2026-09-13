import SwiftUI

/// Stores the user's position independently of a ScrollView's mounted lifetime.
@MainActor
final class BrowserNativeScrollState {
    var offset: CGFloat = 0
    var listRow: Int?
    var listRowOffset: CGFloat = 0
}

private struct BrowserNativeScrollRestoration: ViewModifier {
    let state: BrowserNativeScrollState
    @State private var position: ScrollPosition
    @State private var currentOffset: CGFloat

    init(state: BrowserNativeScrollState) {
        self.state = state
        _position = State(initialValue: ScrollPosition(y: state.offset))
        _currentOffset = State(initialValue: state.offset)
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                withTransaction(Transaction(animation: nil)) { position.scrollTo(y: state.offset) }
            }
            .onDisappear { state.offset = currentOffset }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                max(0, geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, offset in
                currentOffset = offset
                // Capture accessibility and programmatic scrolling too. Commit
                // on disappearance so initial layout cannot erase a saved offset.
            }
    }
}

extension View {
    func browserNativeScrollState(_ state: BrowserNativeScrollState) -> some View {
        modifier(BrowserNativeScrollRestoration(state: state))
            .id(ObjectIdentifier(state))
    }
}
