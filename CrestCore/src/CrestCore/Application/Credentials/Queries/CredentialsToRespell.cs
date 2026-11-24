using CrestCore.Application;

namespace CrestCore.Contracts;

/// Which of `Saved`, the passwords a Space keeps, are saved for an origin a
/// page spells another way, each with the origin a page spells, so the app
/// rewrites each in place once (see `CredentialOrigin.Respelled`). An import
/// before imports spelled IP addresses as pages do kept `127.1` or a long IPv6
/// address as the file wrote it; such a password fills its page, but does not
/// merge with one saved there. An origin no page can have stays as it is. It
/// reads nothing the app holds. Refused with `DuplicateCredential` when two
/// passwords share an identity.
public sealed record CredentialsToRespell(IReadOnlyList<SavedCredentialOrigin> Saved) : Query<CredentialRespellings> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override CredentialRespellings Answer(CrestApp app) {
        ArgumentNullException.ThrowIfNull(Saved);
        if (Saved.Select(saved => saved.Id).Distinct().Count() != Saved.Count) throw new Rejected(new DuplicateCredential());
        return new([.. Saved.Select(saved => saved.Origin.Respelled is { } respelled ? saved with { Origin = respelled } : null)
            .OfType<SavedCredentialOrigin>()]);
    }

    #endregion
}
