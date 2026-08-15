import Foundation
import WebKit

extension BrowserDownloadCenter: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        await destinationURL(
            for: download,
            response: response,
            suggestedFilename: suggestedFilename
        )
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download)
    }

    func download(
        _ download: WKDownload,
        didFailWithError error: any Error,
        resumeData: Data?
    ) {
        handleFailure(
            for: download,
            error: error,
            resumeData: resumeData
        )
    }

    func download(
        _ download: WKDownload,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler:
            @escaping @MainActor @Sendable (
                URLSession.AuthChallengeDisposition,
                URLCredential?
            ) -> Void
    ) {
        handleAuthenticationChallenge(
            challenge,
            for: download,
            completionHandler: completionHandler
        )
    }
}
