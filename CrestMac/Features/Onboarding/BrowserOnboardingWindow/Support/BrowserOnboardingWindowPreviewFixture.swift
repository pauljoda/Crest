import AppKit
import Foundation

@MainActor
struct BrowserOnboardingWindowPreviewFixture {
    let request: BrowserOnboardingRequest
    let browser: BrowserStore
    let cloudSync: BrowserCloudSyncController
    let progress: BrowserOnboardingProgressStore
    let flow: BrowserOnboardingFlow

    init(
        entryPoint: BrowserOnboardingEntryPoint = .firstRun,
        plan: BrowserImportReviewPlan? = nil
    ) {
        let request = BrowserOnboardingRequest(
            entryPoint: entryPoint,
            presentationID: Self.requestID
        )
        let browser = BrowserStore(
            session: Self.session,
            persistence: InMemoryBrowserSessionPersistence()
        )
        let flow = BrowserOnboardingFlow(
            request: request,
            browser: browser,
            sourceDiscovery: BrowserOnboardingPreviewSourceDiscovery(
                sources: [Self.importSource]
            ),
            dataAccessProvider: BrowserOnboardingPreviewDataAccessProvider(),
            importReader: BrowserOnboardingPreviewImportReader(),
            importCommitter: BrowserOnboardingPreviewImportCommitter()
        )
        flow.discoverInstalledSources()
        if let plan {
            flow.updatePlan(plan)
        }

        self.request = request
        self.browser = browser
        cloudSync = .isolated(browser: browser)
        progress = BrowserOnboardingProgressStore(
            persistence: InMemoryBrowserOnboardingProgressPersistence(),
            forceWelcome: true
        )
        self.flow = flow
    }

    static let session = BrowserSession(
        spaces: [destinationSpace],
        selectedSpaceID: destinationSpace.id
    )

    static let reviewPlan = BrowserImportReviewPlan(
        imported: BrowserPortableImport(
            spaces: [sourceSpace],
            summary: BrowserPortableImportSummary(
                spaceCount: 1,
                folderCount: 0,
                liveTabCount: 1,
                archivedTabCount: 0,
                historyEntryCount: 0
            )
        ),
        existing: session
    )

    static let importSource = BrowserInstalledImportSource(
        application: .arc,
        applicationURL: URL(
            fileURLWithPath: "/Applications/Preview Browser.app"
        ),
        detectedPayload: BrowserDetectedImportPayload(
            application: .arc,
            profiles: []
        ),
        icon: NSImage(
            systemSymbolName: "safari.fill",
            accessibilityDescription: "Preview browser"
        ) ?? NSImage(size: NSSize(width: 54, height: 54))
    )

    private static let requestID = UUID(
        uuid: (
            0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
            0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x01
        )
    )
    private static let spaceID = SpaceID(
        rawValue: UUID(
            uuid: (
                0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
                0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x02
            )
        )
    )
    private static let profileID = UUID(
        uuid: (
            0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
            0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x03
        )
    )
    private static let tabID = TabID(
        rawValue: UUID(
            uuid: (
                0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
                0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x04
            )
        )
    )
    private static let sourceSpaceID = SpaceID(
        rawValue: UUID(
            uuid: (
                0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
                0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x05
            )
        )
    )
    private static let sourceProfileID = UUID(
        uuid: (
            0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
            0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x06
        )
    )
    private static let sourceTabID = TabID(
        rawValue: UUID(
            uuid: (
                0x8E, 0x72, 0x21, 0xB6, 0xD0, 0x3D, 0x4B, 0xA9,
                0x91, 0x7D, 0x7D, 0x55, 0xA6, 0xC3, 0xC0, 0x07
            )
        )
    )
    private static let previewDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let tab = BrowserTab(
        id: tabID,
        title: "Crest Preview",
        url: URL(string: "https://example.com/crest-preview"),
        symbol: "safari.fill",
        placement: .current,
        lastActivatedAt: previewDate
    )
    private static let destinationSpace = BrowserSpace(
        id: spaceID,
        profile: BrowsingProfile(id: profileID),
        name: "Work",
        symbol: "briefcase.fill",
        accent: .indigo,
        branding: .initial(accent: .indigo, symbol: "briefcase.fill"),
        folders: [],
        tabs: [tab],
        selectedTabID: tab.id
    )
    private static let sourceTab = BrowserTab(
        id: sourceTabID,
        title: "Imported Preview",
        url: URL(string: "https://example.com/imported-preview"),
        symbol: "square.and.arrow.down.fill",
        placement: .current,
        lastActivatedAt: previewDate
    )
    private static let sourceSpace = BrowserSpace(
        id: sourceSpaceID,
        profile: BrowsingProfile(id: sourceProfileID),
        name: "Imported Work",
        symbol: "shippingbox.fill",
        accent: .orange,
        branding: .initial(accent: .orange, symbol: "shippingbox.fill"),
        folders: [],
        tabs: [sourceTab],
        selectedTabID: sourceTab.id
    )
}
