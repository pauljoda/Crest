import Foundation

enum BrowserSitePermissionRecordOrderingPolicy {
    static func areInIncreasingOrder(
        _ lhs: BrowserSitePermissionRecord,
        _ rhs: BrowserSitePermissionRecord
    ) -> Bool {
        if lhs.origin.displayName != rhs.origin.displayName {
            return lhs.origin.displayName.localizedStandardCompare(rhs.origin.displayName)
                == .orderedAscending
        }
        let lhsOrder = permissionOrder(lhs.permission)
        let rhsOrder = permissionOrder(rhs.permission)
        if lhsOrder != rhsOrder {
            return lhsOrder < rhsOrder
        }
        return (lhs.detail ?? "") < (rhs.detail ?? "")
    }

    private static func permissionOrder(_ permission: BrowserSitePermission) -> Int {
        switch permission {
        case .automaticDownloads:
            0
        case .camera:
            1
        case .cameraAndMicrophone:
            2
        case .externalApplications:
            3
        case .location:
            4
        case .microphone:
            5
        case .notifications:
            6
        case .popups:
            7
        }
    }
}
