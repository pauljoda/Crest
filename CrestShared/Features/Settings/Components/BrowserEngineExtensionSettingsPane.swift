import SwiftUI

#if !CREST_CHROMIUM_HOST
/// The Extensions destination's pane for an engine that ships no extensions.
///
/// The destination stays in the catalog — its raw value is a shipped
/// accessibility contract — but `isProvidedByCurrentEngine` keeps it out of
/// every list, so this body is only ever reached by a direct navigation.
struct BrowserEngineExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var requestedSpaceID: SpaceID?
    var requestRevision = 0

    var body: some View { EmptyView() }
}
#endif
