import SwiftUI

/// The Extensions destination's pane for an engine that ships no extensions.
///
/// The destination stays in the catalog — its raw value is a shipped
/// accessibility contract — but `isProvidedByCurrentEngine` keeps it out of
/// every list, so this body is only ever reached by a direct navigation. The
/// Chromium framework supplies its own pane and excludes this file.
struct BrowserEngineExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var requestedSpaceID: SpaceID?
    var requestRevision = 0

    var body: some View { EmptyView() }
}
