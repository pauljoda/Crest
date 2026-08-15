import SwiftUI

extension BrowserRootModel {
    var sidebarPresentation: BrowserSidebarPresentation {
        BrowserSidebarPresentationPolicy.presentation(
            columnVisibility: chrome.columnVisibility,
            isFloatingSidebarPresented: isFloatingSidebarPresented
        )
    }

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

    func hideSidebar(reduceMotion: Bool) {
        chrome.utilityPresentation.dismiss()
        dismissFloatingSidebar(reduceMotion: reduceMotion)
        withAnimation(accessibleAnimation(CrestMotion.chrome, reduceMotion)) {
            chrome.hideSidebar()
        }
    }

    func toggleSidebar(reduceMotion: Bool) {
        switch sidebarPresentation.sidebarToggleAction {
        case .hide:
            hideSidebar(reduceMotion: reduceMotion)
        case .dock:
            withAnimation(
                accessibleAnimation(CrestMotion.chrome, reduceMotion)
            ) {
                isFloatingSidebarPresented = false
                chrome.showSidebar()
            }
        }
    }

    func presentFloatingSidebar(reduceMotion: Bool) {
        guard chrome.columnVisibility == .detailOnly else { return }
        withAnimation(
            accessibleAnimation(CrestMotion.floatingPane, reduceMotion)
        ) {
            isFloatingSidebarPresented = true
        }
    }

    func dismissFloatingSidebar(reduceMotion: Bool) {
        if sidebarPresentation == .floating {
            chrome.utilityPresentation.dismiss()
        }
        withAnimation(
            accessibleAnimation(CrestMotion.dismissal, reduceMotion)
        ) {
            isFloatingSidebarPresented = false
        }
    }

    func floatingSidebarHoverChanged(
        _ isHovering: Bool,
        reduceMotion: Bool
    ) {
        guard !isHovering else { return }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }

    func columnVisibilityChanged(reduceMotion: Bool) {
        guard chrome.columnVisibility != .detailOnly else {
            chrome.utilityPresentation.dismiss()
            return
        }
        dismissFloatingSidebar(reduceMotion: reduceMotion)
    }
}
