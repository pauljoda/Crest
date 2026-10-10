import Foundation

// The parameters each automation method reads and the results it answers,
// as they cross the socket. Keys are the protocol's; they never change once
// published.

// MARK: - Parameters

/// What `hello` sends: the protocol version the tool speaks and the name it
/// goes by.
struct BrowserAutomationHello: Decodable {
    struct Client: Decodable {
        let name: String
        let version: String?
    }

    let `protocol`: Int
    let client: Client
}

/// A method that reads no parameters.
struct BrowserAutomationNoParameters: Decodable {}

/// Which Space's tabs `tabs.list` lists, or every Space's.
struct BrowserAutomationTabQuery: Decodable {
    let space: UUID?
}

/// Where `tabs.open` opens a tab, the address it loads, and whether it comes
/// forward.
struct BrowserAutomationTabOpening: Decodable {
    let space: UUID
    let url: String
    let show: Bool?
}

/// The tab a method acts on.
struct BrowserAutomationTabReference: Decodable {
    let tab: UUID
}

// MARK: - Results

/// What `hello` answers: the protocol version, Crest's version, and the
/// methods the tool may call.
struct BrowserAutomationGreeting: Encodable {
    struct Crest: Encodable {
        let version: String
    }

    let `protocol`: Int
    let crest: Crest
    let methods: [String]
}

/// The Spaces a tool reaches.
struct BrowserAutomationSpaceList: Encodable {
    struct Space: Encodable {
        let id: UUID
        let name: String
        let locked: Bool
    }

    let spaces: [Space]
}

/// A tab as a tool reads it. A tab that shows no web page has no `url`.
struct BrowserAutomationTab: Encodable {
    let id: UUID
    let space: UUID
    let title: String
    let url: String?
    let placement: String
    let shown: Bool
}

struct BrowserAutomationTabList: Encodable {
    let tabs: [BrowserAutomationTab]
}

struct BrowserAutomationTabAnswer: Encodable {
    let tab: BrowserAutomationTab
}

struct BrowserAutomationClosed: Encodable {
    let closed: Bool
}
