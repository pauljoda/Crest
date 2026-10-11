import Foundation
import UIKit

@MainActor
enum BrowserPlatformDefaultBrowserErrorPolicy {
    /// Whether the system declined to answer because Crest asked too recently.
    static func isRateLimited(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == UIApplication.CategoryDefaultError.errorDomain
            && error.code == UIApplication.CategoryDefaultError.rateLimited.rawValue
    }

    static func userFacingDescription(for error: any Error) -> String? {
        guard isRateLimited(error) else { return nil }

        if let retryDate = (error as NSError).userInfo[
            UIApplication.CategoryDefaultError.retryAvailableDateErrorKey
        ] as? Date {
            return
                "Apple limits default-browser checks. Try again after \(retryDate.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Apple limits how often Crest can check this status. Review it in Default Apps Settings."
    }
}
