import Foundation
import Security

/// The result inside a decrypted reply to a query.
struct ApplePasswordsQueryResult: Decodable, Sendable {
    // MARK: - Types

    /// One saved account. The sites are read only so a password can be matched
    /// to the frame's own host: a fill is bound to that host, never to a site a
    /// reply names.
    struct Entry: Decodable, Sendable {
        /// The username Apple shows in place of an account on a site where the person chose never to save.
        /// Apple's own text has non-breaking spaces, so names compare after any whitespace becomes one plain space.
        private static let neverSaveMarker = "Passwords not saved"

        let username: String?
        let password: String?
        let sites: [String]

        /// Whether this entry is the never-save marker rather than an account.
        var isNeverSaveMarker: Bool { username.map(Self.isNeverSaveMarker) ?? false }

        /// Whether `name` is the never-save marker, in Apple's spelling or with plain spaces.
        static func isNeverSaveMarker(_ name: String) -> Bool {
            name.split(whereSeparator: \.isWhitespace).joined(separator: " ") == neverSaveMarker
        }

        private enum CodingKeys: String, CodingKey {
            case username = "USR"
            case password = "PWD"
            case sites
        }

        /// A field of the wrong type is left empty rather than failing the reply:
        /// one odd entry must not unpair the session.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            username = try? container.decodeIfPresent(String.self, forKey: .username)
            password = try? container.decodeIfPresent(String.self, forKey: .password)
            sites = (try? container.decodeIfPresent([String].self, forKey: .sites)) ?? []
        }
    }

    /// One code a one-time-code reply lists, in the helper's own keys.
    private struct CodeEntry: Decodable {
        let code: ApplePasswordsOneTimeCode

        private enum CodingKeys: String, CodingKey {
            case source
            case code
            case username
            case domain
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = ApplePasswordsOneTimeCode(
                source: .named(try? container.decodeIfPresent(String.self, forKey: .source)),
                code: try? container.decodeIfPresent(String.self, forKey: .code),
                username: try? container.decodeIfPresent(String.self, forKey: .username),
                domain: try? container.decodeIfPresent(String.self, forKey: .domain))
        }
    }

    /// An element of `Entries` that is skipped when it is not an entry at all.
    private struct Lenient<Element: Decodable>: Decodable {
        let element: Element?

        init(from decoder: any Decoder) throws {
            element = try? Element(from: decoder)
        }
    }

    // MARK: - Variables

    let status: ApplePasswordsQueryStatus
    /// Every entry the reply carried, the never-save marker included.
    let entries: [Entry]
    /// Every one-time code the reply listed.
    let codes: [ApplePasswordsOneTimeCode]

    /// The accounts in the reply, without the never-save marker.
    var logins: [Entry] { entries.filter { !$0.isNeverSaveMarker } }
    /// Whether Apple reports that the person chose never to save passwords for the site.
    var neverSaves: Bool { entries.contains { $0.isNeverSaveMarker } }

    // MARK: - Initializers

    /// Entries arrive as `Entries`, or as one `Entry_<n>` key apiece.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = ApplePasswordsQueryStatus.numbered(try container.decode(Int.self, forKey: .status))
        entries = Self.elements(Entry.self, in: container)
        codes = Self.elements(CodeEntry.self, in: container).map(\.code)
    }

    private static func elements<Element: Decodable>(
        _ type: Element.Type, in container: KeyedDecodingContainer<CodingKeys>
    ) -> [Element] {
        var elements = ((try? container.decodeIfPresent([Lenient<Element>].self, forKey: .entries)) ?? []).compactMap(
            \.element)
        let numbered = container.allKeys.filter { $0.stringValue.hasPrefix(CodingKeys.numberedEntryPrefix) }
        for key in numbered.sorted(by: { $0.stringValue.localizedStandardCompare($1.stringValue) == .orderedAscending })
        {
            if let element = try? container.decode(Lenient<Element>.self, forKey: key).element {
                elements.append(element)
            }
        }
        return elements
    }

    private struct CodingKeys: CodingKey {
        static let numberedEntryPrefix = "Entry_"
        static let status = CodingKeys(stringValue: "STATUS")
        static let entries = CodingKeys(stringValue: "Entries")

        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// A request whose body is sealed with the paired session's key. The protocol
/// supplies the envelope and the sealing; a conformer says what it asks and
/// what the answer means.
protocol ApplePasswordsEncryptedRequest: ApplePasswordsRequest {
    associatedtype Body: Encodable & Sendable

    var session: ApplePasswordsSecretSession { get }
    var queryID: ApplePasswordsQueryID { get }
    /// A small per-launch integer naming the page the query is for.
    var tabID: Int { get }
    /// The frame's host: the only site the query is about.
    var host: String { get }
    /// The envelope's `url`, which a save leaves out.
    var envelopeURL: String? { get }
    var body: Body { get }

    /// What the decrypted result means.
    func reply(from result: ApplePasswordsQueryResult) throws -> Reply
}

extension ApplePasswordsEncryptedRequest {
    var envelopeURL: String? { host }

    func encoded() throws -> Data {
        let sealed = try session.message(sealing: body)
        let message = try String(decoding: JSONEncoder().encode(sealed), as: UTF8.self)
        let payload = ApplePasswordsQueryEnvelope.Payload(queryID: queryID.name, sealedMessage: message)
        return try JSONEncoder().encode(
            ApplePasswordsQueryEnvelope(
                number: command.number,
                tabID: tabID,
                frameID: 0,
                host: envelopeURL,
                payload: String(decoding: JSONEncoder().encode(payload), as: UTF8.self)
            )
        )
    }

    func reply(from envelope: ApplePasswordsInboundEnvelope) throws -> Reply {
        guard let message = envelope.payload?.sealedMessage else { throw ApplePasswordsError.malformedReply }
        return try reply(from: session.body(of: message, as: ApplePasswordsQueryResult.self))
    }
}

private struct ApplePasswordsQueryEnvelope: Encodable {
    struct Payload: Encodable {
        let queryID: String
        /// A JSON string, not an object.
        let sealedMessage: String

        private enum CodingKeys: String, CodingKey {
            case queryID = "QID"
            case sealedMessage = "SMSG"
        }
    }

    let number: Int
    let tabID: Int
    let frameID: Int
    /// Absent for a save, which names no URL in its envelope.
    let host: String?
    /// The payload's JSON, as a string.
    let payload: String

    private enum CodingKeys: String, CodingKey {
        case number = "cmd"
        case tabID = "tabId"
        case frameID = "frameId"
        case host = "url"
        case payload
    }
}
