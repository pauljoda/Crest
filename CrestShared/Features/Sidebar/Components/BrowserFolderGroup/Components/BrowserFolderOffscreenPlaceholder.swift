import SwiftUI

/// Draws a folder well away from the screen as a block of the height it had
/// when it was last drawn, where the shell keeps a visible band. The band
/// decides when; see `BrowserSidebarVisibleBand`.
///
/// The block is only as right as that height, so the folder is drawn again
/// whenever anything its height follows has changed since: whether it is
/// open, what it holds, which folders inside it are open, the tab a closed one
/// keeps, and the row metrics.
///
/// A folder is never let go while VoiceOver or Switch Control is on, since a
/// block has nothing for them to reach, or while something inside it is in
/// progress, such as a rename or an open picker, which would be lost with the
/// rows that hold it.
struct BrowserFolderOffscreenPlaceholder: ViewModifier {
    // MARK: - Types

    /// Raised by a row with work in progress that its view holds, so the
    /// folders around it stay drawn until the work ends.
    struct KeepsDrawnKey: PreferenceKey {
        static let defaultValue = false

        static func reduce(value: inout Bool, nextValue: () -> Bool) {
            value = value || nextValue()
        }
    }

    /// What a folder's height follows. A block drawn for one shape is wrong
    /// for any other.
    struct Shape: Equatable {
        enum Element: Equatable {
            case tab(depth: Int)
            case split(depth: Int, members: Int)
            case folder(depth: Int, isOpen: Bool, keptTabID: UUID?)
        }

        let elements: [Element]
        let tabScale: Double
        let hasBorders: Bool
    }

    // MARK: - Variables

    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    /// Off for a folder drawn on the way to a closed folder's kept tab.
    var isEnabled = true

    @Environment(\.browserSidebarVisibleBand) private var band
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverEnabled
    @Environment(\.accessibilitySwitchControlEnabled) private var isSwitchControlEnabled

    /// The height the folder had when it was last drawn, for the shape it had.
    @State private var drawn: (height: CGFloat, shape: Shape)?
    /// Whether a row inside has work in progress.
    @State private var keepsDrawn = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let band {
            let shape = shape
            let canLetGo =
                isEnabled && drawn != nil && !keepsDrawn && !isVoiceOverEnabled && !isSwitchControlEnabled
            let drawsPlaceholder = canLetGo && band.slot(for: folder.id).isPlaceholder && drawn?.shape == shape
            Group {
                if drawsPlaceholder, let drawn {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: drawn.height)
                        .accessibilityHidden(true)
                } else {
                    content.onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: { height in
                        drawn = (height, shape)
                    }
                }
            }
            .transaction(value: drawsPlaceholder) { $0.animation = nil }
            .onPreferenceChange(KeepsDrawnKey.self) { keepsDrawn = $0 }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: BrowserSidebarVisibleBand.contentSpace)
            } action: { frame in
                band.place(folder.id, at: frame, canLetGo: canLetGo)
            }
            .onChange(of: canLetGo) { _, canLetGo in
                band.allow(folder.id, toLetGo: canLetGo)
            }
            .onDisappear { band.forget(folder.id) }
        } else {
            content
        }
    }

    // MARK: - Actions - Reading

    private var shape: Shape {
        let space = context.space
        let appearance = BrowserDeviceAppearanceStore.shared
        var elements: [Shape.Element] = [
            .folder(depth: 0, isOpen: !folder.isCollapsed, keptTabID: keptTabID(of: folder))
        ]
        func walk(_ list: SidebarListModel, depth: Int) {
            for item in BrowserSidebarListItem.items(of: list, in: space) {
                switch item.content {
                case .tab: elements.append(.tab(depth: depth))
                case .split(_, let members): elements.append(.split(depth: depth, members: members.count))
                case .folder(let inner):
                    elements.append(.folder(depth: depth, isOpen: !inner.isCollapsed, keptTabID: keptTabID(of: inner)))
                    if !inner.isCollapsed { walk(space.sidebar.inside(inner.id), depth: depth + 1) }
                }
            }
        }
        if !folder.isCollapsed { walk(space.sidebar.inside(folder.id), depth: 1) }
        return Shape(
            elements: elements, tabScale: appearance.tabScale, hasBorders: appearance.tabs.borders == .all)
    }

    /// The tab a closed folder keeps on screen in place of its contents.
    private func keptTabID(of folder: FolderStateModel) -> UUID? {
        guard folder.isCollapsed else { return nil }
        #if os(macOS)
            let state = sidebarInteraction.collapsedFolderVisibility(
                for: BrowserFolderRuntimeAssignment(
                    folderID: folder.id, spaceID: context.space.id, profileID: context.space.profileID)
            ).state
            // Residency is invisible to Observation unless its revision is read.
            _ = context.pageAccess.residencyRevision()
            guard let keptTabID = state.keptTabID, context.pageAccess.containsResidentPage(keptTabID) else {
                return nil
            }
            return keptTabID
        #else
            return nil
        #endif
    }
}

extension View {
    /// Keeps the folders around this view drawn while `keeps` is true.
    func keepsSidebarFolderDrawn(_ keeps: Bool) -> some View {
        transformPreference(BrowserFolderOffscreenPlaceholder.KeepsDrawnKey.self) { $0 = $0 || keeps }
    }
}
