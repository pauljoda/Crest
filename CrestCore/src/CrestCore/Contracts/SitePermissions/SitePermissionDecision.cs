using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A person's answer for one capability, origin and Space. Session answers
/// last until the process ends; persistent answers are saved on this device.
///
/// The saved permission document (`crest.site-permissions.v1`) and the
/// permission ledger's JSON spell a decision as its `Name`, so a name never
/// changes.
public sealed class SitePermissionDecision {
    #region Static Variables

    /// Ask clears both the session and the saved choice.
    public static readonly SitePermissionDecision Ask = new(name: "ask", SitePermissionVerdict.Ask, isPersistent: false,
        precedence: 2, title: "Ask", record: (ledger, space, key, _, _, _) => ledger.Forget(space, key), overrule: Forget);
    public static readonly SitePermissionDecision GrantForSession = new(name: "grantForSession", SitePermissionVerdict.Grant,
        isPersistent: false, precedence: 1, title: "Allowed for Session", record: KeepForSession, overrule: ForgetForSession);
    public static readonly SitePermissionDecision DenyForSession = new(name: "denyForSession", SitePermissionVerdict.Deny,
        isPersistent: false, precedence: 3, title: "Blocked for Session", record: KeepForSession, overrule: ForgetForSession);
    public static readonly SitePermissionDecision GrantPersistently = new(name: "grantPersistently", SitePermissionVerdict.Grant,
        isPersistent: true, precedence: 0, title: "Allow", record: Persist, overrule: Forget);
    public static readonly SitePermissionDecision DenyPersistently = new(name: "denyPersistently", SitePermissionVerdict.Deny,
        isPersistent: true, precedence: 4, title: "Block", record: Persist, overrule: Forget);

    public static IReadOnlyList<SitePermissionDecision> All { get; } =
        [Ask, GrantForSession, DenyForSession, GrantPersistently, DenyPersistently];

    #endregion

    #region Variables

    public string Name { get; }

    public SitePermissionVerdict Verdict { get; }

    public bool Grants => Verdict == SitePermissionVerdict.Grant;

    public bool Denies => Verdict == SitePermissionVerdict.Deny;

    /// The decision leaves the question to the person.
    public bool Asks => Verdict == SitePermissionVerdict.Ask;

    /// Only persistent answers are saved; session answers and Ask never are.
    public bool IsPersistent { get; }

    /// When several decisions answer one request together, as a camera and a
    /// microphone answer for combined capture, the one with the highest
    /// precedence holds: any block over no answer, no answer over a session
    /// grant, and a session grant over a saved one.
    public int Precedence { get; }

    /// What the settings call the decision.
    [Localized]
    public string Title { get; }

    /// How a ledger records the decision for one choice in one Space, and
    /// whether that changed what it saves.
    private readonly Func<SitePermissionLedger, Guid, SitePermissionLedger.SitePermissionKey, SitePermissionDecision, Guid, double, bool>
        record;

    /// How a ledger clears the same choice in another Space of the group the
    /// decision is recorded for, and whether that changed what it saves.
    private readonly Func<SitePermissionLedger, Guid, SitePermissionLedger.SitePermissionKey, bool> overrule;

    #endregion

    #region Constructors

    private SitePermissionDecision(string name, SitePermissionVerdict verdict, bool isPersistent, int precedence, string title,
        Func<SitePermissionLedger, Guid, SitePermissionLedger.SitePermissionKey, SitePermissionDecision, Guid, double, bool> record,
        Func<SitePermissionLedger, Guid, SitePermissionLedger.SitePermissionKey, bool> overrule) {
        Name = name;
        Verdict = verdict;
        IsPersistent = isPersistent;
        Precedence = precedence;
        Title = title;
        this.record = record;
        this.overrule = overrule;
    }

    #endregion

    #region Actions - Lookup

    public static SitePermissionDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    /// The decision that holds when all of `decisions` answer one request.
    public static SitePermissionDecision Strongest(IEnumerable<SitePermissionDecision> decisions) =>
        decisions.MaxBy(decision => decision.Precedence) ?? Ask;

    #endregion

    #region Actions - Recording

    /// Records the decision for `key` in `space` in `ledger`, and says whether
    /// that changed what the ledger saves. `recordId` names the record a new
    /// persistent choice creates, made at `now`.
    internal bool Record(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key, Guid recordId, double now) =>
        record(ledger, space, key, this, recordId, now);

    /// Clears the same choice in `space`, another Space of the group the
    /// decision was recorded for, and says whether that changed what `ledger`
    /// saves.
    internal bool Overrule(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key) =>
        overrule(ledger, space, key);

    /// A session answer overrides the saved choice without replacing it.
    private static bool KeepForSession(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key,
        SitePermissionDecision decision, Guid recordId, double now) =>
        ledger.KeepForSession(space, key, decision);

    /// A persistent answer replaces both and keeps an existing record's identity.
    private static bool Persist(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key,
        SitePermissionDecision decision, Guid recordId, double now) =>
        ledger.Persist(space, key, decision, recordId, now);

    /// Ask and a persistent answer leave another Space of the group neither
    /// choice.
    private static bool Forget(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key) =>
        ledger.Forget(space, key);

    /// A session answer leaves another Space of the group its saved choice,
    /// which the answer overrides without replacing.
    private static bool ForgetForSession(SitePermissionLedger ledger, Guid space, SitePermissionLedger.SitePermissionKey key) =>
        ledger.ForgetForSession(space, key);

    #endregion
}
