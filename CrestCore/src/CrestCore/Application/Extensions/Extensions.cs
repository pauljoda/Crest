using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The extensions of the person's Spaces, on whichever engine keeps them: what
/// each engine installed in each Space's profile, and the installs under way.
/// Every change and install is checked against its Space here before any
/// engine hears of it: only a Space of the person's own workspace, not
/// locked, not being deleted and not a private window's, on an engine that
/// supports `extensions`. The engine owns verification, permissions,
/// updates and execution; the core owns which Spaces may change, where a
/// copy may go and which consent answers a later question. Never saved or
/// synced: each engine lists what it has every time it starts.
internal sealed class Extensions(Device device, Engines engines, Prompts prompts) {
    #region Variables

    /// What each engine last listed for each profile.
    private readonly Dictionary<(EngineKind Engine, Guid ProfileId), IReadOnlyList<InstalledExtension>> listed = [];

    /// The installs under way, by install.
    private readonly Dictionary<Guid, ExtensionInstall> installs = [];

    #endregion

    #region Actions - Intents

    /// Runs one extension intent, publishing what it changed to `changes` and
    /// handing the engine commands it causes to `issue`.
    public void Handle(ExtensionIntent intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        intent.Apply(this, changes, issue);

    #endregion

    #region Actions - Reports

    /// Applies what an engine reported about extensions.
    public void Report(ExtensionEvent report, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        report.Apply(this, engine, changes, issue);

    #endregion

    #region Actions - Access

    /// The Space `spaceId` names, with the engine of `kind`, when the Space's
    /// extensions may change on that engine. Refused with `UnknownSpace` for
    /// a Space the person's own workspace does not hold, `SpaceIsPrivate` for
    /// a private window's, `SpaceBeingDeleted`, `SpaceLocked` while it or a
    /// Space it shares its profile with is locked, `UnregisteredEngine`, and
    /// `EngineLacksCapability` for an engine without `extensions`.
    internal (SpaceState Space, Engine Engine) Reachable(Guid spaceId, EngineKind kind) =>
        Reach(spaceId, kind, out var refusal) ?? throw new Rejected(refusal!);

    /// The Space and engine `Reachable` answers, or null with the rule that
    /// refuses them.
    private (SpaceState Space, Engine Engine)? Reach(Guid spaceId, EngineKind kind, out Rejection? refusal) {
        var workspace = device.Persistent()?.Authority;
        var space = workspace?.Current.Space(spaceId);
        var engine = engines.Registered(kind);
        refusal = workspace is null || space is null
            ? device.IsPrivate(spaceId) ? new SpaceIsPrivate(spaceId) : new UnknownSpace(spaceId)
            : workspace.IsDeleting(spaceId) ? new SpaceBeingDeleted(spaceId)
            : workspace.IsLocked(space) ? new SpaceLocked(spaceId)
            : engine is null ? new UnregisteredEngine(kind)
            : !engine.Supports(EngineCapability.Extensions) ? new EngineLacksCapability(kind, EngineCapability.Extensions)
            : null;
        return refusal is null ? (space!, engine!) : null;
    }

    #endregion

    #region Actions - Listing

    /// What `engine` last listed for `profileId`, or null before it listed it.
    internal IReadOnlyList<InstalledExtension>? Listed(Engine engine, Guid profileId) =>
        listed.GetValueOrDefault((engine.Kind, profileId));

    /// Whether `engine` listed `extensionId` in `profileId`.
    private bool Has(Engine engine, Guid profileId, string extensionId) =>
        Listed(engine, profileId)?.Any(extension => extension.Id == extensionId) == true;

    /// Publishes what `engine` holds for `profileId` as far as the core
    /// knows it, and asks the engine to list it again and follow it.
    internal void List(Engine engine, Guid profileId, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (Listed(engine, profileId) is { } known) Publish(engine, profileId, known, changes);
        issue(engine, new ListEngineExtensions(profileId));
    }

    /// Keeps what `engine` listed for `profileId`, and publishes it.
    internal void Record(Engine engine, Guid profileId, IReadOnlyList<InstalledExtension> extensions, ChangeFeed changes) {
        listed[(engine.Kind, profileId)] = extensions;
        Publish(engine, profileId, extensions, changes);
    }

    /// Publishes `extensions` when one of the person's own Spaces browses
    /// with `profileId` and no locked Space does, since a locked Space's
    /// extensions are its grant's to reveal.
    private void Publish(Engine engine, Guid profileId, IReadOnlyList<InstalledExtension> extensions, ChangeFeed changes) {
        if (device.Persistent()?.Authority.Current.Spaces.Any(space => space.ProfileId == profileId) == true
            && device.LockedSpace(profileId) is null)
            changes.Publish(new InstalledExtensionsChanged(engine.Kind, profileId, extensions));
    }

    #endregion

    #region Actions - Copies

    /// The Spaces a copy of `extensionId` from `source` may go to on
    /// `engine`: one for each profile other than `source`'s, a group's
    /// primary standing for the group, of a Space within reach, and none
    /// whose profile already has the extension.
    internal ExtensionCopyDestinationList Destinations(SpaceState source, Engine engine, string extensionId) {
        var targets = CopyTargets(source);
        return new([.. targets.Where(space => !Has(engine, space.ProfileId, extensionId)).Select(space => space.Id)],
            Listed: targets.All(space => Listed(engine, space.ProfileId) is not null));
    }

    /// One Space for each profile a copy from `source` could go to: the
    /// person's own Spaces within reach that browse with another profile,
    /// each group's primary in place of its Sub-Spaces, in the order the
    /// workspace keeps them.
    private IReadOnlyList<SpaceState> CopyTargets(SpaceState source) {
        if (device.Persistent()?.Authority is not { } workspace) return [];
        return [.. workspace.Current.Spaces
            .Where(space => space.ProfileId != source.ProfileId && !workspace.IsDeleting(space.Id) && !workspace.IsLocked(space))
            .GroupBy(space => space.ProfileId)
            .Select(group => group.FirstOrDefault(space => space.OwnProfileId == space.ProfileId) ?? group.First())];
    }

    #endregion

    #region Actions - Installs

    /// The install `installId` names while it runs on `engine`, or null.
    internal ExtensionInstall? Running(Guid installId, Engine engine) =>
        installs.TryGetValue(installId, out var install) && ReferenceEquals(install.Engine, engine) ? install : null;

    /// Starts `install`: the engine lists every profile it may go to, so the
    /// copies can tell which already have the extension, and downloads the
    /// package through the first Space's profile. A repeated install changes
    /// nothing.
    internal void Start(ExtensionInstall install, SpaceState source, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (!installs.TryAdd(install.Id, install)) return;
        foreach (var profileId in CopyTargets(source).Select(space => space.ProfileId).Prepend(source.ProfileId))
            issue(install.Engine, new ListEngineExtensions(profileId));
        issue(install.Engine, new DownloadExtension(install.Id, source.ProfileId, install.ExtensionId));
        changes.Publish(new ExtensionInstallChanged(install.State));
    }

    /// Installs the package in the next Space `install` goes to, or ends it
    /// once none is left. The first Space must still be within reach; a copy
    /// leaves out a Space out of reach now, a profile the install already
    /// put the extension in, and one that already has it, as a pre-approved
    /// install does for its first Space too.
    internal void Advance(ExtensionInstall install, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        while (install.TryNext(out var spaceId, out var first)) {
            if (Reach(spaceId, install.Engine.Kind, out _)?.Space is not { } space) {
                if (!first) continue;
                End(install, ExtensionInstallFailure.SpaceUnavailable, changes, issue);
                return;
            }
            if (install.Holds(space.ProfileId)
                || (!first || install.PreApproved) && Has(install.Engine, space.ProfileId, install.ExtensionId)) continue;
            install.Begin(space.Id, space.ProfileId);
            issue(install.Engine, new InstallExtensionPackage(install.Id, space.ProfileId));
            return;
        }
        End(install, failure: null, changes, issue);
    }

    /// The engine asks whether to install `question`'s package for `install`.
    /// A copy whose question asks for the consent already given is answered
    /// with it, and any other declined; a pre-approved install takes its
    /// first question as its consent; otherwise the person is asked.
    internal void Ask(ExtensionInstall install, Guid promptId, ExtensionInstallQuestion question, ChangeFeed changes,
        Action<Engine, EngineCommand> issue) {
        if (install.Consent is { } consent) {
            issue(install.Engine,
                new SettleExtensionInstall(promptId, question.IsCoveredBy(consent.Question), consent.WithholdsSiteAccess));
            return;
        }
        if (install.PreApproved) {
            install.Approve(question, question.WithholdsSiteAccess);
            issue(install.Engine, new SettleExtensionInstall(promptId, Accepted: true, question.WithholdsSiteAccess));
            changes.Publish(new ExtensionInstallChanged(install.State));
            return;
        }
        var declining = new SettleExtensionInstall(promptId, Accepted: false, WithholdsSiteAccess: false);
        if (!prompts.Raised(install.Engine, promptId, pageId: null, question, declining, issue)) return;
        install.Ask(promptId, question);
        changes.Publish(new ExtensionInstallAsked(promptId, install.Id, question));
        changes.Publish(new ExtensionInstallChanged(install.State));
    }

    /// The person's answer to the question an install waits on. Refused with
    /// `UnknownPrompt` for a prompt that no longer waits, and
    /// `PromptAnswerMismatch` for one that asks something else. When they
    /// accept, the copies go to `CopySpaceIds`, each checked when its turn
    /// comes.
    internal void Answer(AnswerExtensionInstall answer, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        prompts.Answer(answer.PromptId, question => question is ExtensionInstallQuestion,
            new SettleExtensionInstall(answer.PromptId, answer.Accepted, answer.WithholdsSiteAccess), changes, issue);
        if (installs.Values.FirstOrDefault(install => install.AskingPromptId == answer.PromptId) is not { } asking) return;
        asking.Answer(answer.Accepted, answer.WithholdsSiteAccess, answer.CopySpaceIds);
        changes.Publish(new ExtensionInstallChanged(asking.State));
    }

    /// Ends `install`, done when `failure` is null: a question it still waits
    /// on is declined, the engine discards its package, and the core
    /// publishes how it ended.
    internal void End(ExtensionInstall install, ExtensionInstallFailure? failure, ChangeFeed changes,
        Action<Engine, EngineCommand> issue) {
        if (!installs.Remove(install.Id)) return;
        if (install.AskingPromptId is { } promptId) {
            prompts.Settle(promptId, changes);
            issue(install.Engine, new SettleExtensionInstall(promptId, Accepted: false, WithholdsSiteAccess: false));
        }
        install.End(failure);
        issue(install.Engine, new EndExtensionInstall(install.Id));
        changes.Publish(new ExtensionInstallChanged(install.State));
    }

    /// Stops the install `installId` names, as the person canceling it. One
    /// that already ended changes nothing.
    internal void Cancel(Guid installId, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (installs.GetValueOrDefault(installId) is { } install)
            End(install, ExtensionInstallFailure.Canceled, changes, issue);
    }

    /// Ends each install whose first Space went out of reach before it was
    /// done, or whose Space it installs in now did, as a Space that locked or
    /// began to be deleted. The engine finishes an install it already began,
    /// and the core ignores it.
    public void Prune(ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        foreach (var install in installs.Values.ToArray()) {
            var sourceGone = install.InstalledCount == 0 && Reach(install.SpaceId, install.Engine.Kind, out _) is null;
            var targetGone = install.InstallingSpaceId is { } target && Reach(target, install.Engine.Kind, out _) is null;
            if (sourceGone || targetGone) End(install, ExtensionInstallFailure.SpaceUnavailable, changes, issue);
        }
    }

    #endregion
}
