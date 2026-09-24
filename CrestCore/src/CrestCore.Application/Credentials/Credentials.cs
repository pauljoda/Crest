using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The credentials and passkeys area: capture, fill and save decisions, the
/// generated-password recipe, passkey access and the system Passwords offer.
/// It holds no state. Only identities and metadata arrive: form facts say
/// whether a username or password is present, never what it is, and the save
/// plan takes the platform's comparison instead of a stored secret.
public sealed class Credentials {
    #region Actions - Capture and fill

    public CredentialCaptureDecision Answer(CredentialCapture query) {
        ArgumentNullException.ThrowIfNull(query);
        return CredentialCapturePolicy.Decide(query.Facts, query.Hint, query.Pending, query.Now);
    }

    public CredentialFillDecision Answer(CredentialFill query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(CredentialCapturePolicy.Offers(query.Source, query.PasswordKind));
    }

    #endregion

    #region Actions - Saving

    public CredentialSaveVerdict Answer(CredentialSaveCheck query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(CredentialCapturePolicy.SaveValidity(query.Origin, query.TopLevelOrigin, query.SubmittedAt, query.Now));
    }

    public CredentialChoice Answer(MostRecentCredential query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(CredentialRecencyPolicy.MostRecent(query.Records)?.Id);
    }

    public CredentialChoice Answer(CredentialSaveMatch query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(CredentialSavePolicy.Match(query.Username, query.Records)?.Id);
    }

    public CredentialSavePlan Answer(CredentialSave query) {
        ArgumentNullException.ThrowIfNull(query);
        return CredentialSavePolicy.Plan(query.MatchId, query.Stored);
    }

    public StrongPasswordRecipe Answer(StrongPassword query) {
        ArgumentNullException.ThrowIfNull(query);
        return StrongPasswordPolicy.Recipe(query.Length);
    }

    #endregion

    #region Actions - Passkeys and system passwords

    public PasskeyAccessVerdict Answer(PasskeyAccess query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(PasskeyAccessPolicy.Status(query.HasManagedCapability, query.DeviceConfiguration, query.AuthorizationState));
    }

    public SystemPasswordWriteThroughSupport Answer(SystemPasswordWriteThrough query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(PasskeyAccessPolicy.WriteThroughAvailability(query.IsMobilePlatform, query.SupportsSystemPasswordSaving,
            query.HasManagedBrowserCapability, query.IsLaunchIsolated));
    }

    public SystemPasswordOfferDecision Answer(SystemPasswordOffer query) {
        ArgumentNullException.ThrowIfNull(query);
        return new(PasskeyAccessPolicy.OffersWriteThrough(query.SpaceOffersSystemPasswords, query.Availability,
            query.IsPrivateBrowsing));
    }

    #endregion
}
