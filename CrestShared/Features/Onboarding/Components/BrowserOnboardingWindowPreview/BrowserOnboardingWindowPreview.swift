import SwiftUI

/// A Space as the Crest window shows it: its field across the whole window,
/// its sidebar on the left with the Space's name among its tabs, and the page
/// card inset beside it, measured as the real window is. The name is edited
/// in place where the preview is given it. Given how the switcher shows
/// Spaces, its bottom bar shows the Space among three others in that look.
struct BrowserOnboardingWindowPreview<Page: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let branding: SpaceBranding
    let symbol: String
    let name: String
    var editableName: Binding<String>? = nil
    var showsNameHint = false
    /// How the switcher shows the Spaces, or nil to show this Space alone.
    var spaceIcons: BrowserSpaceIconDisplay? = nil
    /// The look the other Spaces in the switcher wear, or nil for their own.
    var companionLook: SetupLook? = nil
    @ViewBuilder let page: Page

    @State private var favicons = FaviconAssets()

    /// The showcase's first Space dressed in the look, as the core resolves it.
    private var space: SpaceModel {
        SpaceModel.detached(
            SessionState.Seed.showcase.spaces[0].wearing(
                branding, symbol: symbol, name: name.isEmpty ? String(localized: "Your Space") : name))
    }

    var body: some View {
        let space = space
        ZStack {
            BrowserSpaceBannerBackground(branding: branding)
            HStack(spacing: 0) {
                sidebar(space)
                    .frame(width: BrowserChromeLayout.sidebarIdealWidth)
                pageCard
            }
        }
        .clipShape(.rect(cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserOnboardingWindowPreviewMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.14), lineWidth: CrestLayout.hairline)
        }
        .shadow(color: .black.opacity(0.45), radius: 30, y: 24)
        .environment(\.colorScheme, branding.colorScheme(over: colorScheme))
        .environment(\.sidebarSpacePresentation, SidebarSpacePresentation(space: space, isUnlocked: true))
        .accessibilityElement(children: editableName == nil ? .ignore : .contain)
        .accessibilityLabel("Preview of \(space.settings.name) in a Crest window")
    }

    /// The page beside the sidebar, inset as the window insets it.
    private var pageCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BrowserChromeLayout.pageCornerRadius, style: .continuous)
                .fill(CrestBrandPalette.paper)
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            page
        }
        .padding(.vertical, BrowserChromeLayout.pageFrameInset)
        .padding(.trailing, BrowserChromeLayout.pageFrameInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sidebar(_ space: SpaceModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titlebar
            addressField
                .padding(.horizontal, 10)
                .padding(.top, 2)
            PinnedTabGrid(
                tabs: space.pinnedTabs, favicons: favicons, assignment: BrowserSpaceRuntimeAssignment(space: space),
                select: { _ in }
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .allowsHitTesting(false)
            spaceRow(space)
                .padding(.horizontal, 14)
                .padding(.top, 8)
            if showsNameHint {
                Text("Click the name to rename")
                    .font(CrestTypography.sans(11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
            }
            BrowserSpaceSidebarSection(
                title: String(localized: "OPEN TABS"), tabs: space.currentTabs, favicons: favicons,
                profileID: space.profileID, selectedTabID: space.currentTabs.first?.id
            )
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .allowsHitTesting(false)
            Spacer(minLength: 0)
            bottomBar(space)
        }
    }

    /// The window's controls and the sidebar's navigation, as the title bar
    /// holds them.
    private var titlebar: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                Circle().fill(.primary.opacity(0.22)).frame(width: 12, height: 12)
            }
            Spacer()
            Image(systemName: "chevron.left")
            Image(systemName: "chevron.right").opacity(0.45)
            Image(systemName: "arrow.clockwise")
                .padding(.leading, 4)
        }
        .font(.system(size: BrowserChromeLayout.sidebarNavigationSymbolPointSize, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: BrowserChromeLayout.sidebarTitlebarHeight)
        .accessibilityHidden(true)
    }

    private var addressField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Search or enter website").lineLimit(1)
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: BrowserChromeLayout.addressHeight)
        .browserAddressFieldSurface(progress: 0, isLoading: false, isEditing: false, branding: branding)
        .accessibilityHidden(true)
    }

    private func spaceRow(_ space: SpaceModel) -> some View {
        HStack(spacing: 10) {
            BrowserSpaceIdentityIcon(space: space, size: 22)
                .frame(width: 22, height: 22)
            if let editableName {
                BrowserInlineSpaceName(
                    name: editableName, size: 15, titleFont: CrestTypography.sans(15, weight: .semibold))
            } else {
                Text(space.settings.name).font(CrestTypography.sans(15, weight: .semibold)).lineLimit(1)
                Spacer()
            }
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(height: 32)
    }

    private func bottomBar(_ space: SpaceModel) -> some View {
        HStack {
            Image(systemName: "arrow.down.circle")
            Spacer()
            if let spaceIcons {
                switcher(space, icons: spaceIcons)
            } else {
                BrowserSpaceIdentityIcon(space: space, size: 22)
                    .frame(width: 22, height: 22)
                    .padding(5)
                    .background(.primary.opacity(0.12), in: .rect(cornerRadius: 8, style: .continuous))
            }
            Spacer()
            Image(systemName: "archivebox")
        }
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityHidden(true)
    }
}

extension BrowserOnboardingWindowPreview {
    // MARK: - Actions - Switcher

    /// The switcher with this Space shown, two Spaces in its group beside it
    /// and one on its own.
    fileprivate func switcher(_ space: SpaceModel, icons: BrowserSpaceIconDisplay) -> some View {
        let shades: [BrowserSpaceDot.Shade] = [.shown, .grouped, .grouped, .other]
        let members = [space] + companions
        return HStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.offset) { index, member in
                Group {
                    if icons.showsDots {
                        BrowserSpaceDot(shade: shades[min(index, shades.count - 1)], isLocked: false, scale: 1.2)
                    } else {
                        BrowserSpaceIdentityIcon(space: member, size: 20)
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: 30, height: 30)
                .background(
                    .primary.opacity(index == 0 && !icons.showsDots ? 0.14 : 0),
                    in: .rect(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(3)
        .background(.primary.opacity(icons.showsDots ? 0 : 0.07), in: .rect(cornerRadius: 9, style: .continuous))
    }

    /// Three more Spaces, each wearing another template in the companion
    /// look.
    private var companions: [SpaceModel] {
        let seed = SessionState.Seed.showcase.spaces[0]
        let symbols = ["briefcase.fill", "book.fill", "leaf.fill"]
        return zip(SpaceHouse.all.dropFirst(), symbols).map { house, symbol in
            let look = companionLook?.applying(to: house.look) ?? house.look
            return SpaceModel.detached(seed.wearing(look, symbol: symbol, name: String(localized: house.title)))
        }
    }
}

enum BrowserOnboardingWindowPreviewMetrics {
    static let cornerRadius: CGFloat = 12
}
