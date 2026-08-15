import Foundation

@MainActor
enum BrowserPasskeyAccessPreviewFixture {
    static func controller(
        authorizationState: BrowserPasskeyAuthorizationState
    ) -> BrowserPasskeyAccessController {
        BrowserPasskeyAccessController(
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { authorizationState },
            authorizationRequester: { authorizationState }
        )
    }
}
