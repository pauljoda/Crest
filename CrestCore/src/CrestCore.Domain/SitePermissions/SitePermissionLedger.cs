using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Per-Space site permission choices for one process.
///
/// Persistent choices are the saved records; session choices override them
/// until the process ends and are never saved or synced. A request with a
/// detail (such as one URL scheme) is answered by the narrowest choice first,
/// then by the site-wide rule for the same capability. A locked Space never
/// answers, lists or records a choice: its questions are Ask and its writes are
/// rejected. Removals still apply, so deleting or resetting a Space cannot be
/// blocked by its lock. Callers serialize access.
public sealed class SitePermissionLedger {
    #region Variables

    public const int MaximumRecords = 4_096;
    public const int MaximumDetailLength = 256;

    private readonly List<SitePermissionRecord> persistent = [];
    private readonly Dictionary<Guid, Dictionary<SitePermissionKey, SitePermissionDecision>> session = [];

    /// Saved records in storage order.
    public IReadOnlyList<SitePermissionRecord> PersistentRecords => persistent;

    #endregion

    #region Actions - Persistence

    /// Replaces the saved records with those read from storage. Records that
    /// are not persistent choices, or that repeat an earlier record's Space,
    /// origin, capability and detail, are left out, as lookups always answered
    /// from the first. Returns how many records were kept.
    public int Restore(IEnumerable<SitePermissionRecord> records) {
        ArgumentNullException.ThrowIfNull(records);
        persistent.Clear();
        session.Clear();
        var seen = new HashSet<(Guid, SitePermissionKey)>();
        foreach (var record in records) {
            if (persistent.Count >= MaximumRecords) break;
            if (record.Id == Guid.Empty || record.Space == Guid.Empty || !IsValidDetail(record.Detail)
                || !record.Decision.IsPersistent || !double.IsFinite(record.ModifiedAt)) continue;
            if (persistent.Any(existing => existing.Id == record.Id)) continue;
            if (!seen.Add((record.Space, Key(record)))) continue;
            persistent.Add(record);
        }
        return persistent.Count;
    }

    #endregion

    #region Actions - Decisions

    public SitePermissionDecision Decision(Guid space, SiteOrigin origin, SitePermission permission, string? detail,
        bool isLocked) {
        ArgumentNullException.ThrowIfNull(origin);
        RequireDetail(detail);
        if (isLocked) return SitePermissionDecision.Ask;
        var key = new SitePermissionKey(origin, permission, detail);
        foreach (var candidate in detail is null ? [key] : new[] { key, key with { Detail = null } }) {
            if (session.TryGetValue(space, out var decisions) && decisions.TryGetValue(candidate, out var decision)) return decision;
            if (persistent.FirstOrDefault(record => record.Space == space && Key(record) == candidate) is { } saved)
                return saved.Decision;
        }
        return SitePermissionDecision.Ask;
    }

    /// A capture request's decision. Combined capture must respect a block on
    /// either device, and an existing combined grant still answers a request
    /// for just one of those devices. `media` must be a capture device.
    public SitePermissionDecision MediaDecision(Guid space, SiteOrigin origin, SitePermission media, bool isLocked) {
        ArgumentNullException.ThrowIfNull(media);
        if (!media.IsMedia) throw new ArgumentException($"{media.Name} is not a capture device.", nameof(media));
        if (isLocked) return SitePermissionDecision.Ask;
        var devices = media.Devices().Select(device => Decision(space, origin, device, null, false)).ToArray();
        var combinations = media.Combinations().Select(combination => Decision(space, origin, combination, null, false)).ToArray();
        var strongest = SitePermissionDecision.Strongest(devices.Concat(combinations));
        if (strongest.Denies) return strongest;
        return combinations.FirstOrDefault(decision => decision.Grants) ?? SitePermissionDecision.Strongest(devices);
    }

    /// One Space's saved choices in display order. A locked Space lists none.
    public IReadOnlyList<SitePermissionRecord> Records(Guid space, bool isLocked) =>
        isLocked ? [] : [.. persistent.Where(record => record.Space == space).Order(SitePermissionRecordOrder.Instance)];

