using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// The request member that names the window a command came from.
    private const string WindowField = "windowId";

    /// The device whose windows show this session, and the workspace it gave
    /// it; null until attached.
    private Device? device;
    private Guid workspaceId;

    /// The accepted session, for readers outside the command path.
    internal SessionState Current {
        get {
            lock (Gate) return session;
        }
    }

    /// Pages in this workspace keep nothing once they close.
    internal bool IsPrivateBrowsing => privateBrowsing;

    /// Whether `spaceId` is being deleted here or, for a borrowed workspace, in
    /// the workspace it borrows from, which owns the Space's profile.
    internal bool IsDeleting(Guid spaceId) {
        lock (Gate) return PendingDeletion(session, spaceId) is not null || borrowedSource?.IsDeleting(spaceId) == true;
    }

    #endregion

    #region Actions - Device

    private static Guid? OptionalId(JsonNode? value) => value is null ? null : Id(value);

    internal void AttachDevice(Device value, Guid workspace) {
        lock (Gate) {
            if (device is not null && !ReferenceEquals(device, value))
                throw new BrowserRuleException(BrowserRuleCodes.InvalidSessionTransaction);
            device = value;
            workspaceId = workspace;
        }
    }

    /// Tells the device the session accepted `committed`, with what the
    /// command chose for the window that issued it. Called with no lock held.
    internal void Published(SessionState committed, WindowFollowUp? followUp) {
        Device? target;
        Guid workspace;
        lock (Gate) {
            target = device;
            workspace = workspaceId;
        }
        target?.SessionPublished(workspace, committed, followUp);
    }

    /// Records that a window showed `tabId`, which current-tab cleanup reads,
    /// as a new revision saved behind. Answers null, and changes nothing, when
    /// the Space or tab is gone, the Space is being deleted, or this session
    /// takes no edits. Throws `Rejected` for a locked Space.
    internal (ulong Revision, DateTimeOffset At)? Touch(Guid spaceId, Guid tabId, DateTimeOffset now) {
        lock (Gate) {
            try {
                RequireWritable();
            } catch (BrowserRuleException) {
                return null;
            }
            if (PendingDeletion(session, spaceId) is not null || session.Spaces.FirstOrDefault(s => s.Id == spaceId) is not { } space
                || space.Tabs.All(tab => tab.Id != tabId)) return null;
            if (IsLockedUnderGate(space)) throw new Rejected(new SpaceLocked(spaceId));
            // The stored spelling of the time, so the next load reads the same value.
            var at = StoredSessionCodec.Date(StoredSessionCodec.Seconds(now));
            session = Replacing(session, space with {
                Tabs = [.. space.Tabs.Select(tab => tab.Id == tabId ? tab with { LastActivatedAt = at } : tab)]
            });
            Revision = checked(Revision + 1);
            storage?.Enqueue(session, Revision);
            return (Revision, at);
        }
    }

    /// Whether this process holds no grant to show `space`.
    internal bool IsLocked(SpaceState space) {
        lock (Gate) return IsLockedUnderGate(space);
    }

    private bool IsLockedUnderGate(SpaceState space) {
        if (access is null) return false;
        lock (access) return access.IsLocked(new SpaceAccessAssignment(space.Id, space.ProfileId), RequiresAuthentication(space));
    }

    #endregion
}
