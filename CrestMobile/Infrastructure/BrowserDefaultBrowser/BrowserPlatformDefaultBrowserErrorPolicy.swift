import Foundation
import UIKit

@MainActor
enum BrowserPlatformDefaultBrowserErrorPolicy {
    static func userFacingDescription(for error: any Error) -> String? {
        let error = error as NSError
        guard error.domain == UIApplication.CategoryDefaultError.errorDomain,
              error.code
                == UIApplication.CategoryDefaultError.rateLimited.rawValue else {
            return nil
        }

        if let retryDate = error.userInfo[
            UIApplication.CategoryDefaultError.retryAvailableDateErrorKey
        ] as? Date {
            return "Apple limits default-browser checks. Try again after \(retryDate.formatted(date: .abbreviated, time: .shortened))."
        }
        return "Apple limits how often Crest can check this status. Review it in Default Apps Settings."
    }
}
