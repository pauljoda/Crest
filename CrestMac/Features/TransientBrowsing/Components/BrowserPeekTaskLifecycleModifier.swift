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
