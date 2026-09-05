import Foundation

extension BrowserSyncPayload {
    var spaceValue: BrowserSyncSpace? {
        guard case .space(let value) = self else { return nil }
        return value
    }

    var folderValue: BrowserSyncFolder? {
        guard case .folder(let value) = self else { return nil }
        return value
    }

    var tabValue: BrowserSyncTab? {
        guard case .tab(let value) = self else { return nil }
        return value
    }

    var historyValue: BrowserSyncHistory? {
        guard case .history(let value) = self else { return nil }
        return value
    }
}
