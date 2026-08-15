import Foundation
import WebKit

@MainActor
struct MobileBrowserCredentialChromePreviewFixture {
    let browser: BrowserStore
    let page: MobileBrowserPage
    let space: BrowserSpace
    let currentPasswordRequest: BrowserCredentialFillRequest
    let newPasswordRequest: BrowserCredentialFillRequest
    let saveCandidate: BrowserCredentialSaveCandidate
    let suggestion: CredentialDescriptor

    init() {
        guard
            let origin = CredentialOrigin(
                securityProtocol: "https",
                host: "accounts.example.com",
                port: 443
            )
        else {
            preconditionFailure("The credential preview origin must be valid.")
        }
        let previewDate = Date(timeIntervalSince1970: 1_700_000_000)
        let spaceID = SpaceID(rawValue: Self.spaceUUID)
        let tab = BrowserTab(
            id: TabID(rawValue: Self.tabUUID),
            title: "Accounts",
            url: URL(string: "https://accounts.example.com/sign-in"),
            symbol: "person.crop.circle",
            placement: .current,
            lastActivatedAt: previewDate
        )
        let space = BrowserSpace(
            id: spaceID,
            profile: BrowsingProfile(id: Self.profileUUID),
            name: "Work",
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )

        self.browser = browser
        self.space = space
        page = MobileBrowserPage(
            tab: tab,
            space: space,
            websiteDataStore: WKWebsiteDataStore.nonPersistent(),
            allowsCredentialAccess: false,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
        currentPasswordRequest = BrowserCredentialFillRequest(
            id: Self.currentRequestUUID,
            origin: origin,
            topLevelOrigin: origin,
            usernameHint: "paul@example.com",
            passwordKind: .current,
            isCrossOriginFrame: false,
            requestedAt: previewDate
        )
        newPasswordRequest = BrowserCredentialFillRequest(
            id: Self.newRequestUUID,
            origin: origin,
            topLevelOrigin: origin,
            usernameHint: "paul@example.com",
            passwordKind: .new,
            isCrossOriginFrame: false,
            requestedAt: previewDate
        )
        saveCandidate = BrowserCredentialSaveCandidate(
            id: Self.saveCandidateUUID,
            origin: origin,
            topLevelOrigin: origin,
            username: "paul@example.com",
            password: "preview-password",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: previewDate
        )
        suggestion = CredentialDescriptor(
            id: CredentialID(rawValue: Self.credentialUUID),
            spaceID: spaceID,
            origin: origin,
            username: "paul@example.com",
            displayName: "Media Library",
            createdAt: previewDate,
            updatedAt: previewDate
        )
    }

    private static let spaceUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
        )
    )
    private static let profileUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02
        )
    )
    private static let tabUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03
        )
    )
    private static let currentRequestUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04
        )
    )
    private static let newRequestUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05
        )
    )
    private static let credentialUUID = UUID(
        uuid: (
            0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x40, 0x00,
            0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x06
        )
    )
    private static let saveCandidateUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)
    )
}
