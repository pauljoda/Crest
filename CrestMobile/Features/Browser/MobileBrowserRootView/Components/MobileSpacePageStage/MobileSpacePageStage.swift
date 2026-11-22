import SwiftUI

/// The regular-width page area as the sidebar's Space pager moves: the shown
/// Space's card, and beside it the cards of the Spaces either side, sliding
/// with the pager as the next Space's sidebar does, finger and release alike.
/// With "Animate pages when switching Spaces" off or Reduce Motion on, the
/// cards keep their place and fade from one to the next as the pager moves
/// instead, finger and release alike, as on Mac.
///
/// The shown card is the page area itself and keeps its identity whichever
/// Space it shows, so a Space switch never builds it again. The others hold
/// what their Spaces show without taking touches, and only while they stand
/// in view: at rest the page area draws the shown card alone. Where a page
/// another Space keeps in memory slides in live, its web view moves into the
/// shown card as the pager comes to rest on that Space, where it already
/// stands, so landing changes nothing on screen. A Space whose pages have not
/// drawn yet keeps the card that slid in under its own until they have.
struct MobileSpacePageStage<Shown: View>: View {
    // MARK: - Types

    /// What the cards follow, which a change of has them follow anew.
    private struct Following: Equatable {
        let presentation: ObjectIdentifier?
        let spaceIDs: [UUID]
        let shownSpaceID: UUID?
        let shownPins: [UUID: UUID]
        let slides: Bool
    }

    // MARK: - Variables

    @Environment(\.spacePagerPresentation) private var presentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    let model: MobileBrowserRootModel
    let adjoinsSidebar: Bool
    let usesBorderlessPageFrame: Bool
    let shown: Shown
    @State private var motion = MobileSpacePageMotion()

    private var browser: BrowserStore { model.browser }

    // MARK: - Actions - Presentation

    var body: some View {
        let shownSpaceID = browser.shownSpace?.id
        ZStack {
            ForEach(neighbors(of: shownSpaceID)) { space in
                MobileSpaceNeighborPage(
                    space: space, model: model, adjoinsSidebar: adjoinsSidebar,
                    usesBorderlessPageFrame: usesBorderlessPageFrame
                )
                .modifier(MobileSpacePageSlot(motion: motion, spaceID: space.id, isShown: false))
            }
            shown
                .modifier(MobileSpacePageSlot(motion: motion, spaceID: shownSpaceID, isShown: true))
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            motion.measure(width)
        }
        .onChange(of: following(shownSpaceID), initial: true) { _, _ in
            motion.follow(
                presentation, spaces: browser.availableSpaces, shownSpaceID: shownSpaceID, shownPins: shownPins,
                slides: slides)
        }
        .onDisappear { motion.stopFollowing() }
    }

    /// The Spaces whose cards the page area draws now besides the shown
    /// one's, and the Space a slide came to rest on, under it, until its
    /// pages have drawn.
    private func neighbors(of shownSpaceID: UUID?) -> [SpaceModel] {
        var ids = motion.pageSpaceIDs.filter { $0 != shownSpaceID }
        if let landed = motion.landedSpaceID, landed == shownSpaceID, !ids.contains(landed), !shownPagesHaveDrawn {
            ids.append(landed)
        }
        let spaces = browser.availableSpaces
        return ids.compactMap { id in spaces.first { $0.id == id } }
    }

    /// Whether the shown Space's web pages have each drawn something of
    /// their own, or failed to.
    private var shownPagesHaveDrawn: Bool {
        guard let space = browser.shownSpace, !model.spaceAccess.isLocked(space) else { return true }
        return browser.cards(in: space).allSatisfy { card in
            guard card.surface == .webPage else { return true }
            let assignment = BrowserTabRuntimeAssignment(tabID: card.id, spaceID: space.id, profileID: space.profileID)
            guard let page = model.pages.residentPage(matching: assignment) else { return false }
            return page.live.failure != nil
                || BrowserPageSurfacePresentation.revealsWebContent(
                    committedNavigationCount: page.committedNavigationCount)
        }
    }

    private func following(_ shownSpaceID: UUID?) -> Following {
        Following(
            presentation: presentation.map(ObjectIdentifier.init), spaceIDs: browser.availableSpaces.map(\.id),
            shownSpaceID: shownSpaceID, shownPins: shownPins, slides: slides)
    }

    /// Whether the cards slide with the pager, or keep their place and fade.
    private var slides: Bool {
        SpacePageMotionPreference.slides(animatesPages: animatesSpacePages, reduceMotion: reduceMotion)
    }

    /// The pinned tab each unlocked Space shows, for those that show one.
    private var shownPins: [UUID: UUID] {
        var pins: [UUID: UUID] = [:]
        for space in browser.availableSpaces where !model.spaceAccess.isLocked(space) {
            guard let tabID = browser.selectedTabID(in: space.id), space.shownTab(tabID)?.placement == .pinned
            else { continue }
            pins[space.id] = tabID
        }
        return pins
    }
}