    #endregion

    #region Actions - Commands

    /// Records one answer. Ask clears both the session and the saved choice;
    /// a session answer overrides the saved choice without replacing it; a
    /// persistent answer replaces both and keeps an existing record's identity.
    /// `recordId` names the record a new persistent choice creates.
    public SitePermissionOutcome Set(Guid space, SiteOrigin origin, SitePermission permission, string? detail,
        SitePermissionDecision decision, Guid recordId, double now, bool isLocked) {
        ArgumentNullException.ThrowIfNull(origin);
        ArgumentNullException.ThrowIfNull(permission);
        ArgumentNullException.ThrowIfNull(decision);
        RequireDetail(detail);
        if (space == Guid.Empty || recordId == Guid.Empty) throw new BrowserRuleException(BrowserRuleCodes.InvalidIdentity);
        if (!double.IsFinite(now)) throw new BrowserRuleException(BrowserRuleCodes.InvalidRecordDate);
        if (isLocked) return SitePermissionOutcome.Rejected;
        var key = new SitePermissionKey(origin, permission, detail);
        bool persistenceChanged = false;
        if (decision.IsPersistent) {
            if (session.TryGetValue(space, out var overridden)) overridden.Remove(key);
            int index = persistent.FindIndex(record => record.Space == space && Key(record) == key);
            if (index >= 0) {
                persistent[index] = persistent[index] with { Decision = decision, ModifiedAt = now };
            } else {
                if (persistent.Count >= MaximumRecords) throw new BrowserRuleException(BrowserRuleCodes.SitePermissionRecordLimit);
                if (persistent.Any(record => record.Id == recordId)) throw new BrowserRuleException(BrowserRuleCodes.DuplicateSitePermissionRecord);
                persistent.Add(new(recordId, space, origin, permission, detail, decision, now));
            }
            persistenceChanged = true;
        } else if (decision.Verdict == SitePermissionVerdict.Ask) {
            if (session.TryGetValue(space, out var cleared)) cleared.Remove(key);
            persistenceChanged = persistent.RemoveAll(record => record.Space == space && Key(record) == key) > 0;
        } else {
            if (!session.TryGetValue(space, out var decisions)) session[space] = decisions = [];
            decisions[key] = decision;
        }
        return new(true, persistenceChanged,
            [new(space, origin, permission, detail, !decision.Grants)]);
    }

    public SitePermissionOutcome ResetRecord(Guid id) {
        int index = persistent.FindIndex(record => record.Id == id);
        if (index < 0) return SitePermissionOutcome.Rejected;
        var record = persistent[index];
        persistent.RemoveAt(index);
        return new(true, true, [new(record.Space, record.Origin, record.Permission, record.Detail, true)]);
    }

    /// Clears every saved and session choice in one Space.
    public SitePermissionOutcome ResetSpace(Guid space) {
        session.Remove(space);
        bool removed = persistent.RemoveAll(record => record.Space == space) > 0;
        return new(true, removed, [new(space, null, null, null, true)]);
    }

    /// Clears every session choice, as when the process's session ends.
    public SitePermissionOutcome ResetSession() {
        var changes = session.SelectMany(entry => entry.Value.Keys.Select(key =>
            new SitePermissionChange(entry.Key, key.Origin, key.Permission, key.Detail, true))).ToArray();
        session.Clear();
        return new(true, false, changes);
    }

    #endregion

    #region Actions - Keys

    private static SitePermissionKey Key(SitePermissionRecord record) => new(record.Origin, record.Permission, record.Detail);

    private static bool IsValidDetail(string? detail) => detail is null || (detail.Length is > 0 and <= MaximumDetailLength);

    private static void RequireDetail(string? detail) {
        if (!IsValidDetail(detail)) throw new BrowserRuleException(BrowserRuleCodes.InvalidSitePermissionDetail);
    }

    /// One choice's identity within a Space.
    private readonly record struct SitePermissionKey(SiteOrigin Origin, SitePermission Permission, string? Detail);

    #endregion
}
