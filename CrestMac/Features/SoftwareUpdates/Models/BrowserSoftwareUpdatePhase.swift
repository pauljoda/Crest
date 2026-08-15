enum BrowserSoftwareUpdatePhase: Equatable, Sendable {
    case idle
    case permission
    case checking
    case updateAvailable
    case downloading
    case extracting
    case readyToInstall
    case installing
    case upToDate
    case failed
    case installed
}
