import SwiftUI

struct BrowserPeekTaskLifecycleModifier: ViewModifier {
    let requestID: UUID
    let completedNavigationCount: Int?
    let present: @MainActor @Sendable () async -> Void
    let recordCompletedNavigation: @MainActor @Sendable () -> Void

    func body(content: Content) -> some View {
        content
            .task(id: requestID) {
                await present()
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
