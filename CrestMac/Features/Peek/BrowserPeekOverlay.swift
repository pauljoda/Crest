import SwiftUI

struct BrowserPeekOverlay: View {
    let reservedLeadingWidth: CGFloat
    let layoutDirection: LayoutDirection
    let spaceAccess: BrowserSpaceAccessController

    @State private var model: BrowserPeekModel

    init(
        request: BrowserPeekRequest,
        browser: BrowserStore,
        pages: BrowserPagePool,
        coordinator: BrowserTransientBrowsingCoordinator,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.spaceAccess = spaceAccess
        _model = State(
            initialValue: BrowserPeekModel(
                request: request,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                coordinator: coordinator
            )
        )
    }

    init(
        model: BrowserPeekModel,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.spaceAccess = spaceAccess
        _model = State(initialValue: model)
    }

    var body: some View {
        BrowserPeekOverlayContent(
            model: model,
            spaceAccess: spaceAccess
        ) {
            BrowserPeekUnlockedContent(
                model: model,
                reservedLeadingWidth: reservedLeadingWidth,
                layoutDirection: layoutDirection
            )
        }
        .onChange(of: sourceIsLocked, initial: true) { _, isLocked in
            model.setSourceLocked(isLocked)
        }
        .onChange(of: sourceIsAvailable, initial: true) { _, isAvailable in
            model.setSourceAvailable(isAvailable)
        }
    }

    private var sourceIsLocked: Bool {
        guard let space = model.space else { return false }
        return spaceAccess.isLocked(space)
    }

    private var sourceIsAvailable: Bool {
        model.space != nil
    }
}

#Preview {
    BrowserPeekOverlay(
        model: BrowserPeekPreviewFixture.makeModel(),
        reservedLeadingWidth: 0,
        layoutDirection: .leftToRight,
        spaceAccess: BrowserPeekPreviewFixture.makeAccessController()
    )
    .frame(width: 900, height: 620)
}
