import AppKit

extension BrowserMacAgents {
    // MARK: - Actions - Connections

    func admit(_ connection: BrowserAgentConnection) {
        guard listener != nil, links.count < Self.maximumConnections else {
            connection.close()
            return
        }
        let link = Link(connection: connection)
        let key = ObjectIdentifier(link)
        links[key] = link
        connection.open { [weak self] line in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(line, on: key) } }
        } ended: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.forget(key) } }
        }
    }

    /// The helper hung up: the agent is no longer connected.
    private func forget(_ key: ObjectIdentifier) {
        guard let link = links.removeValue(forKey: key) else { return }
        release(link)
    }

    func end(_ link: Link) {
        link.connection.close()
        links[ObjectIdentifier(link)] = nil
        release(link)
    }

    /// Lets go of what `link`'s agent held: its pages render and keep
    /// activity for it no more, and the core disconnects it.
    private func release(_ link: Link) {
        approvals.withdraw(ObjectIdentifier(link))
        for tabID in Set(link.heldPages.keys).union(link.observedPages.keys) { letGo(tabID, of: link) }
        guard let sessionID = link.sessionID else { return }
        link.sessionID = nil
        let name = core.state.agentSessions.first { $0.sessionID == sessionID }?.name ?? link.agent?.agentName
        _ = try? core.send(EndAgentSession(sessionID: sessionID))
        if let name {
            BrowserNoticeCenter.shared.post(
                BrowserNotice(message: String(localized: "\(name) stopped using Crest"), systemImage: "sparkles"))
        }
    }

    /// Lets `link` go of tab `tabID`'s page: it renders and keeps activity
    /// for agents no more once no other connection uses it, since the engine
    /// keeps one of each per page.
    func letGo(_ tabID: UUID, of link: Link) {
        let page = agentPage(tabID)?.enginePage
        let others = links.values.filter { $0 !== link }
        if let held = link.heldPages.removeValue(forKey: tabID), page?.id == held,
            !others.contains(where: { $0.heldPages[tabID] == held })
        {
            page?.holdRendering(false, size: .zero)
        }
        if let observed = link.observedPages.removeValue(forKey: tabID), page?.id == observed,
            !others.contains(where: { $0.observedPages[tabID] == observed })
        {
            page?.observeActivity(false)
        }
        link.lastInput[tabID] = nil
    }

    // MARK: - Actions - Requests

    private func receive(_ line: Data, on key: ObjectIdentifier) {
        guard let link = links[key] else { return }
        guard let request = try? JSONDecoder().decode(AgentLinkRequest.self, from: line) else {
            end(link)
            return
        }
        request.handle(on: self, from: link)
    }

    /// The helper behind `link` introduced the agent `client`, speaking link
    /// `version`.
    func attach(_ link: Link, version: Int, client: AgentClientInfo?) {
        guard version == AgentLinkRequest.version else {
            reply(.refused(reason: .staleHelper), on: link)
            link.connection.close()
            return
        }
        guard core.state.agentPreferences.isOn else {
            reply(.refused(reason: .agentsOff), on: link)
            return
        }
        link.client = client
        link.isAttached = true
        reply(.attached(tools: AgentToolDefinition.catalog), on: link)
    }

    /// The agent behind `link` called tool `name` with `arguments`, as call
    /// `id`, which is answered once the tool finishes.
    func call(_ id: Int, name: String, arguments: AgentJSON, from link: Link) {
        let key = ObjectIdentifier(link)
        Task { [weak self] in
            guard let self else { return }
            let result = await perform(name, arguments: arguments, on: link)
            guard links[key] != nil else { return }
            reply(.result(id: id, result: result), on: link)
        }
    }

    private func reply(_ response: AgentLinkResponse, on link: Link) {
        guard var line = try? JSONEncoder().encode(response) else { return }
        // An answer longer than the helper reads would end the agent's whole
        // connection, so that one call fails instead.
        if line.count > AgentLinkResponse.maximumBytes, case .result(let id, _) = response,
            let refusal = try? JSONEncoder().encode(
                AgentLinkResponse.result(id: id, result: .error(BrowserAgentFailure.tooLarge.message)))
        {
            line = refusal
        }
        link.connection.send(line)
    }

    /// Answers the agent's call of tool `name`, once the person allowed the
    /// agent.
    private func perform(_ name: String, arguments: AgentJSON, on link: Link) async -> AgentToolResult {
        guard link.isAttached else { return .error(BrowserAgentFailure.notAttached.message) }
        do throws(BrowserAgentFailure) {
            let sessionID = try await session(for: link)
            guard let tool = BrowserAgentTool.named(name) else { throw .unknownTool(name) }
            return try await tool.perform(
                BrowserAgentCall(agents: self, link: link, sessionID: sessionID, arguments: arguments))
        } catch {
            return .error(error.message)
        }
    }

    /// The agent's connection in the core: begun now when the person already
    /// allowed it, or after they allow it when it is new. Calls that arrive
    /// while it begins share it, as an agent's first calls often come
    /// together.
    private func session(for link: Link) async throws(BrowserAgentFailure) -> UUID {
        if let sessionID = link.sessionID { return sessionID }
        if let beginning = link.beginning { return try await beginning.value.get() }
        let beginning = Task { await self.begin(link) }
        link.beginning = beginning
        let begun = await beginning.value
        link.beginning = nil
        return try begun.get()
    }

    private func begin(_ link: Link) async -> Result<UUID, BrowserAgentFailure> {
        do throws(BrowserAgentFailure) {
            return .success(try await beginSession(for: link))
        } catch {
            return .failure(error)
        }
    }

    private func beginSession(for link: Link) async throws(BrowserAgentFailure) -> UUID {
        guard core.state.agentPreferences.isOn else { throw .rejected(.agentsOff(AgentsOff())) }
        guard let agent = link.agent else { throw .unidentified }
        let sessionID = UUID()
        do {
            _ = try core.send(BeginAgentSession(sessionID: sessionID, identity: agent.identity, name: agent.agentName))
        } catch .agentNotApproved {
            try await approvals.approve(agent, client: link.client, for: ObjectIdentifier(link))
            guard links[ObjectIdentifier(link)] != nil, core.state.agentPreferences.isOn else { throw .declined }
            do {
                _ = try core.send(ApproveAgent(agent: ApprovedAgent(identity: agent.identity, name: agent.agentName)))
                _ = try core.send(
                    BeginAgentSession(sessionID: sessionID, identity: agent.identity, name: agent.agentName))
            } catch {
                throw .rejected(error)
            }
        } catch {
            throw .rejected(error)
        }
        link.sessionID = sessionID
        BrowserNoticeCenter.shared.post(
            BrowserNotice(message: String(localized: "\(agent.agentName) is using Crest"), systemImage: "sparkles"))
        return sessionID
    }

}
