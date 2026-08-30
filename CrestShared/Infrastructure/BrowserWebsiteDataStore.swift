import Foundation
import WebKit

@MainActor
enum BrowserWebsiteDataStore {
    static func launchScoped(
        for profile: BrowsingProfile,
        environment: BrowserLaunchEnvironment = .current
    ) -> WKWebsiteDataStore {
        guard
            !BrowserLaunchIsolationPolicy.usesEphemeralProfileStorage(
                environment
            )
        else {
            return .nonPersistent()
        }
        return persistent(for: profile)
    }

    static func persistent(for profile: BrowsingProfile) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: profile.id)
    }

    static func clearSiteData(
        for pageURL: URL,
        in dataStore: WKWebsiteDataStore
    ) async {
        guard let host = pageURL.host()?.lowercased(), !host.isEmpty else { return }

        let cookieStore = dataStore.httpCookieStore
        let cookies = await allCookies(in: cookieStore)
        for cookie in cookies
        where BrowserSiteDataPolicy.matchesCookieDomain(
            cookie.domain,
            host: host
        ) {
            await delete(cookie, from: cookieStore)
        }

        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataRecords(ofTypes: dataTypes, in: dataStore)
        let matchingRecords = records.filter {
            BrowserSiteDataPolicy.matchesDataRecord(
                displayName: $0.displayName,
                host: host
            )
        }
        guard !matchingRecords.isEmpty else { return }
        await removeData(
            ofTypes: dataTypes,
            for: matchingRecords,
            in: dataStore
        )
    }

    private static func allCookies(
        in cookieStore: WKHTTPCookieStore
    ) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            cookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static func delete(
        _ cookie: HTTPCookie,
        from cookieStore: WKHTTPCookieStore
    ) async {
        await withCheckedContinuation { continuation in
            cookieStore.delete(cookie) { continuation.resume() }
        }
    }

    private static func dataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        await withCheckedContinuation { continuation in
            dataStore.fetchDataRecords(ofTypes: dataTypes) {
                continuation.resume(returning: $0)
            }
        }
    }

    private static func removeData(
        ofTypes dataTypes: Set<String>,
        for records: [WKWebsiteDataRecord],
        in dataStore: WKWebsiteDataStore
    ) async {
        await withCheckedContinuation { continuation in
            dataStore.removeData(ofTypes: dataTypes, for: records) {
                continuation.resume()
            }
        }
    }
}
