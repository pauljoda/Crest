import SwiftUI

struct BrowserQuickWindowActivityLifecycleModifier: ViewModifier {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: model.selectedAssignment) {
                model.preparePage(isActive: scenePhase == .active)
            }
            .task(id: model.activityClock.revision) {
                guard await model.waitUntilArchiveIsDue() else { return }
                model.archivePageIfNeeded()
                dismiss()
            }
            .onChange(of: scenePhase) { _, phase in
                model.setActive(phase == .active)
                guard phase != .active else { return }
                if phase == .inactive {
                    spaceAccess.lockAllForInactiveScene()
                } else {
                    spaceAccess.lockAll()
                }
            }
    }
}

#Preview("Quick Window Activity Lifecycle") {
    Color.clear
        .modifier(
            BrowserQuickWindowActivityLifecycleModifier(
                model: BrowserQuickWindowPreviewFixture.makeModel(),
                spaceAccess: BrowserQuickWindowPreviewFixture.makeAccessController(),
                dismiss: {}
            )
        )
        .frame(width: 480, height: 320)
}
