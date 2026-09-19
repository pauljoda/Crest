using System.Text.Json;
using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One process may own several browsing-record workspaces. Only the persistent
/// workspace has a storage provider; borrowing a profile never borrows records.
public sealed partial class BrowserSessionKernel
{
    private sealed class Scope(BrowserKernel kernel, string mode, WorkspaceId? source = null, SpaceId? sourceSpace = null)
    {
        public BrowserKernel Kernel { get; } = kernel;
        public string Mode { get; } = mode;
        public WorkspaceId? Source { get; } = source;
        public SpaceId? SourceSpace { get; } = sourceSpace;
        public bool Closing { get; set; }
        public Outgoing? Release { get; set; }
        public bool Released { get; set; }
        public ProfileId? PrivateSourceProfile { get; init; }
        public HashSet<WindowId> WindowIds { get; } = [];
    }
    private readonly IReadOnlyList<Adapter> adapters;
    private readonly IIdSource ids;
    private readonly IClock clock;
    private readonly Dictionary<WorkspaceId, Scope> scopes = [];
    private readonly Dictionary<Guid, Scope> authentications = [];
    private readonly Scope persistent;
    private readonly string ui;
    private readonly Adapter engine;
    private ulong revision;
    private bool quiescing;
    private static readonly HashSet<string> ProfileCommands = ["core.rename_space", "core.select_search_provider",
        "core.upsert_search_provider", "core.remove_search_provider", "core.set_retention", "core.set_space_access",
        "core.lock_space", "core.unlock_space", "core.set_content_blocking", "core.retry_content_blocking"];
    public BrowserWorkspace Workspace => persistent.Kernel.Workspace;
    public IReadOnlyList<BrowserWorkspace> Workspaces => scopes.Values.Where(s => !s.Closing).Select(s => s.Kernel.Workspace).ToArray();
    public bool SaveFailed => persistent.Kernel.SaveFailed;
    public int PendingEffectCount => scopes.Values.Sum(s => s.Kernel.PendingEffectCount + (s.Release is not null && !s.Released ? 1 : 0))
        + (transfer is null ? 0 : 1) + deferredCommands.Count;
    public BrowserSessionKernel(IReadOnlyList<Adapter> adapters, IIdSource? ids = null, IClock? clock = null,
        JsonObject? initialState = null, bool persistSession = false)
    {
        this.adapters = adapters; this.ids = ids ?? new SystemIdSource(); this.clock = clock ?? new SystemClock();
        ui = adapters.Single(a => a.Role == "ui").Id; engine = adapters.Single(a => a.Role == "engine");
        persistent = new(new(adapters, this.ids, this.clock, initialState, persistSession), "persistent");
        scopes.Add(Workspace.Id, persistent);
    }
    public void BeginShutdown() { quiescing = true; foreach (var s in scopes.Values) s.Kernel.BeginShutdown(); }
    public void CancelShutdown() { quiescing = false; foreach (var s in scopes.Values.Where(s => !s.Closing)) s.Kernel.CancelShutdown(); }
    private Outgoing Failure(Envelope m, string code) => new(ui, "result", "core.operation_failed",
        new() { ["code"] = code }, ids.Next(), m.CorrelationId, m.Id);
    private static Envelope WithPayload(Envelope m, JsonObject payload) => m with
    { Payload = JsonDocument.Parse(payload.ToJsonString()).RootElement.Clone() };
    private Scope Route(Envelope m)
    {
        Scope? routed = null;
        var p = m.Payload;
        if (Protocol.OptionalId(p, "workspaceId") is { } explicitId)
            routed = scopes.GetValueOrDefault(new(explicitId)) ?? throw new BrowserRuleException("unknown_workspace");
        if (Protocol.OptionalId(p, "windowId") is { } window)
        {
            var owner = scopes.Values.SingleOrDefault(s => s.Kernel.Workspace.HasWindow(new(window)));
            if (owner is not null && routed is not null && owner != routed) throw new BrowserRuleException("wrong_workspace");
            routed ??= owner;
            if (m.Kind == "command" && m.Type != "core.open_window" && owner is null)
                throw new BrowserRuleException("unknown_window");
            if (m.Type == "engine.adoption_requested" && owner is null) throw new BrowserRuleException("source_page_not_presented");
        }
        var page = Protocol.OptionalId(p, "pageId") ?? Protocol.OptionalId(p, "sourcePageId");
        if (page is { } pageID)
        {
            var owner = scopes.Values.SingleOrDefault(s => s.Kernel.Workspace.Spaces.Any(space => space.Tabs.Any(t => t.PageId?.Value == pageID)));
            if (owner is null) throw new BrowserRuleException("stale_page");
            if (routed is not null && owner != routed) throw new BrowserRuleException("wrong_workspace");
            routed = owner;
        }
        if (m.Type == "platform.authentication_completed" && m.CausationId is { } cause)
            routed = authentications.GetValueOrDefault(cause) ?? throw new BrowserRuleException("stale_authentication");
        return routed ?? persistent;
    }
    private void Append(List<Outgoing> output, Scope scope, IEnumerable<Outgoing> messages)
    {
        foreach (var window in scope.Kernel.Workspace.Windows) scope.WindowIds.Add(window.Id);
        foreach (var original in messages)
        {
            var body = (JsonObject)original.Payload.DeepClone();
            if (original.Kind == "projection")
            {
                body["revision"] = (++revision).ToString();
                if (original.Type == "ui.snapshot")
                { body["workspaceMode"] = scope.Mode; body["workspaceClosing"] = scope.Closing; }
            }
            if (original.Kind == "effect" && original.Recipient == engine.Id)
            {
                body["workspaceId"] = scope.Kernel.Workspace.Id.Value.ToString();
                body["profileMode"] = IsPrivate(scope) ? "private" : "regular";
                body["privateSourceProfileId"] = PrivateSource(scope)?.Value.ToString();
            }
            if (original.Type == "platform.authenticate_space") authentications[original.Id] = scope;
            if (original.Type == "platform.cancel_authentication" && Guid.TryParse(body["requestId"]?.GetValue<string>(), out var request))
                authentications.Remove(request);
            output.Add(original with { Payload = body });
        }
    }
    private bool IsPrivate(Scope scope) => scope.Mode == "private" || scope.Source is { } source && IsPrivate(scopes[source]);
    private ProfileId? PrivateSource(Scope scope) => scope.PrivateSourceProfile ?? (scope.Source is { } source ? PrivateSource(scopes[source]) : null);
    private void Create(Envelope m, List<Outgoing> output)
    {
        var p = m.Payload;
        Protocol.Members(p, "windowId", "sourceWorkspaceId", "spaceId", "mode");
        if (quiescing) throw new BrowserRuleException("session_closing");
        var mode = Protocol.Text(p, "mode");
        if (mode is not ("private" or "borrowed")) throw new BrowserRuleException("invalid_workspace_mode");
        if (!engine.Supports("workspace-profiles")) throw new BrowserRuleException("capability_unavailable");
        var window = new WindowId(Protocol.Id(p, "windowId"));
        if (scopes.Values.Any(s => s.Kernel.Workspace.HasWindow(window))) throw new BrowserRuleException("duplicate_window");
        var source = scopes.GetValueOrDefault(new(Protocol.Id(p, "sourceWorkspaceId"))) ?? throw new BrowserRuleException("unknown_workspace");
        if (source.Closing) throw new BrowserRuleException("profile_lease_revoked");
        if (source.Source is { } owner) source = scopes[owner];
        var sourceSpace = source.Kernel.Workspace.Space(new(Protocol.Id(p, "spaceId"))); sourceSpace.EnsureAccessible();
        var state = sourceSpace.Capture(null) with { Tabs = [], Folders = [], Archive = [], History = [] };
        if (mode == "private") state = state with
        {
            Id = new(ids.Next()), ProfileId = new(ids.Next()), Name = "Private", RequiresAuthentication = false,
            SupportsDeviceAuthentication = true, Search = SearchPreferences.Default.Select("duckDuckGo", false),
            Retention = RetentionPreferences.Default with { CurrentTabs = CurrentTabCleanup.Never }
        };
        var workspace = new WorkspaceState(new(ids.Next()), state.Id, state.Id, [state], []);
        var document = new LegacySessionDocument().Write(workspace);
        var scope = new Scope(new(adapters, ids, clock, document, privateBrowsing: mode == "private"), mode,
            mode == "borrowed" ? source.Kernel.Workspace.Id : null, mode == "borrowed" ? sourceSpace.Id : null)
        { PrivateSourceProfile = mode == "private" ? PrivateSource(source) ?? sourceSpace.ProfileId : null };
        if (mode == "borrowed") scope.Kernel.Workspace.Space(state.Id).ReconcileBorrowedPolicy(sourceSpace);
        scopes.Add(workspace.Id, scope);
        Append(output, scope, scope.Kernel.Process(WithPayload(m with { Type = "core.open_window" },
            new() { ["windowId"] = window.Value.ToString() })));
    }
    public IReadOnlyList<Outgoing> Process(Envelope message)
    {
        var output = new List<Outgoing>();
        try
        {
            if (transfer is not null && (message.Kind == "command"
                || message.Type is "engine.open_requested" or "engine.reveal_requested" or "engine.adoption_requested" or "platform.memory_pressure"))
            {
                int bytes = message.Payload.GetRawText().Length * 2 + 512;
                if (deferredBytes + bytes > 8_388_608) throw new BrowserRuleException("operation_busy");
                deferredCommands.Enqueue((message, bytes)); deferredBytes += bytes; return output;
            }
            if (ProcessTransferObservation(message, output)) { }
            else if (message.Type == "core.transfer_tab") BeginTransfer(message, output);
            else if (message.Type == "core.create_workspace") Create(message, output);
            else if (message.Type == "engine.workspace_released") ReleaseCompleted(message, output);
            else
            {
                var scope = Route(message);
                if (scope.Closing && message.Kind == "command" && message.Type != "core.close_window")
                    throw new BrowserRuleException("workspace_closing");
                var body = JsonNode.Parse(message.Payload.GetRawText())!.AsObject(); body.Remove("workspaceId");
                if (message.Type == "engine.adoption_requested") body.Remove("windowId");
                var m = WithPayload(message, body);
                if (m.Type == "core.unlock_space" && scopes.Values.Any(s => s.Kernel.AuthenticationEffect is not null))
                    throw new BrowserRuleException("authentication_busy");
                if (m.Type is "core.lock_all" or "core.maintain_session" or "core.snapshot" or "core.release_inactive_pages" or "platform.memory_pressure")
                {
                    foreach (var s in scopes.Values.Where(s => !s.Closing && (m.Type != "core.lock_all" || s.Mode != "borrowed")).ToArray())
                        Append(output, s, s.Kernel.Process(m));
                }
                else if (scope.Source is { } owner && ProfileCommands.Contains(m.Type))
                {
                    // The source remains the sole writer of borrowed profile policy.
                    // The requesting window was validated against its own workspace above.
                    var authority = scopes[owner];
                    if (authority.Closing) throw new BrowserRuleException("profile_lease_revoked");
                    if (new SpaceId(Protocol.Id(m.Payload, "spaceId")) != scope.SourceSpace)
                        throw new BrowserRuleException("wrong_profile");
                    Append(output, authority, authority.Kernel.Process(m, profileAuthority: true));
                }
                else
                {
                    if (scope.Mode == "borrowed" && m.Type is "core.create_space" or "core.delete_space" or "core.retry_space_deletion")
                        throw new BrowserRuleException("borrowed_workspace_fixed_profile");
                    Append(output, scope, scope.Kernel.Process(m));
                }
                foreach (var request in authentications.Where(a => a.Value.Kernel.AuthenticationEffect != a.Key).Select(a => a.Key).ToArray())
                    authentications.Remove(request);
                if (m.Type == "core.close_window" && scope != persistent && scope.Kernel.Workspace.Windows.Count == 0)
                    CloseScope(scope, message, output);
            }
            ReconcileBorrowers(message, output);
            ReleaseReadyScopes(message, output);
            foreach (var scope in scopes.Values.Where(s => !s.Closing).ToArray())
            {
                var released = scope.Kernel.Workspace.SpaceDeletions.Where(d => !d.Completed &&
                    !scopes.Values.Any(b => b.Source == scope.Kernel.Workspace.Id && b.SourceSpace == d.Space && !b.Released))
                    .Select(d => d.Space).ToHashSet();
                Append(output, scope, scope.Kernel.ContinueDeletions(message, released));
            }
        }
        catch (BrowserRuleException error) { RejectInvalidAdoption(message, output); output.Add(Failure(message, error.Code)); }
        catch (Exception error) when (error is ProtocolException or InvalidOperationException or KeyNotFoundException or FormatException)
        { RejectInvalidAdoption(message, output); output.Add(Failure(message, "invalid_payload")); }
        if (!drainingDeferred)
        {
            drainingDeferred = true;
            try
            {
                while (transfer is null && deferredCommands.TryDequeue(out var next))
                { deferredBytes -= next.Bytes; output.AddRange(Process(next.Message)); }
            }
            finally { drainingDeferred = false; }
        }
        return output;
    }
    private void RejectInvalidAdoption(Envelope m, List<Outgoing> output)
    {
        if (m.Type != "engine.adoption_requested" || !m.Payload.TryGetProperty("adoptionId", out var token)
            || token.ValueKind != JsonValueKind.String || !Guid.TryParseExact(token.GetString(), "D", out var id) || id == Guid.Empty) return;
        output.Add(new(engine.Id, "effect", "engine.reject_adoption", new() { ["adoptionId"] = id.ToString() },
            ids.Next(), m.CorrelationId, m.Id));
    }
    private void CloseScope(Scope scope, Envelope m, List<Outgoing> output)
    {
        if (scope.Closing) return;
        if (scope.Kernel.AuthenticationEffect is { } request)
        {
            output.Add(new(adapters.Single(a => a.Role == "platform").Id, "effect", "platform.cancel_authentication",
                new() { ["requestId"] = request.ToString() }, ids.Next(), m.CorrelationId, m.Id));
            authentications.Remove(request);
        }
        scope.Closing = true;
        Append(output, scope, scope.Kernel.BeginWorkspaceClosure(m));
        foreach (var dependent in scopes.Values.Where(s => s.Source == scope.Kernel.Workspace.Id)) CloseScope(dependent, m, output);
    }
    private void ReconcileBorrowers(Envelope m, List<Outgoing> output)
    {
        foreach (var borrowed in scopes.Values.Where(s => s.Source is not null && !s.Closing).ToArray())
        {
            var source = scopes[borrowed.Source!.Value];
            var original = source.Kernel.Workspace.Spaces.SingleOrDefault(s => s.Id == borrowed.SourceSpace);
            var local = borrowed.Kernel.Workspace.Spaces.Single();
            if (source.Closing || original is null || original.IsDeleting || original.ProfileId != local.ProfileId)
            { CloseScope(borrowed, m, output); continue; }
            if (local.Name == original.Name && local.Search == original.Search && local.Retention == original.Retention
                && local.ContentBlocking == original.ContentBlocking
                && local.RequiresAuthentication == original.RequiresAuthentication && local.IsLocked == original.IsLocked
                && local.AccessGeneration == original.AccessGeneration) continue;
            local.ReconcileBorrowedPolicy(original);
            Append(output, borrowed, borrowed.Kernel.Refresh(m));
        }
    }
    private void ReleaseReadyScopes(Envelope m, List<Outgoing> output)
    {
        foreach (var scope in scopes.Values.Where(s => s.Closing && s.Release is null && !s.Released && s.Kernel.PendingEffectCount == 0))
        {
            if (scope.Source is { } sourceId && scope.SourceSpace is { } sourceSpace
                && scopes[sourceId].Kernel.Workspace.SpaceDeletions.Any(d => d.Space == sourceSpace)
                && !scopes[sourceId].Kernel.IsDeletionDurable(sourceSpace)) continue;
            // Owning profiles outlive every borrower, including their native teardown.
            if (scopes.Values.Any(s => s.Source == scope.Kernel.Workspace.Id && !s.Released)) continue;
            var profiles = scope.Source is null ? scope.Kernel.Workspace.Spaces.Select(s => (JsonNode)JsonValue.Create(s.ProfileId.Value.ToString())!).ToArray() : [];
            var release = new Outgoing(engine.Id, "effect", "engine.release_workspace", new()
            {
                ["workspaceId"] = scope.Kernel.Workspace.Id.Value.ToString(), ["releaseProfiles"] = new JsonArray(profiles),
                ["windowIds"] = new JsonArray(scope.WindowIds.Select(w => (JsonNode)JsonValue.Create(w.Value.ToString())!).ToArray()),
                ["profileMode"] = IsPrivate(scope) ? "private" : "regular"
            }, ids.Next(), m.CorrelationId, m.Id);
            scope.Release = release; output.Add(release);
        }
    }
    private void ReleaseCompleted(Envelope m, List<Outgoing> output)
    {
        Protocol.Members(m.Payload, "workspaceId");
        var id = new WorkspaceId(Protocol.Id(m.Payload, "workspaceId"));
        if (!scopes.TryGetValue(id, out var scope) || scope.Release is not { } release || scope.Released
            || release.Id != m.CausationId || release.CorrelationId != m.CorrelationId) throw new BrowserRuleException("unknown_workspace_release");
        scope.Released = true;
        output.Add(new(ui, "projection", "ui.workspace_removed", new()
        { ["revision"] = (++revision).ToString(), ["workspaceId"] = id.Value.ToString() }, ids.Next(), m.CorrelationId, m.Id));
        // Keep the owner until its dependents have acknowledged native disposal.
        if (!scopes.Values.Any(s => s.Source == id && !s.Released))
        {
            foreach (var dependent in scopes.Where(s => s.Value.Source == id && s.Value.Released).Select(s => s.Key).ToArray()) scopes.Remove(dependent);
            if (scope.Source is null || !scopes[scope.Source.Value].Closing) scopes.Remove(id);
        }
    }
}
