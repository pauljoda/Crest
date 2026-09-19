using System.Text.Json;
using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed record Outgoing(string Recipient, string Kind, string Type, JsonObject Payload,
    Guid Id, Guid CorrelationId, Guid? CausationId);

/// Processes one message at a time. Effects are data, never calls into a native provider.
public sealed partial class BrowserKernel
{
    private sealed record Pending(string Type, Guid Operation, SpaceId Space, TabId Tab, WindowId Window);
    private sealed record SurfaceAssignment(Guid Effect, Guid Operation);
    private sealed record Handoff(Envelope Command, WindowId Source, WindowId Destination, SpaceId Space, TabId Tab,
        TabId SourceSelection, SpaceId DestinationSpace, TabId? DestinationSelection);
    private sealed record Authentication(Guid Effect, Envelope Command, SpaceId Space, ProfileId Profile, ulong Generation);
    private Authentication? authenticating;
    private readonly Dictionary<WindowId, Handoff> handoffs = [];
    private readonly Dictionary<WindowId, Handoff> attachingHandoffs = [];
    private readonly IIdSource ids;
    private readonly IClock clock;
    private readonly BrowserWorkspace workspace;
    private readonly Adapter engine;
    private readonly Adapter platform;
    private readonly Adapter? services;
    private readonly string ui;
    private readonly string? storage;
    private readonly LegacySessionDocument document;
    private JsonObject? savedState;
    private bool persistenceDirty;
    private (Guid Id, Guid Operation, ulong Revision, JsonObject State)? saving;
    private ulong saveRevision;
    public bool SaveFailed { get; private set; }
    private readonly Dictionary<Guid, Pending> pending = [];
    private readonly Dictionary<TabId, Guid> creations = [];
    private readonly Dictionary<TabId, Guid> closeOperations = [];
    private readonly Dictionary<TabId, string> closeReasons = [];
    private DateTimeOffset? lastMaintained;
    private readonly HashSet<Guid> adoptedNativePages = [];
    private readonly Dictionary<WindowId, Guid> leases = [];
    private readonly Dictionary<WindowId, SurfaceAssignment> surfaceAssignments = [];
    private readonly List<Outgoing> output = [];
    private ulong revision;
    private bool quiescing;
    private bool workspaceClosing;
    private readonly HashSet<WindowId> closingSurfaces = [];
    private readonly bool privateBrowsing;
    public BrowserWorkspace Workspace => workspace;
    internal Guid? AuthenticationEffect => authenticating?.Effect;
    internal bool HasPresentationWork => handoffs.Count != 0 || attachingHandoffs.Count != 0 || surfaceAssignments.Count != 0;
    public int PendingEffectCount => pending.Count + handoffs.Count + attachingHandoffs.Count + deletionEffects.Count
        + closingSurfaces.Count + contentBlockingEffects.Count + (saving is null ? 0 : 1);
    public void BeginShutdown() { quiescing = true; authenticating = null; }
    public void CancelShutdown() => quiescing = false;
    internal IReadOnlyList<Outgoing> BeginWorkspaceClosure(Envelope m)
    {
        output.Clear(); workspaceClosing = true; BeginShutdown();
        foreach (var handoff in handoffs.Values.Concat(attachingHandoffs.Values)) Result(handoff.Command, "canceled");
        handoffs.Clear(); attachingHandoffs.Clear();
        foreach (var window in workspace.Windows)
        {
            var effect = ids.Next(); var lease = ids.Next(); leases[window.Id] = lease;
            surfaceAssignments[window.Id] = new(effect, m.CorrelationId); closingSurfaces.Add(window.Id);
            Emit(m, platform.Id, "effect", "platform.assign_surface", new()
            { ["windowId"] = window.Id.Value.ToString(), ["leaseId"] = lease.ToString() }, effect);
        }
        Snapshot(m); return output.ToArray();
    }

