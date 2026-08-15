import Foundation

enum MobileOnboardingPreviewFixtures {
    static var tutorialWorkSpace: BrowserSpace {
        guard let space = BrowserSession.preview.spaces.first else {
            preconditionFailure("The onboarding work preview requires one Space.")
        }
        return space
    }

    static var tutorialPersonalSpace: BrowserSpace {
        guard let space = BrowserSession.preview.spaces.dropFirst().first else {
            preconditionFailure("The onboarding personal preview requires two Spaces.")
        }
        return space
    }

    @MainActor
    static var manualPlan: BrowserManualSetupPlan {
        BrowserManualSetupPlan(existing: MobileBrowserPreviewFixture().browser.session)
    }

    static let samplePinnedTabs = [
        BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x5C, 0xD5, 0x3A, 0xCD, 0xF3, 0xDC, 0x4D, 0x50,
                        0x88, 0x11, 0x79, 0x0D, 0x7A, 0x46, 0xA1, 0x05
                    )
                )
            ),
            title: "Mail",
            url: httpsURL(host: "mail.google.com"),
            symbol: BrowserTab.symbol(forEmoji: "✉️"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
        BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x77, 0xC0, 0x2B, 0xCD, 0x04, 0x1C, 0x47, 0xEB,
                        0x92, 0x48, 0x4B, 0x12, 0xE6, 0xFB, 0x24, 0x32
                    )
                )
            ),
            title: "Calendar",
            url: httpsURL(host: "calendar.google.com"),
            symbol: BrowserTab.symbol(forEmoji: "📅"),
            placement: .pinned,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    static let sampleSavedTabs = [
        BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0xC7, 0xE3, 0x17, 0x32, 0xA7, 0xA3, 0x41, 0x9D,
                        0x86, 0xDB, 0x4E, 0xE7, 0xC2, 0x8C, 0xE3, 0xB5
                    )
                )
            ),
            title: "Project notes",
            url: httpsURL(host: "notion.so"),
            symbol: BrowserTab.symbol(forEmoji: "📝"),
            placement: .saved,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
        BrowserTab(
            id: TabID(
                rawValue: UUID(
                    uuid: (
                        0x68, 0x61, 0x14, 0xE8, 0x23, 0x88, 0x44, 0x54,
                        0xA0, 0x1A, 0x20, 0x7F, 0xA1, 0x3A, 0xA2, 0xC6
                    )
                )
            ),
            title: "Reading list",
            url: httpsURL(host: "developer.apple.com"),
            symbol: BrowserTab.symbol(forEmoji: "📚"),
            placement: .saved,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        ),
    ]

    private static func httpsURL(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        guard let url = components.url else {
            preconditionFailure("Invalid onboarding preview host: \(host)")
        }
        return url
    }
}
