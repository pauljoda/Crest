import Foundation

/// A method a tool may call, by the name it calls it with. Each reads its own
/// parameters and answers its own result, so a new method is one instance
/// here and the work it does on `BrowserMacAutomation`.
@MainActor
struct BrowserAutomationMethod {
    // MARK: - Static Variables

    static let hello = Self(name: "hello", isOpen: true) {
        (automation, parameters: BrowserAutomationHello, session) async throws(BrowserAutomationError) in
        try await automation.hello(parameters, in: session)
    }
    static let listSpaces = Self(name: "spaces.list") {
        (automation, _: BrowserAutomationNoParameters, _) throws(BrowserAutomationError) in
        try automation.listSpaces()
    }
    static let listTabs = Self(name: "tabs.list") {
        (automation, parameters: BrowserAutomationTabQuery, _) throws(BrowserAutomationError) in
        try automation.listTabs(parameters)
    }
    static let openTab = Self(name: "tabs.open") {
        (automation, parameters: BrowserAutomationTabOpening, _) throws(BrowserAutomationError) in
        try automation.openTab(parameters)
    }
    static let closeTab = Self(name: "tabs.close") {
        (automation, parameters: BrowserAutomationTabReference, _) async throws(BrowserAutomationError) in
        try await automation.closeTab(parameters)
    }
    static let showTab = Self(name: "tabs.show") {
        (automation, parameters: BrowserAutomationTabReference, _) throws(BrowserAutomationError) in
        try automation.showTab(parameters)
    }

    static let all: [Self] = [hello, listSpaces, listTabs, openTab, closeTab, showTab]

    /// The methods a tool may call once the person approved it, as `hello`
    /// lists them.
    static var approvedNames: [String] { all.filter { !$0.isOpen }.map(\.name) }

    // MARK: - Variables

    let name: String
    /// Whether a tool may call it before the person approved the tool.
    let isOpen: Bool
    private let perform:
        @MainActor (BrowserMacAutomation, BrowserAutomationRequest, BrowserMacAutomation.Session)
            async throws(BrowserAutomationError) -> Data

    // MARK: - Initializers

    private init<Parameters: Decodable, Result: Encodable>(
        name: String, isOpen: Bool = false,
        perform:
            @escaping @MainActor (BrowserMacAutomation, Parameters, BrowserMacAutomation.Session)
            async throws(BrowserAutomationError) -> Result
    ) {
        self.name = name
        self.isOpen = isOpen
        self.perform = { automation, request, session throws(BrowserAutomationError) in
            request.answer(try await perform(automation, try request.parameters(Parameters.self), session))
        }
    }

    // MARK: - Actions - Requests

    /// The method a request names, or nil for one Crest does not have.
    static func named(_ name: String) -> Self? {
        all.first { $0.name == name }
    }

    /// Reads `request`'s parameters, does what the method does on
    /// `automation` for `session`'s tool, and answers the response.
    func answer(
        _ request: BrowserAutomationRequest, on automation: BrowserMacAutomation,
        in session: BrowserMacAutomation.Session
    ) async throws(BrowserAutomationError) -> Data {
        try await perform(automation, request, session)
    }
}
