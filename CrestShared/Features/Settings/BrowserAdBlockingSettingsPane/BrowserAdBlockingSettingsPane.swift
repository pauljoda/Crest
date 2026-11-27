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
            BrowserSettingsSectionSlot(.adBlockingLevel) {
                BrowserAdBlockingLevelSection(core: browser.core, errorDescription: contentBlockingErrorDescription)
            }
            BrowserSettingsSectionSlot(.filterLists) {
                BrowserFilterListsSettingsSection(core: browser.core).disabled(isOff)
            }
            BrowserSettingsSectionSlot(.customFilterLists) {
                BrowserCustomFilterListsSettingsSection(core: browser.core).disabled(isOff)
            }
            BrowserSettingsSectionSlot(.customFilters) {
                BrowserCustomFiltersSettingsSection(core: browser.core).disabled(isOff)
            }
            BrowserSettingsSectionSlot(.blockingSites) {
                BrowserBlockingSitesSettingsSection(core: browser.core).disabled(isOff)
            }
        }
    }

    /// Everything below the level waits while blocking is off.
    private var isOff: Bool {
        !browser.core.state.filterLists.level.blocksContent
    }
}
