import AppKit

extension BrowserMacAgents {
    // MARK: - Types

    private struct PrivateOpening: Decodable {
        let url: String?
    }

    private struct PrivateReceipt: Encodable {
        let windowID: UUID
    }

    // MARK: - Actions - Windows

    /// Private creation grants no capability to enumerate or later act on its contents.
    func openPrivateWindow(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        _ = try reach(call)
        let opening = try call.arguments(PrivateOpening.self)
        let url = try opening.url.map(Self.address)
        windows.openPrivateWindow()
        if let url, application.privateBrowser.openNewTab(url: url) == nil {
            throw .refused("Crest could not open the private address.")
        }
        return .data(PrivateReceipt(windowID: application.privatePages.windowID))
    }
}

extension BrowserMacAgents {
    // MARK: - Types

    private struct WindowOpening: Decodable {
        let space: UUID?
        let url: String?
    }

    private struct WindowReceipt: Encodable {
        let windowID: UUID
        let spaceID: UUID
        let tabID: UUID?
    }

    // MARK: - Actions - Windows

    func openWindow(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        let space = try resolveSpace(opening.space, call)
        let url = try opening.url.map(Self.address)
        let window = try openWindow(over: space)
        var tabID: UUID?
        if let url {
            guard let opened = window.browser.openNewTab(url: url, in: space.id, selecting: true) else {
                throw .refused("Crest could not open the address in this Space.")
            }
            _ = try claim(opened, call)
            tabID = opened
        }
        bringForward(window)
        return .data(WindowReceipt(windowID: window.id, spaceID: space.id, tabID: tabID))
    }

    func openBlankWindow(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        guard opening.url == nil else { throw .invalidArguments("a Blank Window does not take a URL.") }
        let space = try resolveSpace(opening.space, call)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserMacWindowRequest.temporary(sourceWindowID: nil, assignment: assignment)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else { throw .noWindow }
        bringForward(window)
        return .data(WindowReceipt(windowID: window.id, spaceID: space.id, tabID: nil))
    }

    func openQuickWindow(_ call: BrowserAgentCall) throws(BrowserAgentFailure) -> AgentToolResult {
        let opening = try call.arguments(WindowOpening.self)
        guard let text = opening.url else { throw .invalidArguments("url is missing.") }
        let url = try Self.address(text)
        let space = try resolveSpace(opening.space, call)
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: space.profileID)
        let request = BrowserQuickWindowRequest(url: url, spaceAssignment: assignment)
        windows.openQuickWindow(request)
        guard windows.quickWindow(request.id) != nil else { throw .noWindow }
        return .data(WindowReceipt(windowID: request.id, spaceID: space.id, tabID: nil))
    }

    /// Opening a window happens only for explicit window and show-tab commands.
    func openWindow(over space: SpaceModel) throws(BrowserAgentFailure) -> BrowserMacWindowModel {
        let request = BrowserMacWindowRequest.normal(sourceWindowID: nil)
        windows.open(request, activation: .key)
        guard let window = application.windowCoordinator.existingModel(for: request.id) else { throw .noWindow }
        window.browser.selectSpace(space.id)
        return window
    }
}
