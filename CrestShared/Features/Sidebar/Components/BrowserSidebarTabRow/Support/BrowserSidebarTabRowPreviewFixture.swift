#if DEBUG
    import Foundation

    /// A draft tab for the previews of the setup and import rows, which draw
    /// tabs that never reached the core.
    @MainActor
    enum BrowserSidebarTabRowPreviewFixture {
        // MARK: - Static Variables

        static let profileID = uuid(0x72)
        static let tabID = uuid(0x73)
        static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        // MARK: - Actions - Fixtures

        static func tab(placement: TabPlacement = .current) -> BrowserTab {
            BrowserTab(
                id: tabID,
                title: "Example",
                url: URL(fileURLWithPath: "/preview/example"),
                symbol: "globe",
                placement: placement,
                lastActivatedAt: fixedDate
            )
        }

        private static func uuid(_ suffix: UInt8) -> UUID {
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, suffix))
        }
    }
#endif
