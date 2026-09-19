using System.Text.Json.Nodes;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class BrowserSessionKernel
{
    private sealed record TabTransfer(Envelope Command, Scope Source, Scope Destination, SpaceId Space,
        BrowserTab Tab, WindowId Window, WindowId? SourceWindow, Guid Effect, Guid? DetachLease);
    private TabTransfer? transfer;
    private readonly Queue<(Envelope Message, int Bytes)> deferredCommands = [];
    private int deferredBytes;
    private bool drainingDeferred;

    private void BeginTransfer(Envelope m, List<Outgoing> output)
    {
        Protocol.Members(m.Payload, "sourceWorkspaceId", "destinationWorkspaceId", "spaceId", "tabId", "windowId");
        if (quiescing) throw new BrowserRuleException("session_closing");
        if (!engine.Supports("workspace-transfer")) throw new BrowserRuleException("capability_unavailable");
        var source = scopes.GetValueOrDefault(new(Protocol.Id(m.Payload, "sourceWorkspaceId")))
            ?? throw new BrowserRuleException("unknown_workspace");
        var destination = scopes.GetValueOrDefault(new(Protocol.Id(m.Payload, "destinationWorkspaceId")))
            ?? throw new BrowserRuleException("unknown_workspace");
        if (source.Closing || destination.Closing) throw new BrowserRuleException("workspace_closing");
        if (source.Kernel.HasPresentationWork || destination.Kernel.HasPresentationWork)
            throw new BrowserRuleException("presentation_busy");
        var space = new SpaceId(Protocol.Id(m.Payload, "spaceId"));
        var tab = source.Kernel.Workspace.Space(space).Tab(new(Protocol.Id(m.Payload, "tabId")));
        destination.Kernel.Workspace.Space(space).ValidateTransferFrom(source.Kernel.Workspace.Space(space), tab.Id);
        var window = new WindowId(Protocol.Id(m.Payload, "windowId")); _ = destination.Kernel.Workspace.Window(window);
        var owner = source.Kernel.Workspace.PresentingWindow(space, tab.Id)?.Id;
        var effect = ids.Next();
        transfer = new(m, source, destination, space, tab, window, owner, effect, owner is null ? null : ids.Next());
        if (owner is { } attached)
        {
            output.Add(new(adapters.Single(a => a.Role == "platform").Id, "effect", "platform.assign_surface", new()
            { ["windowId"] = attached.Value.ToString(), ["leaseId"] = transfer.DetachLease!.Value.ToString() },
                effect, m.CorrelationId, m.Id));
        }
        else ReassignNativePage(m, output);
    }
    private void ReassignNativePage(Envelope m, List<Outgoing> output)
    {
        var current = transfer!;
        if (current.Tab.PageId is not { } page) { FinishTransfer(m, output); return; }
        var space = current.Destination.Kernel.Workspace.Space(current.Space);
        transfer = current with { Effect = ids.Next(), DetachLease = null };
        output.Add(new(engine.Id, "effect", "engine.reassign_page", new()
        {
            ["workspaceId"] = current.Destination.Kernel.Workspace.Id.Value.ToString(),
            ["sourceWorkspaceId"] = current.Source.Kernel.Workspace.Id.Value.ToString(),
            ["windowId"] = current.Window.Value.ToString(), ["spaceId"] = current.Space.Value.ToString(),
            ["tabId"] = current.Tab.Id.Value.ToString(), ["pageId"] = page.Value.ToString(),
            ["profileId"] = space.ProfileId.Value.ToString(), ["generation"] = current.Tab.Generation.ToString(),
            ["profileMode"] = IsPrivate(current.Destination) ? "private" : "regular",
            ["privateSourceProfileId"] = PrivateSource(current.Destination)?.Value.ToString()
        }, transfer.Effect, current.Command.CorrelationId, m.Id));
    }
    private bool ProcessTransferObservation(Envelope m, List<Outgoing> output)
    {
        if (transfer is not { } current)
            return m.Type is "engine.page_reassigned" or "engine.page_reassignment_failed";
        if (m.Type == "engine.page_destroyed" && Protocol.OptionalId(m.Payload, "pageId") == current.Tab.PageId?.Value)
        { FinishTransfer(m, output, "page_destroyed"); return false; }
        if (m.CausationId != current.Effect) return false;
        if (m.CorrelationId != current.Command.CorrelationId) throw new BrowserRuleException("wrong_transfer_operation");
        if (current.DetachLease is { } lease)
        {
            if (m.Type is not ("platform.surface_attached" or "platform.failed")) return false;
            Protocol.Members(m.Payload, "windowId", "leaseId", "code");
            if (Protocol.Id(m.Payload, "windowId") != current.SourceWindow!.Value.Value || Protocol.Id(m.Payload, "leaseId") != lease)
                throw new BrowserRuleException("wrong_transfer_surface");
            if (m.Type == "platform.failed") FinishTransfer(m, output, "surface_unavailable");
            else ReassignNativePage(m, output);
        }
        else
        {
            if (m.Type is not ("engine.page_reassigned" or "engine.page_reassignment_failed")) return false;
            Protocol.Members(m.Payload, "workspaceId", "spaceId", "tabId", "profileId", "pageId", "generation");
            if (Protocol.Id(m.Payload, "workspaceId") != current.Destination.Kernel.Workspace.Id.Value
                || Protocol.Id(m.Payload, "spaceId") != current.Space.Value || Protocol.Id(m.Payload, "tabId") != current.Tab.Id.Value
                || Protocol.Id(m.Payload, "profileId") != current.Source.Kernel.Workspace.Space(current.Space).ProfileId.Value
                || Protocol.Id(m.Payload, "pageId") != current.Tab.PageId?.Value || Protocol.Counter(m.Payload, "generation") != current.Tab.Generation)
                throw new BrowserRuleException("wrong_transfer_page");
            FinishTransfer(m, output, m.Type == "engine.page_reassignment_failed" ? "native_transfer_failed" : null);
        }
        return true;
    }
    private void FinishTransfer(Envelope m, List<Outgoing> output, string? failure = null)
    {
        var current = transfer!;
        if (failure is null)
            current.Source.Kernel.TransferTabTo(current.Destination.Kernel, current.Space, current.Tab.Id, current.Window);
        transfer = null;
        Append(output, current.Source, current.Source.Kernel.PublishTransferredState(m));
        Append(output, current.Destination, current.Destination.Kernel.PublishTransferredState(m));
        output.Add(failure is null ? new(ui, "result", "core.operation_completed", new() { ["code"] = "completed" },
            ids.Next(), current.Command.CorrelationId, current.Command.Id) : Failure(current.Command, failure));
    }
}
