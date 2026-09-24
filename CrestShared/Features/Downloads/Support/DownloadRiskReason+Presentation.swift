import Foundation

extension DownloadRiskReason {
    var message: String {
        String(localized: warningMessage)
    }

    var warningMessage: LocalizedStringResource {
        switch self {
        case .executableOrInstaller:
            "This file type can install or run software."
        case .deceptiveFilename:
            "The original filename used invisible or direction-changing characters that can disguise its real extension."
        default:
            "The server-reported file type does not match the filename and one of those types can run software."
        }
    }
}
