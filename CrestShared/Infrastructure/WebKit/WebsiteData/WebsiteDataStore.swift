import Foundation
import WebKit

@MainActor
enum BrowserWebsiteDataStore {
    static func launchScoped(
        for profile: BrowsingProfile,
        environment: BrowserLaunchEnvironment = .current
    ) -> WKWebsiteDataStore {
        guard
            !environment.usesEphemeralProfileStorage
        else {
            return .nonPersistent()
        }
        return persistent(for: profile, environment: environment)
    }

    /// The profile's persistent store, which a named isolated launch keeps
    /// apart from the installed app's.
    static func persistent(
        for profile: BrowsingProfile,
        environment: BrowserLaunchEnvironment = .current
    ) -> WKWebsiteDataStore {
        WKWebsiteDataStore(forIdentifier: environment.websiteDataStoreIdentifier(forProfileID: profile.id))
    }

    static func clearSiteData(
        for pageURL: URL,
        in dataStore: WKWebsiteDataStore
    ) async {
        await clearSiteDataInStore(for: pageURL, in: dataStore)
        if let identifier = dataStore.identifier {
            let hostedID = BrowserLegacyExtensionWebsiteDataStore.identifier(forProfileID: identifier)
            if await WKWebsiteDataStore.allDataStoreIdentifiers.contains(hostedID) {
                await clearSiteDataInStore(for: pageURL, in: WKWebsiteDataStore(forIdentifier: hostedID))
            }
        }
    }

    private static func clearSiteDataInStore(for pageURL: URL, in dataStore: WKWebsiteDataStore) async {
        guard let host = pageURL.host()?.lowercased(), !host.isEmpty else { return }

        let cookieStore = dataStore.httpCookieStore
        let cookies = await allCookies(in: cookieStore)
        for cookie in cookies
        where BrowserSiteDataPolicy.includesCookieDomainForRemoval(
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
