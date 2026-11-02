import SwiftUI

struct BrowserPeekOverlay: View {
    let reservedLeadingWidth: CGFloat
    let layoutDirection: LayoutDirection
    let spaceAccess: BrowserSpaceAccessController
    let frameInsets: EdgeInsets

    @State private var model: BrowserPeekModel

    init(
        request: BrowserPeekRequest,
        browser: BrowserStore,
        pages: BrowserPagePool,
        coordinator: BrowserTransientBrowsingCoordinator,
        reservedLeadingWidth: CGFloat,
        layoutDirection: LayoutDirection,
        spaceAccess: BrowserSpaceAccessController,
        frameInsets: EdgeInsets
    ) {
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.spaceAccess = spaceAccess
        self.frameInsets = frameInsets
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
        spaceAccess: BrowserSpaceAccessController,
        frameInsets: EdgeInsets
    ) {
        self.reservedLeadingWidth = reservedLeadingWidth
        self.layoutDirection = layoutDirection
        self.spaceAccess = spaceAccess
        self.frameInsets = frameInsets
        _model = State(initialValue: model)
    }

    var body: some View {
        BrowserTransientOverlayContent(
            requestID: model.request.id,
            space: model.spaceModel,
            spaces: model.availableSpaceModels,
            spaceAccess: spaceAccess,
            unavailableSpacePresentation: BrowserPeekVocabulary.unavailableSpace,
            selectSpace: model.selectLockedSpace,
            dismissUnavailable: model.dismissUnavailableRequest
        ) {
            BrowserPeekUnlockedContent(
                model: model,
                reservedLeadingWidth: reservedLeadingWidth,
                layoutDirection: layoutDirection,
                frameInsets: frameInsets
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
        guard let space = model.spaceModel else { return false }
        return spaceAccess.isLocked(space)
    }

    private var sourceIsAvailable: Bool {
        model.request.hasSource(in: model.browser) && model.spaceModel != nil
    }
}
