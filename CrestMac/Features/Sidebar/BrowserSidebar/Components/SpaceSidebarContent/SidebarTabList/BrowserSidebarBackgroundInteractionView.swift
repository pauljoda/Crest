import SwiftUI

struct BrowserSidebarBackgroundInteractionView: View {
    let editSpace: () -> Void
    let createSpace: () -> Void

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture())
            .contextMenu {
                ForEach(
                    BrowserSidebarBackgroundInteractionPolicy.actions,
                    id: \.self
                ) { action in
                    Button(action.title, systemImage: action.systemImage) {
                        perform(action)
                    }
                }
            }
            .accessibilityLabel("Sidebar background")
            .accessibilityHint("Drag to move the window or open Space actions")
    }

    private func perform(_ action: BrowserSidebarBackgroundAction) {
        switch action {
        case .editSpace:
            editSpace()
        case .newSpace:
            createSpace()
        }
    }
}
