extension BrowserCloudAccountState {
    var description: String {
        switch self {
        case .checking: "Checking"
        case .available: "Available"
        case .noAccount: "Not signed in"
        case .restricted: "Restricted"
        case .temporarilyUnavailable: "Temporarily unavailable"
        case .couldNotDetermine: "Could not determine"
        }
    }
}
