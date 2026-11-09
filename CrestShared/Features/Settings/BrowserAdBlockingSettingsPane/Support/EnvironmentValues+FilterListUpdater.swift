import SwiftUI

extension EnvironmentValues {
    /// The app's filter list updater, which a control that asked the core to
    /// update every list has check at once; nil where none runs.
    @Entry var filterListUpdater: BrowserFilterListUpdater? = nil
}
