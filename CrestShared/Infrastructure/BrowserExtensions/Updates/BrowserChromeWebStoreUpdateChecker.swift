import Foundation

/// Reads the currently published version from Google's Omaha endpoint.
final class BrowserChromeWebStoreUpdateChecker: BrowserExtensionUpdateChecking {
    typealias Download = @Sendable (URL) async throws -> (Data, URLResponse)

    private let download: Download

    init(
        download: @escaping Download = { url in
            try await URLSession.shared.data(from: url)
        }
    ) {
        self.download = download
    }

    func publishedVersion(
        forExtension extensionID: String
    ) async throws -> String? {
        guard let identifier = BrowserChromeExtensionID(extensionID) else {
            throw BrowserChromeWebStoreUpdateCheckError.identityMismatch
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await download(
                BrowserChromeWebStoreUpdateRequest.updateCheckURL(
                    for: identifier
                )
            )
        } catch {
            throw BrowserChromeWebStoreUpdateCheckError.transport(
                error.localizedDescription
            )
        }
        guard let httpResponse = response as? HTTPURLResponse,
            httpResponse.statusCode == 200,
            httpResponse.url?.scheme?.lowercased() == "https"
        else {
            throw BrowserChromeWebStoreUpdateCheckError.invalidResponse
        }
        return try BrowserChromeWebStoreUpdateCheckParser.check(
            in: data,
            expectedID: identifier
        ).publishedVersion
    }
}
