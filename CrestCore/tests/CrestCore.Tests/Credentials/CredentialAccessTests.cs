using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a Space's passwords serve, and where they live, as the core answers
/// every platform that fills or saves them.
public sealed partial class BrowserContractsTests {
    #region Actions - Credential Access

    /// A group's passwords are read from its primary's vault, which keeps new
    /// ones, then from each Sub-Space's own. A private window saves none, a
    /// Space whose password manager is off fills and saves none, and a page
    /// without HTTPS is served none; reading what a Space keeps is never
    /// refused.
    [Fact]
    public void CredentialAccessNamesTheGroupsVaultsAndWhatItRefuses() {
        var (primary, member, alone, hidden) = (Fixed(3_400), Fixed(3_401), Fixed(3_402), Fixed(3_403));
        using var device = new TestDevice(SessionOf(SpaceOf(primary, Fixed(3_490), "Work"), SpaceOf(member, Fixed(3_491), "Client"),
            SpaceOf(alone, Fixed(3_492), "Personal")));
        var privateWorkspace = device.Attach(SessionOf(SpaceOf(hidden, Fixed(3_493), "Private")), WorkspaceKind.Private);
        device.Send(new JoinSpace(device.Workspace, member, primary));
        device.Send(new SetCredentialPreferences(device.Workspace, alone,
            new CredentialPreferences(IsEnabled: false, SyncsCrestPasswordsWithICloud: false, AlsoOffersSaveToSystemPasswords: false)));
        var secure = new CredentialOrigin("https", "accounts.example.com", 443);
        var plain = new CredentialOrigin("http", "accounts.example.com", 80);
        CredentialAccessAnswer Access(Guid space, CredentialUse use, CredentialOrigin? origin = null, Guid? workspace = null) =>
            device.Query(new CredentialAccess(workspace ?? device.Workspace, space, use, origin));

        Assert.Equal([primary, member], Access(member, CredentialUse.Read).Vaults);
        Assert.Equal([primary, member], Access(primary, CredentialUse.Read).Vaults);
        Assert.Equal([alone], Access(alone, CredentialUse.Read).Vaults);
        Assert.Null(Access(member, CredentialUse.Save, secure).Refusal);
        Assert.Equal(CredentialRefusal.InsecureOrigin, Access(member, CredentialUse.Fill, plain).Refusal);
        Assert.Null(Access(member, CredentialUse.Read, plain).Refusal);
        Assert.Equal(CredentialRefusal.ManagerOff, Access(alone, CredentialUse.Fill, secure).Refusal);
        Assert.Equal(CredentialRefusal.ManagerOff, Access(alone, CredentialUse.Save, plain).Refusal);
        Assert.Null(Access(alone, CredentialUse.Read).Refusal);
        Assert.Equal(CredentialRefusal.PrivateBrowsing, Access(hidden, CredentialUse.Save, secure, privateWorkspace).Refusal);
        Assert.Null(Access(hidden, CredentialUse.Fill, secure, privateWorkspace).Refusal);
        Assert.IsType<UnknownSpace>(Assert.Throws<Rejected>(() => Access(Fixed(3_404), CredentialUse.Read)).Rejection);
    }

    #endregion
}
