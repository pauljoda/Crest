import Foundation

extension BrowserSyncPayload {
    var spaceValue: BrowserSyncSpace? {
        guard case let .space(value) = self else { return nil }
        return value
    }

    var folderValue: BrowserSyncFolder? {
        guard case let .folder(value) = self else { return nil }
        return value
    }

    var tabValue: BrowserSyncTab? {
        guard case let .tab(value) = self else { return nil }
        return value
    }

    var historyValue: BrowserSyncHistory? {
        guard case let .history(value) = self else { return nil }
        return value
    }
}
