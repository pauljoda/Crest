import Foundation

@MainActor
enum MobileBrowserTransientPreviewFixture {
    static let requestID = uuid(0x11)
    static let tabID = TabID(rawValue: uuid(0x12))
    static let previewURL = URL(
        fileURLWithPath: "/crest-transient-preview",
        isDirectory: false
    )
    static let space = BrowserSpace(
        id: SpaceID(rawValue: uuid(0x13)),
        profile: BrowsingProfile(id: uuid(0x14)),
        name: "Preview",
        symbol: "safari.fill",
        accent: .indigo,
        folders: [],
        tabs: [
            BrowserTab(
                id: tabID,
                title: "Preview page",
                url: previewURL,
                placement: .current,
                lastActivatedAt: Date(timeIntervalSince1970: 0)
            )
        ],
        selectedTabID: tabID
    )
    static let presentationState = MobileBrowserTransientPresentationState(
        dismissalOffset: 0,
        isCardVisible: true,
        isCardExpanded: true,
        reduceMotion: false,
        reduceTransparency: false,
        presentationPhase: .committed,
        sourcePresentation: .resolved(nil)
    )
    static let request = BrowserPeekRequest(
        id: requestID,
        url: previewURL,
        sourceTabID: tabID,
        sourceTitle: "Preview page",
        spaceAssignment: BrowserSpaceRuntimeAssignment(space: space),
        trigger: .longPress
    )
    static let presentation = MobileTransientBrowsingPresentation(
        request: .peek(request),
        phase: .committed
    )

    static func makeModel() -> MobileBrowserTransientOverlayModel {
        let browser = makeBrowser()
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        return MobileBrowserTransientOverlayModel(
            previewing: .peek(request),
            browser: browser,
            coordinator: coordinator,
            spaceAccess: makeAccessController()
        )
    }

    static func makeCoordinator() -> BrowserTransientBrowsingCoordinator {
        let coordinator = BrowserTransientBrowsingCoordinator()
        coordinator.presentPeek(request)
        return coordinator
    }

    static func makeBrowser() -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault(),
            browsingMode: .privateBrowsing
        )
    }

    static func makeAccessController() -> BrowserSpaceAccessController {
        BrowserSpaceAccessController(
            authenticator: MobileBrowserTransientPreviewAuthenticator()
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53, 0x54, 0x4D, 0x4F, 0x42,
                0x49, 0x4C, 0x45, 0x50, 0x45, 0x45, 0x4B, finalByte
            )
        )
    }
}
