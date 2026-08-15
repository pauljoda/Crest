import SwiftUI

struct BrowserPeekTaskLifecycleModifier: ViewModifier {
    let requestID: UUID
    let committedNavigationCount: Int?
    let completedNavigationCount: Int?
    let present: @MainActor @Sendable () async -> Void
    let reveal: @MainActor @Sendable () async -> Void
    let recordCompletedNavigation: @MainActor @Sendable () -> Void

    func body(content: Content) -> some View {
        content
            .task(id: requestID) {
                await present()
            }
            .task(id: committedNavigationCount) {
                await reveal()
            }
            .onChange(of: completedNavigationCount) { oldCount, newCount in
                guard let newCount,
                    newCount > 0,
                    newCount != oldCount
                else { return }
                recordCompletedNavigation()
            }
    }
}

#Preview {
    Text("Peek lifecycle")
        .modifier(
            BrowserPeekTaskLifecycleModifier(
                requestID: UUID(
                    uuid: (
                        0x43, 0x52, 0x45, 0x53, 0x54, 0x50, 0x45, 0x45,
                        0x4B, 0x54, 0x41, 0x53, 0x4B, 0x4D, 0x4F, 0x44
                    )),
                committedNavigationCount: nil,
                completedNavigationCount: nil,
                present: {},
                reveal: {},
                recordCompletedNavigation: {}
            )
        )
}
