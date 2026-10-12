using CrestCore.Contracts;

namespace CrestCore.Application;

/// The agents connected now, in the order they connected, with the tabs each
/// uses, and the tabs the person stopped each agent using, which hold for
/// every connection of that agent. The core keeps them in memory only: after
/// a relaunch no agent is connected and none is stopped anywhere. The
/// device's lock guards every call.
internal sealed class AgentSessions {
    #region Static Variables

    /// The most agents connected at once, and the most tabs one uses.
    public const int MaximumSessions = 16;
    public const int MaximumTabs = 64;

    #endregion

    #region Variables

    private readonly List<AgentSessionState> sessions = [];
    private readonly Dictionary<AgentIdentity, HashSet<Guid>> stopped = [];

    /// Every agent connected now.
    public IReadOnlyList<AgentSessionState> All => sessions;

    /// The tabs some agent uses, which keep their pages loaded and their place
    /// while it does.
    public IReadOnlySet<Guid> HeldTabs => sessions.SelectMany(session => session.TabIds).ToHashSet();

    /// The tabs the person stopped agent `identity` using.
    public IReadOnlySet<Guid> Stopped(AgentIdentity identity) =>
        stopped.TryGetValue(identity, out var tabs) ? tabs : new HashSet<Guid>();

    #endregion

    #region Actions - Sessions

    public AgentSessionState? Find(Guid sessionId) => sessions.FirstOrDefault(session => session.SessionId == sessionId);

    /// Connects agent `identity` as `sessionId`, named `name`. Answers whether
    /// that changed anything; refused with `AgentSessionsFull` past
    /// `MaximumSessions`.
    public bool Begin(Guid sessionId, AgentIdentity identity, string name) {
        if (Find(sessionId) is not null) return false;
        if (sessions.Count >= MaximumSessions) throw new Rejected(new AgentSessionsFull(MaximumSessions));
        sessions.Add(new AgentSessionState(sessionId, identity, name, null, []));
        return true;
    }

    /// The agent connected as `sessionId` goes by `name` and `color` from now
    /// on, or keeps what it had for either it leaves out.
    public bool Identify(Guid sessionId, string? name, BrandColor? color) =>
        Revise(sessionId, session => session with { Name = name ?? session.Name, Color = color ?? session.Color });

    /// The agent connected as `sessionId` uses `tabId` from now on. Refused
    /// with `AgentTabStopped` for a tab the person stopped that agent using,
    /// through any of its connections.
    public bool Claim(Guid sessionId, Guid tabId) {
        var session = Find(sessionId) ?? throw new Rejected(new UnknownAgentSession(sessionId));
        if (Stopped(session.Identity).Contains(tabId)) throw new Rejected(new AgentTabStopped(tabId));
        if (session.TabIds.Contains(tabId)) return false;
        if (session.TabIds.Count >= MaximumTabs) throw new Rejected(new AgentTabUnavailable(tabId));
        return Revise(sessionId, current => current with { TabIds = [.. current.TabIds, tabId] });
    }

    /// The person stopped every agent using `tabId`: none uses it any more,
    /// and no connection of those agents may take it again while Crest runs.
    public bool Stop(Guid tabId) {
        bool changed = false;
        for (int index = 0; index < sessions.Count; index++) {
            var session = sessions[index];
            if (!session.TabIds.Contains(tabId)) continue;
            if (!stopped.TryGetValue(session.Identity, out var tabs)) stopped[session.Identity] = tabs = [];
            tabs.Add(tabId);
            sessions[index] = session with { TabIds = [.. session.TabIds.Where(candidate => candidate != tabId)] };
            changed = true;
        }
        return changed;
    }

    /// Disconnects the agents `ends` names.
    public bool End(Func<AgentSessionState, bool> ends) => sessions.RemoveAll(session => ends(session)) > 0;

    /// Forgets where the person stopped the agents `forgets` names, as when
    /// they forget an agent or turn agents off.
    public void Unstop(Func<AgentIdentity, bool> forgets) {
        foreach (var identity in stopped.Keys.Where(forgets).ToList()) stopped.Remove(identity);
    }

    /// Lets each agent go of the tabs `reachable` says it may no longer use.
    public bool Prune(Func<Guid, bool> reachable) {
        bool changed = false;
        for (int index = 0; index < sessions.Count; index++) {
            var session = sessions[index];
            if (session.TabIds.All(reachable)) continue;
            sessions[index] = session with { TabIds = [.. session.TabIds.Where(reachable)] };
            changed = true;
        }
        return changed;
    }

    #endregion

    #region Mutators

    private bool Revise(Guid sessionId, Func<AgentSessionState, AgentSessionState> revise) {
        int index = sessions.FindIndex(session => session.SessionId == sessionId);
        if (index < 0) throw new Rejected(new UnknownAgentSession(sessionId));
        var revised = revise(sessions[index]);
        if (revised.Equals(sessions[index])) return false;
        sessions[index] = revised;
        return true;
    }

    #endregion
}
