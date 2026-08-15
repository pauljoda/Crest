import SwiftUI

extension MobileBrowserRootModel {
    var sidebarWidth: CGFloat {
        sidebarWidthTransaction.width
    }

    var sidebarWidthBinding: Binding<CGFloat> {
        Binding(
            get: { self.sidebarWidthTransaction.width },
            set: { self.sidebarWidthTransaction.resize(to: $0) }
        )
    }

    func restoreSidebarWidth(_ width: CGFloat) {
        guard windowState == nil else { return }
        guard width != sidebarWidthTransaction.persistedWidth else { return }
        sidebarWidthTransaction.restore(persistedWidth: width)
    }

    func commitSidebarWidth(_ width: CGFloat) -> CGFloat? {
        sidebarWidthTransaction.resize(to: width)
        guard let committedWidth = sidebarWidthTransaction.commit() else {
            return nil
        }
        if let windowState {
            windowState.captureSidebar(width: Double(committedWidth))
            return nil
        }
        return committedWidth
    }

    func revealSidebarForUtilityCommand(
        presentation: MobileBrowserPresentation
    ) {
        switch presentation {
        case .compact:
            navigation.showTabViewer()
        case .regular:
            navigation.showRegularSidebar()
        }
    }

    func hideRegularSidebar(reduceMotion: Bool) {
        navigation.utilityPresentation.dismiss()
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.hideRegularSidebar()
        }
    }

    func showRegularSidebar(reduceMotion: Bool) {
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.showRegularSidebar()
        }
    }

    func toggleSidebar(
        presentation: MobileBrowserPresentation,
        reduceMotion: Bool
    ) {
        if presentation == .compact {
            if navigation.compactShowsPage {
                navigation.showTabViewer()
            } else {
                activateSelectedTab()
            }
            return
        }

        if navigation.regularSidebarIsPresented {
            navigation.utilityPresentation.dismiss()
        }
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            navigation.toggleRegularSidebar()
        }
    }

}
