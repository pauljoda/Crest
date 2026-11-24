import SwiftUI

/// The control that opens Site Controls for the page the window shows: a
/// sheet on iPhone and in a narrow iPad window, a popover in a wide one. A
/// permission request opens them on its own, where it waits, and once it is
/// answered they close again unless the person opened them; closing them over
/// a waiting request dismisses it. The control wears a dot while a pop-up
/// waits on the person, and the new downloads badge.
struct MobilePageActionsMenu: View {
    /// The dot that says a pop-up was blocked, at the glyph's top trailing
    /// corner.
    private static let noticeDotSize: CGFloat = 7
    private static let noticeDotOffset = CGSize(width: 3, height: -3)
    /// Where the new downloads badge sits over the glyph's top trailing
    /// corner.
    private static let badgeOffset = CGSize(width: 9, height: -7)

    let browser: BrowserStore
    let pages: MobileSelectedPageActionPort
    let systemImage: String
    var downloadsAccess: MobileDownloadsMenuAccess? = nil
    var hideToolbar: (() -> Void)? = nil
    var controlSize = CGSize(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
    /// Whether the menu is a toolbar item, whose label the system draws so a
    /// side toolbar can stand it on end with the others.
    var isToolbarItem = false

    /// Where the menu's control sits in the window.
    @State private var frame: CGRect?
    @State private var showsSiteControls = false
    /// Whether a permission request opened Site Controls, rather than the
    /// person.
    @State private var opensForRequest = false
    @Environment(\.mobileBrowserCommandContext) private var commands
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if isToolbarItem {
            menu {
                Label("Page Actions", systemImage: systemImage)
            }
            .badge(downloadsAccess?.newItemCount ?? 0)
        } else {
            menu {
                chromeLabel
            }
            .crestMenuActionLabelStyle()
            .tint(.primary)
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    private func menu(@ViewBuilder label: () -> some View) -> some View {
        Button {
            showsSiteControls = pages.activePage != nil
        } label: {
            label()
        }
        .disabled(pages.activePage == nil)
        .crestPopover(isPresented: presentation, arrowEdge: .top) {
            if let page = pages.activePage {
                MobileSiteControlsContent(
                    browser: browser, pages: pages, page: page, commands: commands, source: frame,
                    hideToolbar: hideToolbar, downloadsAccess: downloadsAccess,
                    usesSheet: horizontalSizeClass != .regular,
                    dismiss: { presentation.wrappedValue = false })
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .global)
        } action: { frame in
            self.frame = frame
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(BrowserMobileAccessibilityID.pageActionsMenu)
        .pagePermissionHost(pages.activePage?.sitePermissionRequests)
        .preference(key: MobileSiteControlsHoldsSidebarKey.self, value: showsSiteControls)
        .onChange(of: pages.activePage?.sitePermissionRequests.current?.id, initial: true) { _, request in
            if request != nil {
                guard !showsSiteControls else { return }
                opensForRequest = true
                showsSiteControls = true
            } else if opensForRequest {
                opensForRequest = false
                showsSiteControls = false
            }
        }
    }

    /// Whether Site Controls show. Closing them over a waiting request
    /// dismisses the request.
    private var presentation: Binding<Bool> {
        Binding {
            showsSiteControls
        } set: { isPresented in
            if !isPresented, let requests = pages.activePage?.sitePermissionRequests, requests.current != nil {
                requests.cancelAll()
            }
            if !isPresented { opensForRequest = false }
            showsSiteControls = isPresented
        }
    }

    private var chromeLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemImage)
                .font(CrestTypography.compactControlGlyph)
                .foregroundStyle(
                    pages.blockedPopupNotice == nil
                        ? Color.secondary
                        : CrestColor.warning
                )
            if pages.blockedPopupNotice != nil {
                Circle()
                    .fill(CrestColor.warning)
                    .frame(width: Self.noticeDotSize, height: Self.noticeDotSize)
                    .offset(Self.noticeDotOffset)
                    .accessibilityHidden(true)
            }
            if let downloadsAccess, downloadsAccess.newItemCount > 0 {
                BrowserUtilityNotificationBadge(
                    count: downloadsAccess.newItemCount,
                    tint: CrestBrandTheme.accent,
                    progress: downloadsAccess.activeProgress
                )
                .offset(Self.badgeOffset)
            }
        }
        .frame(width: controlSize.width, height: controlSize.height)
        .contentShape(.rect)
    }

    private var accessibilityLabel: String {
        var label =
            pages.blockedPopupNotice?.chromeAccessibilityLabel(
                surfaceName: "Page Actions"
            ) ?? "Page Actions"
        if let downloadsAccess, downloadsAccess.newItemCount > 0 {
            label += ", \(downloadsAccess.unreadAccessibilityValue)"
        }
        return label
    }

    private var accessibilityHint: String {
        guard pages.blockedPopupNotice != nil else {
            return "Opens controls for this webpage"
        }
        return "Opens the Automatic Pop-ups permission and retry guidance"
    }
}

struct MobileDownloadsMenuAccess {
    let newItemCount: Int
    let activeProgress: Double?
    let open: @MainActor () -> Void

    var unreadAccessibilityValue: String {
        String(localized: "\(newItemCount) new downloads")
    }
}
