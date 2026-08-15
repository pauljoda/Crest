import Foundation

/// Reads Google's Omaha `response=updatecheck` document.
///
/// The answer Crest cares about is three attributes deep and nothing more:
///
/// ```xml
/// <gupdate protocol="2.0">
///   <app appid="…" status="ok">
///     <updatecheck status="ok" version="4.9.129" codebase="…"/>
///   </app>
/// </gupdate>
/// ```
///
/// An up-to-date answer collapses to `<updatecheck status="noupdate"/>`, and a
/// delisted or mistyped identifier answers at the `app` level with a status
/// such as `error-unknownApplication`.
///
/// The parser only accepts an `app` element whose `appid` echoes the extension
/// Crest asked about, so a response that answers for some other extension is
/// rejected rather than quietly applied to the wrong installation.
final class BrowserChromeWebStoreUpdateCheckParser:
    NSObject,
    XMLParserDelegate
{
    /// Real answers run a few hundred bytes. This bound keeps a hostile or
    /// misrouted response from becoming an XML parsing workload.
    static let maximumResponseByteCount = 64 * 1_024

    private let expectedID: BrowserChromeExtensionID
    private var isInsideMatchingApplication = false
    private var didFindMatchingApplication = false
    private var applicationStatus: String?
    private var updateCheckStatus: String?
    private var publishedVersion: String?

    private init(expectedID: BrowserChromeExtensionID) {
        self.expectedID = expectedID
    }

    static func check(
        in data: Data,
        expectedID: BrowserChromeExtensionID
    ) throws -> BrowserChromeWebStoreUpdateCheck {
        guard !data.isEmpty else {
            throw BrowserChromeWebStoreUpdateCheckError.malformedDocument
        }
        guard data.count <= maximumResponseByteCount else {
            throw BrowserChromeWebStoreUpdateCheckError.responseTooLarge
        }
        let reader = BrowserChromeWebStoreUpdateCheckParser(
            expectedID: expectedID
        )
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw BrowserChromeWebStoreUpdateCheckError.malformedDocument
        }
        return try reader.result()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        let element = elementName.lowercased()
        let values = Self.lowercasedKeys(of: attributes)
        switch element {
        case "app":
            guard !didFindMatchingApplication,
                let identifier = values["appid"]?.lowercased(),
                identifier == expectedID.rawValue
            else {
                return
            }
            didFindMatchingApplication = true
            isInsideMatchingApplication = true
            applicationStatus = values["status"]
        case "updatecheck":
            guard isInsideMatchingApplication else { return }
            updateCheckStatus = values["status"]
            publishedVersion = values["version"]
        default:
            return
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        guard elementName.lowercased() == "app" else { return }
        isInsideMatchingApplication = false
    }

    private func result() throws -> BrowserChromeWebStoreUpdateCheck {
        guard didFindMatchingApplication else {
            throw BrowserChromeWebStoreUpdateCheckError.identityMismatch
        }
        guard let applicationStatus, applicationStatus.lowercased() == "ok"
        else {
            throw BrowserChromeWebStoreUpdateCheckError.applicationUnavailable(
                applicationStatus ?? "missing status"
            )
        }
        switch updateCheckStatus?.lowercased() {
        case "ok":
            guard
                let version = publishedVersion?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                !version.isEmpty
            else {
                throw BrowserChromeWebStoreUpdateCheckError.malformedDocument
            }
            return BrowserChromeWebStoreUpdateCheck(
                extensionID: expectedID,
                publishedVersion: version
            )
        case "noupdate":
            return BrowserChromeWebStoreUpdateCheck(
                extensionID: expectedID,
                publishedVersion: nil
            )
        case .none:
            throw BrowserChromeWebStoreUpdateCheckError.malformedDocument
        case .some(let status):
            throw BrowserChromeWebStoreUpdateCheckError.applicationUnavailable(
                status
            )
        }
    }

    private static func lowercasedKeys(
        of attributes: [String: String]
    ) -> [String: String] {
        var values: [String: String] = [:]
        values.reserveCapacity(attributes.count)
        for (key, value) in attributes {
            values[key.lowercased()] = value
        }
        return values
    }
}
