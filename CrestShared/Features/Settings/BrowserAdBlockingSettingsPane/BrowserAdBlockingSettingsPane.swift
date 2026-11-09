import SwiftUI

/// Ad blocking, which holds for every page in every Space: the level it blocks
/// at, the filter lists that level turns on, the lists the person subscribes
/// to by address, their own rules, and the sites where it blocks nothing.
/// Everything below the level waits while blocking is off.
struct BrowserAdBlockingSettingsPane: View {
    let browser: BrowserStore
    let contentBlockingErrorDescription: String?

    var body: some View {
        BrowserSettingsPane(.adBlocking) {
            BrowserAdBlockingLevelSection(core: browser.core, errorDescription: contentBlockingErrorDescription)
            Group {
                BrowserFilterListsSettingsSection(core: browser.core)
                BrowserCustomFilterListsSettingsSection(core: browser.core)
                BrowserCustomFiltersSettingsSection(core: browser.core)
                BrowserBlockingSitesSettingsSection(core: browser.core)
            }
            .disabled(!browser.core.state.filterLists.level.blocksContent)
        }
    }
}
