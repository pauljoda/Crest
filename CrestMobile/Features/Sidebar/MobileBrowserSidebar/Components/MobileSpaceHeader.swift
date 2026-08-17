import SwiftUI

struct MobileSpaceHeader: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let space: BrowserSpace
    let isPrivateBrowsing: Bool
    @Binding var isSavedTabsExpanded: Bool
    let openNewTab: () -> Void
    let createFolder: () -> Void
    let showHistory: () -> Void
    let showPasswords: () -> Void
    let showSettings: () -> Void
    let closePrivateBrowsing: () -> Void
    let cleanup: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: toggleSavedTabs) {
                HStack(spacing: CrestSpacing.small) {
                    Group {
                        if BrowserSpaceHeaderIconPolicy.showsDisclosure(
                            isSavedTabsExpanded: isSavedTabsExpanded
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        } else {
                            BrowserSpaceIdentityIcon(space: space, size: 22)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: 22, height: 22)
                    Text(space.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if space.accessPolicy.requiresAuthentication {
                        Image(systemName: "lock.fill")
                            .font(.caption2.weight(.bold))
                            .accessibilityLabel("Private Space")
                    }
                    Spacer(minLength: CrestSpacing.small)
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: BrowserSidebarScrollLayoutPolicy.fixedSpaceHeaderMaxHeight,
                    alignment: .leading
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(space.name) saved tabs")
            .accessibilityValue(isSavedTabsExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(
                isSavedTabsExpanded ? "Collapses saved tabs" : "Expands saved tabs"
            )

            Menu {
                Button("New Tab", systemImage: "plus", action: openNewTab)
                if supportsMultipleWindows {
                    Button("New Window", systemImage: "macwindow.badge.plus") {
                        openWindow(value: BrowserWindowID())
                    }
                    .accessibilityIdentifier("new-browser-window")
                }
                Button("New Folder", systemImage: "folder.badge.plus", action: createFolder)
                Button("History", systemImage: "clock.arrow.circlepath", action: showHistory)
                if isPrivateBrowsing {
                    Label("Passwords Off in Private Browsing", systemImage: "key.slash")
                        .foregroundStyle(.secondary)
                    Button(
                        "Close Private Tabs",
                        systemImage: "xmark.square",
                        role: .destructive,
                        action: closePrivateBrowsing
                    )
                    .accessibilityIdentifier("close-private-tabs")
                } else {
                    Button("Passwords", systemImage: "key.fill", action: showPasswords)
                }
                Button("Settings", systemImage: "gearshape", action: showSettings)
                    .accessibilityIdentifier("settings-button")
                Button("Clean Up Current Tabs", systemImage: "sparkles", action: cleanup)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .tint(.primary)
            .accessibilityIdentifier("space-actions")
            .accessibilityLabel("Space actions")
        }
        .padding(.leading, CrestSpacing.small)
        .padding(.trailing, CrestSpacing.extraSmall)
        .frame(minHeight: CrestLayout.sidebarRowHeight)
        .crestInteractiveSurface(
            isSelected: false,
            isHovering: isHovering,
            cornerRadius: CrestLayout.sidebarControlCornerRadius
        )
        .padding(.horizontal, CrestSpacing.small)
        .onHover { hovering in
            withAnimation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.hover,
                    reduceMotion: reduceMotion
                )
            ) {
                isHovering = hovering
            }
        }
    }

    private func toggleSavedTabs() {
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.disclosure,
                reduceMotion: reduceMotion
            )
        ) {
            isSavedTabsExpanded.toggle()
        }
    }
}
