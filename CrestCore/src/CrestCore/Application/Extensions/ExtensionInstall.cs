using CrestCore.Contracts;

namespace CrestCore.Application;

/// One extension install the core runs, from the download of its package to
/// its last Space: the Space whose profile downloads the package and installs
/// it first, then the copies the person chose, one at a time. The consent the
/// person, or the import that chose the extension, gave to the first question
/// answers each later one for the same package and access. Never saved.
internal sealed class ExtensionInstall {
    #region Variables

    public Guid Id { get; }
    public Engine Engine { get; }

    /// The Space whose profile downloads the package and installs it first.
    public Guid SpaceId { get; }
    public string ExtensionId { get; }

    /// The person chose the extension before the install began, as an
    /// import's review does, so its first question is accepted without
    /// asking, and a Space that already has it is left out, the first too.
    public bool PreApproved { get; }

    public ExtensionInstallStage Stage { get; private set; } = ExtensionInstallStage.Downloading;
    public int InstalledCount { get; private set; }

    /// The engine downloaded the install's package and keeps it.
    public bool HasPackage { get; private set; }
    public ExtensionInstallFailure? Failure { get; private set; }

    /// The Space the engine installs the package in now and the profile it
    /// installs in, or null between installs, and whether it is the install's
    /// first, whose failure ends the install.
    public Guid? InstallingSpaceId { get; private set; }
    public Guid? InstallingProfile { get; private set; }
    public bool InstallingFirst { get; private set; }

    /// The question waiting on the person, by its prompt, and the question.
    public Guid? AskingPromptId { get; private set; }
    private ExtensionInstallQuestion? asked;

    /// The question the consent was given to, and whether it withholds site
    /// access, once the person or the import gave it.
    public (ExtensionInstallQuestion Question, bool WithholdsSiteAccess)? Consent { get; private set; }

    /// The Spaces still to install in, the first Space first.
    private readonly Queue<Guid> pending;
    private bool firstPending = true;

    /// The profiles this install put the extension in.
    private readonly HashSet<Guid> profiles = [];

    /// The install as the core publishes it.
    public ExtensionInstallState State => new(Id, SpaceId, Engine.Kind, ExtensionId, Stage, InstalledCount, Failure);

    #endregion

    #region Constructors

    public ExtensionInstall(Guid id, Engine engine, Guid spaceId, string extensionId, IReadOnlyList<Guid> copySpaceIds,
        bool preApproved) {
        Id = id;
        Engine = engine;
        SpaceId = spaceId;
        ExtensionId = extensionId;
        PreApproved = preApproved;
        pending = new([spaceId, .. copySpaceIds]);
    }

    #endregion

    #region Actions - Spaces

    /// The engine downloaded the package.
    public void Downloaded() => HasPackage = true;

    /// Takes the next Space to install in, and whether it is the first.
    /// False once none is left.
    public bool TryNext(out Guid spaceId, out bool first) {
        first = firstPending;
        if (!pending.TryDequeue(out spaceId)) return false;
        firstPending = false;
        return true;
    }

    /// Whether this install already put the extension in `profileId`.
    public bool Holds(Guid profileId) => profiles.Contains(profileId);

    /// The engine installs the package in Space `spaceId`'s profile
    /// `profileId` now.
    public void Begin(Guid spaceId, Guid profileId, bool first) {
        InstallingSpaceId = spaceId;
        InstallingProfile = profileId;
        InstallingFirst = first;
    }

    /// The engine installed the package in the profile it installed in.
    public void Installed() {
        if (InstallingProfile is { } profile) profiles.Add(profile);
        InstalledCount++;
        Between();
    }

    /// The profile the engine installed in refused its copy, which leaves the
    /// others to go.
    public void Skipped() => Between();

    /// No Space is being installed in until the next one begins.
    private void Between() {
        InstallingSpaceId = null;
        InstallingProfile = null;
    }

    #endregion

    #region Actions - Consent

    /// The engine's question waits on the person.
    public void Ask(Guid promptId, ExtensionInstallQuestion question) {
        AskingPromptId = promptId;
        asked = question;
        Stage = ExtensionInstallStage.Asking;
    }

    /// The person answered the question waiting on them: when they accepted,
    /// with whether it withholds site access and the Spaces the copies go to
    /// in place of those the install began with.
    public void Answer(bool accepted, bool withholdsSiteAccess, IReadOnlyList<Guid> copySpaceIds) {
        var question = asked;
        AskingPromptId = null;
        asked = null;
        if (!accepted || question is null) return;
        Approve(question, withholdsSiteAccess);
        pending.Clear();
        foreach (var spaceId in copySpaceIds) pending.Enqueue(spaceId);
    }

    /// The consent `question` was given, so the install goes on.
    public void Approve(ExtensionInstallQuestion question, bool withholdsSiteAccess) {
        Consent = (question, withholdsSiteAccess);
        Stage = ExtensionInstallStage.Installing;
    }

    #endregion

    #region Actions - Ending

    /// The install ended: done, or failed for `failure`.
    public void End(ExtensionInstallFailure? failure) {
        Failure = failure;
        Stage = failure is null ? ExtensionInstallStage.Installed : ExtensionInstallStage.Failed;
        Between();
    }

    #endregion
}