    public BrowserKernel(IReadOnlyList<Adapter> adapters, IIdSource? ids = null, IClock? clock = null,
        JsonObject? initialState = null, bool persistSession = false, bool privateBrowsing = false)
    {
        this.ids = ids ?? new SystemIdSource();
        this.clock = clock ?? new SystemClock();
        this.privateBrowsing = privateBrowsing;
        engine = adapters.Single(a => a.Role == "engine");
        platform = adapters.Single(a => a.Role == "platform");
        services = adapters.SingleOrDefault(a => a.Role == "services");
        ui = adapters.Single(a => a.Role == "ui").Id;
        Require(engine, "pages"); Require(engine, "navigation"); Require(platform, "surfaces");
        if (persistSession)
        {
            var services = adapters.Single(a => a.Role == "services"); Require(services, "session-storage"); storage = services.Id;
        }
        document = new(initialState);
        if (initialState is not null)
        {
            workspace = BrowserWorkspace.Restore(document.Read(this.ids), this.ids, this.clock, engine.Supports("internal-pages"));
            savedState = document.Write(workspace.Capture());
        }
        else
        {
            workspace = new(new(this.ids.Next()), this.ids, this.clock, engine.Supports("internal-pages"));
            workspace.AddSpace("Personal"); workspace.AddSpace("Work");
            persistenceDirty = true;
        }
    }
    private static void Require(Adapter adapter, string capability)
    {
        if (!adapter.Supports(capability)) throw new BrowserRuleException("capability_unavailable");
    }
    private void Emit(Envelope m, string recipient, string kind, string type, JsonObject body, Guid? id = null)
        => output.Add(new(recipient, kind, type, body, id ?? ids.Next(), m.CorrelationId, m.Id));
    private void Result(Envelope m, string? failure = null)
        => Emit(m, ui, "result", failure is null ? "core.operation_completed" : "core.operation_failed",
            new() { ["code"] = failure ?? "completed" });
    private void Effect(Envelope m, string type, BrowserSpace space, BrowserTab tab, WindowId window, Guid? adoption = null)
    {
        var id = ids.Next();
        pending.Add(id, new(type, m.CorrelationId, space.Id, tab.Id, window));
        var payload = Page(space, tab, window);
        if (adoption is { } token) payload["adoptionId"] = token.ToString();
        Emit(m, engine.Id, "effect", type, payload, id);
        if (type is "engine.create_page" or "engine.adopt_page") creations.Add(tab.Id, id);
    }
    private static JsonObject Page(BrowserSpace space, BrowserTab tab, WindowId window) => new()
    {
        ["spaceId"] = space.Id.Value.ToString(), ["profileId"] = space.ProfileId.Value.ToString(),
        ["tabId"] = tab.Id.Value.ToString(), ["pageId"] = tab.PageId?.Value.ToString(),
        ["generation"] = tab.Generation.ToString(), ["windowId"] = window.Value.ToString(), ["url"] = tab.Url,
        ["contentBlockingPolicy"] = LegacySessionDocument.EnumName(space.ContentBlocking)
    };
    private void Present(Envelope m, BrowserWindow window)
    {
        if (handoffs.Values.Any(h => h.Source == window.Id || h.Destination == window.Id)) return;
        var space = workspace.Space(window.SpaceId);
        var tab = window.Selection(space.Id) is { } selected ? space.Tab(selected) : null;
        var members = workspace.PresentedTabs(window.Id);
        foreach (var member in members)
        {
            if (!quiescing && member is { Kind: TabKind.Web, Phase: TabPhase.Dormant })
            {
                member.CreatePage(new(ids.Next()), engine.Supports("internal-pages"));
                Effect(m, "engine.create_page", space, member, window.Id);
            }
        }
        var body = space.IsLocked || tab is null or { Kind: TabKind.Web, Phase: TabPhase.Creating or TabPhase.Dormant }
            ? new JsonObject { ["windowId"] = window.Id.Value.ToString() } : Page(space, tab, window.Id);
        var lease = ids.Next(); leases[window.Id] = lease;
        var pages = new JsonArray();
        foreach (var member in members.Where(t => t.Kind == TabKind.Web && t.Phase is TabPhase.Ready or TabPhase.Closing))
            pages.Add((JsonNode)Page(space, member, window.Id));
        body["pages"] = pages;
        body["panes"] = new JsonArray(members.Select(member => (JsonNode)new JsonObject
        {
            ["tabId"] = member.Id.Value.ToString(), ["spaceId"] = space.Id.Value.ToString(),
            ["kind"] = member.NativeKind ?? member.Kind.ToString().ToLowerInvariant(),
            ["pageId"] = member.Kind == TabKind.Web && member.Phase is TabPhase.Ready or TabPhase.Closing
                ? member.PageId?.Value.ToString() : null
        }).ToArray());
        body["leaseId"] = lease.ToString();
        var effect = ids.Next();
        surfaceAssignments[window.Id] = new(effect, m.CorrelationId);
        Emit(m, platform.Id, "effect", "platform.assign_surface", body, effect);
    }
    private (BrowserSpace Space, BrowserTab Tab) Target(JsonElement p, bool requireAccess = true)
    {
        var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
        if (requireAccess) space.EnsureAccessible();
        return (space, space.Tab(new(Protocol.Id(p, "tabId"))));
    }
    private bool Select(Envelope m, WindowId destination, SpaceId space, TabId? tab)
    {
        _ = workspace.Window(destination); workspace.Space(space).EnsureAccessible();
        if (tab is { } existing) _ = workspace.Space(space).Tab(existing);
        CancelConflictingHandoffs(m, destination, tab);
        if (tab is { } selected && workspace.PresentingWindow(space, selected) is { } source && source.Id != destination)
        {
            if (workspace.Space(space).SplitMembers(selected).Any(t => t.Phase == TabPhase.Closing)) throw new BrowserRuleException("page_closing");
            var destinationWindow = workspace.Window(destination);
            var handoff = new Handoff(m, source.Id, destination, space, selected, source.Selection(space)!.Value,
                destinationWindow.SpaceId, destinationWindow.Selection(destinationWindow.SpaceId));
            handoffs.Add(source.Id, handoff);
            var effect = ids.Next(); var lease = ids.Next(); leases[source.Id] = lease;
            surfaceAssignments[source.Id] = new(effect, m.CorrelationId);
            Emit(m, platform.Id, "effect", "platform.assign_surface", new()
            { ["windowId"] = source.Id.Value.ToString(), ["leaseId"] = lease.ToString() }, effect);
            return false;
        }
        workspace.Select(destination, space, tab); Present(m, workspace.Window(destination)); return true;
    }
    private void CancelHandoff(Envelope m, Handoff handoff)
    {
        handoffs.Remove(handoff.Source);
        if (!quiescing && workspace.Windows.Any(w => w.Id == handoff.Source)) Present(m, workspace.Window(handoff.Source));
        Result(handoff.Command, "canceled");
    }
    private void CancelConflictingHandoffs(Envelope m, WindowId? window, TabId? tab = null)
    {
        bool Conflicts(Handoff h) => h.Source == window || h.Destination == window || tab is { } id &&
            workspace.Space(h.Space).SplitMembers(h.Tab).Any(t => t.Id == id);
        foreach (var handoff in handoffs.Values.Where(Conflicts).ToArray())
            CancelHandoff(m, handoff);
        foreach (var handoff in attachingHandoffs.Values.Where(Conflicts).ToArray())
        {
            RollbackHandoff(m, handoff);
            Result(handoff.Command, "canceled");
        }
    }
    private void RollbackHandoff(Envelope m, Handoff handoff)
    {
        attachingHandoffs.Remove(handoff.Destination);
        var destination = workspace.Window(handoff.Destination);
        workspace.Select(destination.Id, destination.SpaceId, null);
        if (!quiescing) Present(m, destination);
        workspace.Select(handoff.Source, handoff.Space, handoff.SourceSelection);
        var oldTab = handoff.DestinationSelection;
        if (oldTab is { } id && (!workspace.Space(handoff.DestinationSpace).Tabs.Any(t => t.Id == id)
            || workspace.PresentingWindow(handoff.DestinationSpace, id) is not null)) oldTab = null;
        workspace.Select(destination.Id, handoff.DestinationSpace, oldTab);
        persistenceDirty = true;
        if (!quiescing) { Present(m, workspace.Window(handoff.Source)); Present(m, destination); }
    }
    private Pending Completion(Envelope m, params string[] expected)
    {
        if (m.CausationId is not { } cause || !pending.TryGetValue(cause, out var work)
            || !expected.Contains(work.Type) || m.CorrelationId != work.Operation)
            throw new BrowserRuleException("unknown_effect");
        return work;
    }
    private static void ValidatePage(JsonElement p, BrowserTab tab)
    {
        if (new PageId(Protocol.Id(p, "pageId")) != tab.PageId || Protocol.Counter(p, "generation") != tab.Generation)
            throw new BrowserRuleException("stale_page");
    }
    private void OpenTab(Envelope m, WindowId window, BrowserSpace space, string? url, TabKind kind, bool foreground)
    {
        var tab = workspace.Open(window, space.Id, url, kind, foreground);
        persistenceDirty = true;
        if (foreground) CancelConflictingHandoffs(m, window);
        if (kind == TabKind.Web)
        {
            if (foreground) Present(m, workspace.Window(window));
            Effect(m, "engine.create_page", space, tab, window);
        }
        else { if (foreground) Present(m, workspace.Window(window)); Result(m); }
        Snapshot(m);
    }
    public IReadOnlyList<Outgoing> Process(Envelope m, bool profileAuthority = false)
    {
        output.Clear();
        try
        {
            if (m.Kind == "command")
            {
                Command(m, profileAuthority);
                if (m.Type is not ("core.snapshot" or "core.query_records" or "core.navigate" or "core.back" or "core.forward" or "core.reload" or "core.stop" or "core.maintain_session" or "core.release_inactive_pages"))
                    persistenceDirty = true;
            }
            else Observation(m);
        }
        catch (BrowserRuleException error) { Result(m, error.Code); }
        catch (Exception error) when (error is ProtocolException or KeyNotFoundException or InvalidOperationException or FormatException)
        { Result(m, "invalid_payload"); }
        Persist(m);
        return output.ToArray();
    }
    private void Persist(Envelope m)
    {
        if (storage is null || !persistenceDirty || saving is not null || SaveFailed) return;
        var state = document.Write(workspace.Capture());
        persistenceDirty = false;
        if (JsonNode.DeepEquals(state, savedState)) return;
        var id = ids.Next(); var next = ++saveRevision;
        saving = (id, m.CorrelationId, next, state);
        Emit(m, storage, "effect", "services.save_session", new()
        { ["revision"] = next.ToString(), ["state"] = state.DeepClone() }, id);
    }
    internal IReadOnlyList<Outgoing> Refresh(Envelope m)
    {
        output.Clear(); PresentAll(m); Snapshot(m); return output.ToArray();
    }
    internal void TransferTabTo(BrowserKernel destination, SpaceId space, TabId tab, WindowId window)
    {
        workspace.TransferTabTo(destination.workspace, space, tab, window);
        document.TransferTabMetadata(tab, destination.document);
        persistenceDirty = true; destination.persistenceDirty = true;
    }
    internal IReadOnlyList<Outgoing> PublishTransferredState(Envelope m)
    { output.Clear(); PresentAll(m); Snapshot(m); Persist(m); return output.ToArray(); }
    private void Command(Envelope m, bool profileAuthority)
    {
        var p = m.Payload;
        switch (m.Type)
        {
            case "core.release_inactive_pages": ReleaseInactivePages(m); return;
            case "core.query_records": QueryRecords(m); return;
            case "core.open_records":
            {
                Protocol.Members(p, "windowId", "spaceId", "kind");
                var window = new WindowId(Protocol.Id(p, "windowId")); var space = new SpaceId(Protocol.Id(p, "spaceId"));
                var tab = workspace.OpenRecords(window, space, Protocol.Text(p, "kind", 32));
                if (!Select(m, window, space, tab.Id)) return;
                break;
            }
            case "core.open_history_entry":
            {
                Protocol.Members(p, "windowId", "spaceId", "entryId");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                var visit = space.HistoryEntry(Protocol.Id(p, "entryId"));
                OpenTab(m, window, space, visit.Url, TabKind.Web, true); return;
            }
            case "core.delete_history_entry": case "core.clear_history":
            case "core.delete_archived_tab": case "core.clear_archive":
            {
                Protocol.Members(p, "windowId", "spaceId", "entryId");
                _ = workspace.Window(new(Protocol.Id(p, "windowId")));
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                if (m.Type == "core.delete_history_entry") space.DeleteHistoryEntry(Protocol.Id(p, "entryId"));
                else if (m.Type == "core.delete_archived_tab") space.DeleteArchivedTab(new(Protocol.Id(p, "entryId")));
                else if (m.Type == "core.clear_history") space.ClearHistory();
                else space.ClearArchive();
                break;
            }
            case "core.open_window":
                Protocol.Members(p, "windowId");
                var openedWindow = workspace.AddWindow(new(Protocol.Id(p, "windowId")));
                if (openedWindow.Selection(openedWindow.SpaceId) is not null) Present(m, openedWindow);
                break;
            case "core.close_window":
                Protocol.Members(p, "windowId");
                var closedWindow = new WindowId(Protocol.Id(p, "windowId"));
                if (!workspace.HasWindow(closedWindow)) throw new BrowserRuleException("unknown_window");
                CancelConflictingHandoffs(m, closedWindow);
                workspace.CloseWindow(closedWindow); leases.Remove(closedWindow); surfaceAssignments.Remove(closedWindow);
                closingSurfaces.Remove(closedWindow); break;
            case "core.bind_window_scene":
                Protocol.Members(p, "windowId", "sceneId");
                workspace.BindWindowScene(new(Protocol.Id(p, "windowId")), Protocol.Text(p, "sceneId", 512)); break;
            case "core.create_space":
                Protocol.Members(p, "name"); workspace.AddSpace(Protocol.Text(p, "name", 200), privateBrowsing); break;
            case "core.rename_space":
                Protocol.Members(p, "spaceId", "name");
                workspace.Space(new(Protocol.Id(p, "spaceId"))).Rename(Protocol.Text(p, "name", 200)); break;
            case "core.delete_space":
            case "core.retry_space_deletion":
            {
                Protocol.Members(p, "windowId", "spaceId");
                _ = workspace.Window(new(Protocol.Id(p, "windowId")));
                Require(engine, "profile-deletion");
                if (services is null) throw new BrowserRuleException("capability_unavailable");
                Require(services, "space-data-deletion");
                var space = new SpaceId(Protocol.Id(p, "spaceId"));
                if (m.Type == "core.retry_space_deletion")
                {
                    if (!workspace.Space(space).IsDeleting) throw new BrowserRuleException("space_not_deleting");
                    deletionFailures.Remove(space); SaveFailed = false;
                }
                else
                {
                    // Validate before canceling presentation or authentication work.
                    workspace.Space(space).EnsureAccessible();
                    if (workspace.Spaces.Count(s => !s.IsDeleting) <= 1) throw new BrowserRuleException("cannot_delete_last_space");
                    CancelSpaceHandoffs(m, space); CancelAuthentication(m, space);
                    workspace.BeginSpaceDeletion(space);
                }
                PresentAll(m); break;
            }
            case "core.set_space_access":
            case "core.lock_space":
            case "core.unlock_space":
            {
                Protocol.Members(p, "windowId", "spaceId", "requiresAuthentication");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                if (!profileAuthority && workspace.Window(new(Protocol.Id(p, "windowId"))).SpaceId != space.Id)
                    throw new BrowserRuleException("space_not_selected");
                if (m.Type == "core.unlock_space")
                {
                    if (space.IsDeleting) throw new BrowserRuleException("space_deleting");
                    if (!space.IsLocked) break;
                    if (!space.SupportsDeviceAuthentication) throw new BrowserRuleException("unsupported_access_policy");
                    Require(platform, "device-authentication");
                    if (authenticating is not null) throw new BrowserRuleException("authentication_busy");
                    var effect = ids.Next();
                    authenticating = new(effect, m, space.Id, space.ProfileId, space.AccessGeneration);
                    Emit(m, platform.Id, "effect", "platform.authenticate_space", new()
                    {
                        ["spaceId"] = space.Id.Value.ToString(), ["profileId"] = space.ProfileId.Value.ToString(),
                        ["generation"] = space.AccessGeneration.ToString(), ["name"] = space.Name
                    }, effect);
                    return;
                }
                if (m.Type == "core.set_space_access")
                {
                    Require(platform, "device-authentication");
                    space.EnsureAccessible();
                    // Validate the policy before canceling any active presentation work.
                    _ = p.GetProperty("requiresAuthentication").GetBoolean();
                }
                CancelSpaceHandoffs(m, space.Id); CancelAuthentication(m, space.Id);
                if (m.Type == "core.set_space_access") space.SetAccessPolicy(p.GetProperty("requiresAuthentication").GetBoolean());
                else space.Lock();
                PresentAll(m); break;
            }
            case "core.lock_all":
                Protocol.Members(p);
                // Native authentication temporarily deactivates the scene itself.
                if (authenticating is not null) break;
                foreach (var space in workspace.Spaces.Where(s => s.RequiresAuthentication))
                { CancelSpaceHandoffs(m, space.Id); space.Lock(); }
                PresentAll(m); break;
            case "core.new_tab":
            {
                Protocol.Members(p, "windowId", "spaceId");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                var space = workspace.Space(new(Protocol.Id(p, "spaceId"))); space.EnsureAccessible();
                var draft = space.Tabs.FirstOrDefault(t => t.Kind == TabKind.StartPage && t.Placement == TabPlacement.Current
                    && (workspace.PresentingWindow(space.Id, t.Id) is not { } owner || owner.Id == window));
                if (draft is null) { OpenTab(m, window, space, null, TabKind.StartPage, true); return; }
                if (!Select(m, window, space.Id, draft.Id)) return;
                break;
            }
            case "core.open_tab":
            case "core.open_settings":
            {
                Protocol.Members(p, "windowId", "spaceId", "url", "disposition");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                string disposition = Protocol.Text(p, "disposition");
                if (disposition is not ("foreground" or "background")) throw new BrowserRuleException("invalid_disposition");
                var kind = m.Type == "core.open_settings" ? TabKind.Settings : TabKind.Web;
                OpenTab(m, window, space, Protocol.OptionalText(p, "url"), kind, disposition == "foreground");
                return;
            }
            case "core.switch_space":
            {
                Protocol.Members(p, "windowId", "spaceId");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                var selectedSpace = new SpaceId(Protocol.Id(p, "spaceId"));
                if (workspace.Space(selectedSpace).IsDeleting) throw new BrowserRuleException("space_deleting");
                if (workspace.Space(selectedSpace).IsLocked)
                {
                    CancelConflictingHandoffs(m, window);
                    workspace.Switch(window, selectedSpace); Present(m, workspace.Window(window));
                }
                else if (!Select(m, window, selectedSpace, workspace.Window(window).Selection(selectedSpace))) return;
                break;
            }
            case "core.select_tab":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                var id = Protocol.OptionalId(p, "tabId");
                if (!Select(m, window, new(Protocol.Id(p, "spaceId")), id is null ? null : new TabId(id.Value))) return;
                break;
            }
            case "core.close_tab":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId");
                var window = new WindowId(Protocol.Id(p, "windowId")); _ = workspace.Window(window);
                var (space, tab) = Target(p);
                if (tab.Phase == TabPhase.Unloading) throw new BrowserRuleException("page_unloading");
                CancelConflictingHandoffs(m, null, tab.Id);
                if (tab.Kind != TabKind.Web || tab.Phase is TabPhase.Failed or TabPhase.Dormant)
                { workspace.Close(space.Id, tab.Id); PresentAll(m); break; }
                bool creating = tab.Phase == TabPhase.Creating;
                tab.RequestClose(); closeOperations.Add(tab.Id, m.CorrelationId);
                if (!creating) Effect(m, "engine.close_page", space, tab, window);
                Snapshot(m); return;
            }
            case "core.navigate": case "core.back": case "core.forward": case "core.reload": case "core.stop":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId", "url");
                var window = new WindowId(Protocol.Id(p, "windowId")); _ = workspace.Window(window);
                var (space, tab) = Target(p);
                if (tab.Kind != TabKind.Web || tab.Phase != TabPhase.Ready) throw new BrowserRuleException("page_not_ready");
                if (m.Type == "core.navigate") BrowserWorkspace.ValidateUrl(Protocol.Text(p, "url"), engine.Supports("internal-pages"));
                if ((m.Type == "core.back" && !tab.CanGoBack) || (m.Type == "core.forward" && !tab.CanGoForward))
                    throw new BrowserRuleException("history_unavailable");
                var body = Page(space, tab, window);
                if (m.Type == "core.navigate") body["url"] = Protocol.Text(p, "url");
                Emit(m, engine.Id, "effect", m.Type.Replace("core.", "engine."), body);
                Result(m); return;
            }
            case "core.navigate_input":
            {
                Protocol.Members(p, "windowId", "spaceId", "input");
                var window = workspace.Window(new(Protocol.Id(p, "windowId")));
                var space = workspace.Space(new(Protocol.Id(p, "spaceId"))); space.EnsureAccessible();
                if (window.SpaceId != space.Id) throw new BrowserRuleException("space_not_selected");
                var url = space.Search.Resolve(Protocol.Text(p, "input", 4096), engine.Supports("internal-pages"));
                if (window.Selection(space.Id) is { } selected && space.Tab(selected) is { Kind: TabKind.Web } tab)
                {
                    if (tab.Phase != TabPhase.Ready) throw new BrowserRuleException("page_not_ready");
                    var body = Page(space, tab, window.Id); body["url"] = url;
                    Emit(m, engine.Id, "effect", "engine.navigate", body); Result(m);
                }
                else if (window.Selection(space.Id) is { } draftId && space.Tab(draftId) is
                    { Kind: TabKind.StartPage, Placement: TabPlacement.Current } draft)
                {
                    draft.NavigateStartPage(url, new(ids.Next()), engine.Supports("internal-pages"));
                    persistenceDirty = true;
                    Present(m, window); Effect(m, "engine.create_page", space, draft, window.Id); Snapshot(m);
                }
                else OpenTab(m, window.Id, space, url, TabKind.Web, true);
                return;
            }
            case "core.select_search_provider":
            {
                Protocol.Members(p, "windowId", "spaceId", "providerId", "suggestionsEnabled");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                space.SetSearch(space.Search.Select(Protocol.Text(p, "providerId", 128), p.GetProperty("suggestionsEnabled").GetBoolean()));
                break;
            }
            case "core.upsert_search_provider":
            {
                Protocol.Members(p, "windowId", "spaceId", "providerId", "name", "searchTemplate", "suggestionTemplate");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                space.SetSearch(space.Search.Upsert(SearchProvider.Custom(Protocol.Id(p, "providerId"), Protocol.Text(p, "name", 64),
                    Protocol.Text(p, "searchTemplate", 2048), Protocol.OptionalText(p, "suggestionTemplate", 2048))));
                break;
            }
            case "core.remove_search_provider":
            {
                Protocol.Members(p, "windowId", "spaceId", "providerId");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                space.SetSearch(space.Search.Remove(Protocol.Id(p, "providerId"))); break;
            }
            case "core.create_folder":
            {
                Protocol.Members(p, "spaceId", "name", "location", "parentId");
                var parent = Protocol.OptionalId(p, "parentId");
                workspace.Space(new(Protocol.Id(p, "spaceId"))).AddFolder(new(ids.Next()), Protocol.Text(p, "name", 128),
                    ReadPlacement(p, "location", TabPlacement.Saved), parent is { } id ? new FolderId(id) : null); break;
            }
            case "core.rename_folder": case "core.collapse_folder": case "core.delete_folder":
            {
                Protocol.Members(p, "spaceId", "folderId", "name", "collapsed");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId"))); var folder = new FolderId(Protocol.Id(p, "folderId"));
                if (m.Type == "core.rename_folder") space.RenameFolder(folder, Protocol.Text(p, "name", 128));
                else if (m.Type == "core.collapse_folder") space.CollapseFolder(folder, p.GetProperty("collapsed").GetBoolean(), clock.Now);
                else space.DeleteFolder(folder, clock.Now);
                break;
            }
            case "core.file_tabs":
            {
                Protocol.Members(p, "spaceId", "tabIds", "location", "folderId", "beforeTabId", "beforeFolderId", "detachSplitMembers");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                var requested = p.GetProperty("tabIds");
                if (requested.ValueKind != JsonValueKind.Array || requested.GetArrayLength() is 0 or > BrowserSpace.MaximumTabs)
                    throw new ProtocolException("invalid_tab_ids");
                var tabIds = requested.EnumerateArray().Select(e => new TabId(Protocol.Id(e))).ToArray();
                var folder = Protocol.OptionalId(p, "folderId"); var beforeTab = Protocol.OptionalId(p, "beforeTabId");
                var beforeFolder = Protocol.OptionalId(p, "beforeFolderId");
                space.FileTabs(tabIds, ReadPlacement(p, "location", TabPlacement.Saved), folder is { } f ? new FolderId(f) : null,
                    clock.Now, beforeTab is { } a ? new TabId(a) : null, beforeFolder is { } b ? new FolderId(b) : null,
                    p.TryGetProperty("detachSplitMembers", out var detach) && detach.GetBoolean()); break;
            }
            case "core.move_folder":
            {
                Protocol.Members(p, "spaceId", "folderId", "location", "parentId", "beforeFolderId", "beforeTabId");
                var parent = Protocol.OptionalId(p, "parentId"); var beforeFolder = Protocol.OptionalId(p, "beforeFolderId");
                var beforeTab = Protocol.OptionalId(p, "beforeTabId");
                workspace.Space(new(Protocol.Id(p, "spaceId"))).MoveFolder(new(Protocol.Id(p, "folderId")),
                    p.TryGetProperty("location", out _) ? ReadPlacement(p, "location", TabPlacement.Saved) : null,
                    parent is { } f ? new FolderId(f) : null, clock.Now, beforeFolder is { } b ? new FolderId(b) : null,
                    beforeTab is { } a ? new TabId(a) : null); break;
            }
            case "core.place_tab":
            {
                Protocol.Members(p, "spaceId", "tabId", "placement", "folderId");
                var (space, tab) = Target(p);
                if (!Enum.TryParse<TabPlacement>(Protocol.Text(p, "placement"), true, out var placement) || !Enum.IsDefined(placement))
                    throw new BrowserRuleException("invalid_placement");
                var folder = Protocol.OptionalId(p, "folderId");
                workspace.PlaceTab(space.Id, tab.Id, placement, folder is null ? null : new FolderId(folder.Value)); break;
            }
            case "core.duplicate_tab":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId");
                var window = new WindowId(Protocol.Id(p, "windowId")); var (space, tab) = Target(p);
                if (workspace.Window(window).SpaceId != space.Id) throw new BrowserRuleException("space_not_selected");
                var copy = space.DuplicateTab(tab.Id, ids, clock.Now); document.CopyTabMetadata(tab.Id, copy.Id);
                Select(m, window, space.Id, copy.Id); break;
            }
            case "core.join_split":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId", "targetTabId", "memberIndex");
                var window = new WindowId(Protocol.Id(p, "windowId")); var (space, tab) = Target(p);
                if (workspace.Window(window).SpaceId != space.Id) throw new BrowserRuleException("space_not_selected");
                var targetId = new TabId(Protocol.Id(p, "targetTabId"));
                // Current pages must be owned by this window before joining; durable
                // sources are copied and do not move their existing native pages.
                foreach (var member in new[] { tab, space.Tab(targetId) }.Where(t => t.Placement == TabPlacement.Current))
                    if (workspace.PresentingWindow(space.Id, member.Id) is { } owner && owner.Id != window)
                        throw new BrowserRuleException("page_presented_in_another_window");
                CancelConflictingHandoffs(m, window);
                var joined = space.JoinSplit(tab.Id, new(Protocol.Id(p, "targetTabId")),
                    p.TryGetProperty("memberIndex", out var index) ? index.GetInt32() : null, ids, clock.Now);
                foreach (var (source, copy) in joined.Copies) document.CopyTabMetadata(source, copy);
                if (!Select(m, window, space.Id, joined.SelectedTab)) return;
                break;
            }
            case "core.leave_split":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId"); var (space, tab) = Target(p);
                if (workspace.Window(new(Protocol.Id(p, "windowId"))).SpaceId != space.Id)
                    throw new BrowserRuleException("space_not_selected");
                space.LeaveSplit(tab.Id, clock.Now); break;
            }
            case "core.rename_tab":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId", "title");
                var (space, tab) = Target(p); space.EnsureAccessible();
                workspace.RenameTab(space.Id, tab.Id, Protocol.OptionalText(p, "title", 4096)); break;
            }
            case "core.set_tab_residency":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId", "keepsPageLoaded");
                var (space, tab) = Target(p); space.EnsureAccessible();
                if (tab.Phase == TabPhase.Unloading) throw new BrowserRuleException("page_unloading");
                tab.SetResidency(p.GetProperty("keepsPageLoaded").GetBoolean()); break;
            }
            case "core.set_content_blocking": case "core.retry_content_blocking":
            {
                Protocol.Members(p, "windowId", "spaceId", "policy"); Require(engine, "content-blocking");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId"))); space.EnsureAccessible();
                if (m.Type == "core.set_content_blocking") space.SetContentBlocking(ReadEnum<ContentBlockingPolicy>(p, "policy"));
                contentBlockingFailures.Remove(space.Id); ApplyContentBlocking(m, space); break;
            }
            case "core.set_retention":
            {
                Protocol.Members(p, "windowId", "spaceId", "currentTabs", "history", "archive", "downloads");
                var space = workspace.Space(new(Protocol.Id(p, "spaceId")));
                space.SetRetention(new(ReadEnum<CurrentTabCleanup>(p, "currentTabs"), ReadEnum<DataRetention>(p, "history"),
                    ReadEnum<DataRetention>(p, "archive"), ReadEnum<DataRetention>(p, "downloads")));
                Maintain(m, publish: false, force: true); break;
            }
            case "core.maintain_session":
                Protocol.Members(p); Maintain(m); return;
            case "core.retry_save": Protocol.Members(p); SaveFailed = false; break;
            case "core.restore_tab":
            {
                Protocol.Members(p, "windowId", "spaceId", "tabId");
                var window = new WindowId(Protocol.Id(p, "windowId"));
                workspace.RestoreArchived(window, new(Protocol.Id(p, "spaceId")), new(Protocol.Id(p, "tabId")));
                CancelConflictingHandoffs(m, window);
                Present(m, workspace.Window(window)); break;
            }
            case "core.snapshot": Protocol.Members(p); break;
            default: throw new BrowserRuleException("unknown_command");
        }
        if (m.Type is "core.leave_split" or "core.place_tab" or "core.file_tabs" or "core.move_folder" or "core.delete_folder") PresentAll(m);
        Snapshot(m); Result(m);
    }
    private static T ReadEnum<T>(JsonElement p, string name) where T : struct, Enum
    {
        string text = Protocol.Text(p, name, 32);
        return Enum.TryParse<T>(text, true, out var value) && Enum.IsDefined(value)
            && LegacySessionDocument.EnumName(value) == text ? value : throw new BrowserRuleException("invalid_retention");
    }
    private void Maintain(Envelope m, bool publish = true, bool force = false)
    {
        var now = clock.Now;
        if (!force && lastMaintained is { } previous && now >= previous && now - previous < TimeSpan.FromMinutes(1)) return;
        lastMaintained = now;
        bool changed = false;
        foreach (var space in workspace.Spaces)
        {
            if (space.IsDeleting) continue;
            // Every window's remembered selection, and every member of its split,
            // remains protected even when that window is showing another Space.
            var protectedTabs = workspace.ProtectedTabs(space.Id);
            foreach (var tab in space.ExpiredTabs(now, protectedTabs))
            {
                if (tab.Kind == TabKind.Web && tab.Phase == TabPhase.Ready)
                {
                    if (workspace.Windows.FirstOrDefault() is not { } window) continue;
                    tab.RequestClose(); closeOperations.Add(tab.Id, m.CorrelationId); closeReasons.Add(tab.Id, "autoCleanup");
                    Effect(m, "engine.close_page", space, tab, window.Id);
                }
                else workspace.Close(space.Id, tab.Id, reason: "autoCleanup");
                changed = true;
            }
            changed |= space.PruneStoredRecords(now);
        }
        if (!changed) return;
        persistenceDirty = true; PresentAll(m); if (publish) Snapshot(m);
    }
    private void CancelAuthentication(Envelope m, SpaceId space)
    {
        if (authenticating is not { } request || request.Space != space) return;
        authenticating = null;
        Emit(m, platform.Id, "effect", "platform.cancel_authentication", new() { ["requestId"] = request.Effect.ToString() });
        Result(request.Command, "canceled");
    }
    private void CancelSpaceHandoffs(Envelope m, SpaceId space)
    {
        foreach (var window in workspace.Windows.Where(w => w.SpaceId == space).ToArray())
            CancelConflictingHandoffs(m, window.Id);
    }
    private void AdoptNativePage(Envelope m)
    {
        var p = m.Payload;
        Protocol.Members(p, "adoptionId", "profileId", "sourcePageId", "url", "foreground");
        var adoption = Protocol.Id(p, "adoptionId");
        try
        {
            if (quiescing || adoptedNativePages.Contains(adoption)) throw new BrowserRuleException("adoption_unavailable");
            var profile = new ProfileId(Protocol.Id(p, "profileId"));
            var space = workspace.Spaces.SingleOrDefault(s => s.ProfileId == profile)
                ?? throw new BrowserRuleException("unknown_profile");
            space.EnsureAccessible();
            var source = Protocol.OptionalId(p, "sourcePageId");
            var sourceTab = source is { } page ? space.Tabs.SingleOrDefault(t => t.PageId?.Value == page) : null;
            if (source is not null && sourceTab is null) throw new BrowserRuleException("wrong_profile");
            var window = (sourceTab is null ? null : workspace.PresentingWindow(space.Id, sourceTab.Id))
                ?? workspace.Windows.FirstOrDefault(w => w.SpaceId == space.Id)
                ?? throw new BrowserRuleException("source_page_not_presented");
            bool foreground = p.GetProperty("foreground").GetBoolean();
            var tab = workspace.Open(window.Id, space.Id, Protocol.Text(p, "url"), TabKind.Web, foreground);
            adoptedNativePages.Add(adoption); persistenceDirty = true;
            if (foreground) { CancelConflictingHandoffs(m, window.Id); Present(m, window); }
            Effect(m, "engine.adopt_page", space, tab, window.Id, adoption);
            Snapshot(m);
        }
        catch (BrowserRuleException error)
        {
            Emit(m, engine.Id, "effect", "engine.reject_adoption", new() { ["adoptionId"] = adoption.ToString() });
            Result(m, error.Code);
        }
        catch (Exception error) when (error is ProtocolException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            Emit(m, engine.Id, "effect", "engine.reject_adoption", new() { ["adoptionId"] = adoption.ToString() });
            Result(m, "invalid_payload");
        }
        return;
    }
    private void Observation(Envelope m)
    {
        var p = m.Payload;
        if (m.Type == "platform.memory_pressure") { ReleaseInactivePages(m); return; }
        if (m.Type is "engine.content_blocking_applied" or "engine.content_blocking_failed")
        { CompleteContentBlocking(m); return; }
        if (m.Type is "engine.profile_deleted" or "engine.profile_deletion_failed"
            or "services.space_data_deleted" or "services.space_data_deletion_failed")
        { CompleteDeletionEffect(m); return; }
        if (m.Type == "engine.adoption_requested") { AdoptNativePage(m); return; }
        if (m.Type is "services.session_saved" or "services.save_failed")
        {
            Protocol.Members(p, "revision", "code");
            if (saving is not { } save || m.CausationId != save.Id || m.CorrelationId != save.Operation
                || Protocol.Counter(p, "revision") != save.Revision) throw new BrowserRuleException("unknown_save");
            if (m.Type == "services.session_saved") savedState = save.State;
            else { SaveFailed = true; persistenceDirty = true; Result(m, "persistence_failed"); }
            saving = null; return;
        }
        if (m.Type == "platform.authentication_completed")
        {
            Protocol.Members(p, "spaceId", "profileId", "generation", "outcome");
            if (authenticating is not { } request || request.Effect != m.CausationId) return;
            if (request.Command.CorrelationId != m.CorrelationId || request.Space.Value != Protocol.Id(p, "spaceId")
                || request.Profile.Value != Protocol.Id(p, "profileId") || request.Generation != Protocol.Counter(p, "generation"))
                throw new BrowserRuleException("wrong_authentication_target");
            var outcome = Protocol.Text(p, "outcome");
            if (outcome is not ("succeeded" or "denied" or "unavailable" or "canceled"))
                throw new BrowserRuleException("invalid_authentication_outcome");
            authenticating = null;
            var unlockedSpace = workspace.Space(request.Space);
            if (!quiescing && outcome == "succeeded")
            { unlockedSpace.Unlock(request.Profile, request.Generation); PresentAll(m); Snapshot(m); Result(request.Command); }
            else Result(request.Command, "authentication_" + outcome);
            return;
        }
        if (m.Type is "platform.surface_attached" or "platform.failed")
        {
            Protocol.Members(p, "windowId", "leaseId", "code");
            var window = new WindowId(Protocol.Id(p, "windowId"));
            var lease = Protocol.Id(p, "leaseId");
            // Obsolete leases are harmless terminal observations. They cannot
            // acknowledge or fail the current assignment, even if delayed past window closure.
            if (leases.GetValueOrDefault(window) != lease) return;
            if (!surfaceAssignments.TryGetValue(window, out var assignment)
                || assignment.Effect != m.CausationId || assignment.Operation != m.CorrelationId)
                throw new BrowserRuleException("unknown_surface_assignment");
            surfaceAssignments.Remove(window);
            if (closingSurfaces.Remove(window)) return;
            if (handoffs.Remove(window, out var handoff))
            {
                if (m.Type == "platform.failed" || quiescing)
                {
                    if (!quiescing) Present(m, workspace.Window(handoff.Source));
                    Result(handoff.Command, quiescing ? "canceled" : "surface_unavailable");
                }
                else
                {
                    workspace.TransferPresentation(handoff.Source, handoff.Destination, handoff.Space, handoff.Tab);
                    persistenceDirty = true;
                    if (!quiescing)
                    {
                        Present(m, workspace.Window(handoff.Source));
                        Present(m, workspace.Window(handoff.Destination));
                    }
                    attachingHandoffs.Add(handoff.Destination, handoff);
                }
                Snapshot(m); return;
            }
            if (attachingHandoffs.Remove(window, out var attaching))
            {
                if (m.Type == "platform.failed")
                {
                    RollbackHandoff(m, attaching);
                    Result(attaching.Command, "surface_unavailable");
                }
                else Result(attaching.Command);
                Snapshot(m); return;
            }
            if (m.Type == "platform.failed")
            {
                var failedWindow = workspace.Window(window);
                if (!workspace.Space(failedWindow.SpaceId).IsLocked) workspace.Select(window, failedWindow.SpaceId, null);
                persistenceDirty = true;
                Present(m, failedWindow); Snapshot(m); Result(m, "surface_unavailable");
            }
            return;
        }
        Protocol.Members(p, "spaceId", "tabId", "pageId", "generation", "url", "title", "isLoading", "canGoBack", "canGoForward", "failure", "committed", "code", "restored");
        var (space, tab) = Target(p, requireAccess: false); ValidatePage(p, tab);
        switch (m.Type)
        {
            case "engine.page_unloaded": case "engine.unload_canceled":
            {
                var work = Completion(m, "engine.unload_page");
                if (work.Space != space.Id || work.Tab != tab.Id) throw new BrowserRuleException("wrong_effect_target");
                pending.Remove(m.CausationId!.Value);
                if (m.Type == "engine.page_unloaded") tab.Unload(); else tab.CancelUnload();
                if (!quiescing && !space.IsDeleting) PresentAll(m);
                Result(m); break;
            }
            case "engine.reveal_requested":
            {
                space.EnsureAccessible();
                if (tab.Phase != TabPhase.Ready) throw new BrowserRuleException("page_not_ready");
                var owner = workspace.PresentingWindow(space.Id, tab.Id) ?? workspace.Windows.FirstOrDefault(w => w.SpaceId == space.Id)
                    ?? throw new BrowserRuleException("source_page_not_presented");
                if (!Select(m, owner.Id, space.Id, tab.Id)) return;
                persistenceDirty = true; Result(m); break;
            }
            case "engine.open_requested":
            {
                space.EnsureAccessible();
                if (tab.Phase != TabPhase.Ready) throw new BrowserRuleException("page_not_ready");
                var owner = workspace.PresentingWindow(space.Id, tab.Id)
                    ?? throw new BrowserRuleException("source_page_not_presented");
                OpenTab(m, owner.Id, space, Protocol.Text(p, "url"), TabKind.Web, true);
                return;
            }
            case "engine.page_created":
            {
                bool restored = p.TryGetProperty("restored", out var restoredValue) && restoredValue.GetBoolean();
                var work = Completion(m, "engine.create_page", "engine.adopt_page");
                if (work.Space != space.Id || work.Tab != tab.Id) throw new BrowserRuleException("wrong_effect_target");
                pending.Remove(m.CausationId!.Value); creations.Remove(tab.Id);
                if (tab.Phase == TabPhase.Closing)
                {
                    Result(m, "canceled");
                    var close = m with { CorrelationId = closeOperations[tab.Id] };
                    Effect(close, "engine.close_page", space, tab, work.Window);
                }
                else
                {
                    tab.Created();
                    if (!quiescing && !space.IsDeleting)
                    {
                        if (workspace.PresentingWindow(space.Id, tab.Id) is { } owner) Present(m, owner);
                        if (work.Type != "engine.adopt_page" && !restored)
                            Emit(m, engine.Id, "effect", "engine.navigate", Page(space, tab, work.Window));
                    }
                    Result(m, quiescing ? "canceled" : null);
                }
                break;
            }
            case "engine.page_destroyed":
                if (tab.Phase is TabPhase.Closing or TabPhase.Unloading || creations.ContainsKey(tab.Id))
                    throw new BrowserRuleException("expected_correlated_completion");
                CancelConflictingHandoffs(m, null, tab.Id);
                workspace.Close(space.Id, tab.Id); persistenceDirty = true; PresentAll(m); break;
            case "engine.page_closed": case "engine.close_canceled":
            {
                var work = Completion(m, "engine.close_page");
                if (work.Space != space.Id || work.Tab != tab.Id) throw new BrowserRuleException("wrong_effect_target");
                pending.Remove(m.CausationId!.Value); closeOperations.Remove(tab.Id);
                closeReasons.Remove(tab.Id, out var reason);
                if (m.Type == "engine.close_canceled") { tab.CancelClose(); if (reason is not null) tab.Activate(clock.Now); Result(m, "canceled"); }
                else { workspace.Close(space.Id, tab.Id, reason: reason ?? "closed"); persistenceDirty = true; PresentAll(m); Result(m); }
                break;
            }
            case "engine.failed":
            {
                var work = Completion(m, "engine.create_page", "engine.adopt_page", "engine.close_page", "engine.unload_page");
                if (work.Tab != tab.Id || work.Space != space.Id) throw new BrowserRuleException("wrong_effect_target");
                pending.Remove(m.CausationId!.Value); creations.Remove(tab.Id); closeReasons.Remove(tab.Id);
                if (work.Type == "engine.unload_page") { tab.CancelUnload(); if (!quiescing) PresentAll(m); }
                else if (work.Type == "engine.close_page") tab.CancelClose(); else tab.Fail("native_failure");
                if (closeOperations.Remove(tab.Id, out var closeOperation) && closeOperation != m.CorrelationId)
                {
                    Result(m with { CorrelationId = closeOperation }, "native_failure");
                }
                Result(m, "native_failure"); break;
            }
            case "engine.page_changed":
            {
                if (space.IsDeleting || workspaceClosing) return;
                string? url = Protocol.OptionalText(p, "url");
                if (url is not null) BrowserWorkspace.ValidateUrl(url, engine.Supports("internal-pages"));
                bool committed = p.GetProperty("committed").GetBoolean();
                var oldUrl = tab.Url; var oldTitle = tab.Title;
                // WebKit can have an empty title; the host supplies a URL fallback.
                tab.Observe(url, Protocol.Text(p, "title", 4096), p.GetProperty("isLoading").GetBoolean(),
                    p.GetProperty("canGoBack").GetBoolean(), p.GetProperty("canGoForward").GetBoolean(), Protocol.OptionalText(p, "failure", 128));
                if (committed) workspace.Visit(space.Id, tab.Id);
                bool historyTitleChanged = space.UpdateHistoryTitle(tab);
                if (oldUrl != tab.Url || oldTitle != tab.Title || committed) persistenceDirty = true;
                if (space.IsLocked) return;
                Emit(m, ui, "projection", "ui.tab_changed", new()
                {
                    ["revision"] = (++revision).ToString(), ["workspaceId"] = workspace.Id.Value.ToString(),
                    ["spaceId"] = space.Id.Value.ToString(), ["tab"] = TabProjection(tab), ["recordsChanged"] = committed || historyTitleChanged
                });
                return;
            }
            default: throw new BrowserRuleException("unknown_observation");
        }
        Snapshot(m);
    }
    private static TabPlacement ReadPlacement(JsonElement p, string name, TabPlacement fallback)
    {
        if (!p.TryGetProperty(name, out _)) return fallback;
        return Protocol.Text(p, name) switch
        {
            "current" => TabPlacement.Current, "saved" => TabPlacement.Saved, "pinned" => TabPlacement.Pinned,
            _ => throw new BrowserRuleException("invalid_placement")
        };
    }
    private void PresentAll(Envelope m) { if (!quiescing) foreach (var window in workspace.Windows) Present(m, window); }
    private static JsonObject TabProjection(BrowserTab tab) => new()
    {
        ["id"] = tab.Id.Value.ToString(), ["kind"] = tab.Kind.ToString().ToLowerInvariant(),
        ["url"] = tab.Url, ["title"] = tab.DisplayTitle, ["phase"] = tab.Phase.ToString().ToLowerInvariant(),
        ["placement"] = tab.Placement.ToString().ToLowerInvariant(), ["folderId"] = tab.FolderId?.Value.ToString(),
        ["isLoading"] = tab.IsLoading, ["canGoBack"] = tab.CanGoBack, ["canGoForward"] = tab.CanGoForward,
        ["failure"] = tab.Failure, ["keepsPageLoaded"] = tab.KeepsPageLoaded,
        ["savedUrl"] = tab.SavedUrl, ["nativeKind"] = tab.NativeKind,
        ["splitGroupId"] = tab.SplitGroupId?.ToString()
    };
    private void Snapshot(Envelope m)
    {
        var spaces = new JsonArray();
        foreach (var space in workspace.Spaces)
        {
            var tabs = new JsonArray();
            foreach (var tab in space.Tabs.Where(_ => !space.IsLocked && !space.IsDeleting && !workspaceClosing)) tabs.Add((JsonNode)TabProjection(tab));
            var folders = new JsonArray();
            foreach (var folder in space.Folders.Where(_ => !space.IsLocked && !space.IsDeleting && !workspaceClosing)) folders.Add((JsonNode)new JsonObject
            { ["id"] = folder.Id.Value.ToString(), ["name"] = folder.Name,
                ["location"] = folder.Location.ToString().ToLowerInvariant(), ["parentId"] = folder.ParentId?.Value.ToString(),
                ["collapsed"] = folder.IsCollapsed, ["orderAnchorTabId"] = folder.OrderAnchorTabId?.Value.ToString() });
            spaces.Add((JsonNode)new JsonObject { ["id"] = space.Id.Value.ToString(), ["profileId"] = space.ProfileId.Value.ToString(),
                ["name"] = space.Name, ["tabs"] = tabs, ["folders"] = folders,
                ["requiresAuthentication"] = space.RequiresAuthentication, ["isLocked"] = space.IsLocked,
                ["isDeleting"] = space.IsDeleting, ["deletionFailure"] = deletionFailures.GetValueOrDefault(space.Id),
                ["contentBlockingPolicy"] = LegacySessionDocument.EnumName(space.ContentBlocking),
                ["contentBlockingPending"] = contentBlockingEffects.ContainsKey(space.Id),
                ["contentBlockingFailure"] = contentBlockingFailures.GetValueOrDefault(space.Id),
                ["retention"] = new JsonObject
                {
                    ["currentTabs"] = LegacySessionDocument.EnumName(space.Retention.CurrentTabs),
                    ["history"] = LegacySessionDocument.EnumName(space.Retention.History),
                    ["archive"] = LegacySessionDocument.EnumName(space.Retention.Archive),
                    ["downloads"] = LegacySessionDocument.EnumName(space.Retention.Downloads)
                },
                ["searchProviderId"] = space.Search.SelectedId, ["searchSuggestionsEnabled"] = space.Search.SuggestionsEnabled,
                ["searchProviders"] = new JsonArray(space.Search.Providers.Select(p => (JsonNode)new JsonObject
                { ["id"] = p.Id, ["name"] = p.Name }).ToArray()) });
        }
        var windows = new JsonArray();
        foreach (var window in workspace.Windows) windows.Add((JsonNode)new JsonObject
        {
            ["id"] = window.Id.Value.ToString(), ["spaceId"] = window.SpaceId.Value.ToString(),
            ["tabId"] = workspaceClosing || workspace.Space(window.SpaceId).IsLocked ? null : window.Selection(window.SpaceId)?.Value.ToString()
        });
        Emit(m, ui, "projection", "ui.snapshot", new()
        {
            ["revision"] = (++revision).ToString(), ["workspaceId"] = workspace.Id.Value.ToString(),
            ["spaces"] = spaces, ["windows"] = windows
        });
    }
}
