@MainActor
struct MobilePageActionsPreviewFixture {
    let browser: BrowserStore
    let actions: MobilePageActionsPreviewStub

    init() {
        let fixture = MobileBrowserPreviewFixture()
        browser = fixture.browser
        actions = MobilePageActionsPreviewStub(
            assignment: BrowserTabRuntimeAssignment(
                tabID: TabID(rawValue: fixture.space.id.rawValue),
                spaceID: fixture.space.id,
                profileID: fixture.space.profile.id
            )
        )
    }
}
