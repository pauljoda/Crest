using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class OriginPolicyTests {
    private static readonly SiteOrigin Site = new("https", "site.example", 443);

    [Theory]
    [InlineData("https", "maps.example", true)]
    [InlineData("http", "localhost", true)]
    [InlineData("http", "127.0.0.1", true)]
    [InlineData("http", "::1", true)]
    [InlineData("http", "maps.example", false)]
    [InlineData("file", "localhost", false)]
    public void PowerfulFeaturesNeedASecureContext(string scheme, string host, bool allowed) =>
        Assert.Equal(allowed, SecureOriginPolicy.Allows(new(scheme, host, 0)));

    [Theory]
    [InlineData("https", false, "engine")]
    [InlineData("DATA", false, "engine")]
    [InlineData("blob", false, "engine")]
    [InlineData("javascript", true, "blocked")]
    [InlineData("file", false, "blocked")]
    [InlineData("file", true, "engine")]
    [InlineData("mailto", false, "handOff")]
    [InlineData("zoommtg", false, "handOff")]
    [InlineData(null, false, "engine")]
    public void SchemesAreKeptBlockedOrHandedOff(string? scheme, bool appInitiated, string expected) =>
        Assert.Equal(expected, ExternalSchemePolicy.Disposition(scheme, appInitiated).Name);

    [Fact]
    public void AnOverlongSchemeIsRefused() =>
        Assert.Equal(ExternalSchemeDisposition.Blocked, ExternalSchemePolicy.Disposition(new string('a', 300), false));

    [Fact]
    public void WebLinksNeedHttpOrHttpsAndAHost() {
        Assert.True(ExternalUrlPolicy.AcceptsWebLink("HTTPS", "example.com"));
        Assert.True(ExternalUrlPolicy.AcceptsWebLink("http", "example.com"));
        Assert.False(ExternalUrlPolicy.AcceptsWebLink("https", ""));
        Assert.False(ExternalUrlPolicy.AcceptsWebLink("file", null));
        Assert.False(ExternalUrlPolicy.AcceptsWebLink("javascript", "example.com"));
        Assert.False(ExternalUrlPolicy.AcceptsWebLink(null, "example.com"));
    }

    [Fact]
    public void LocalDocumentsRefuseRemoteAuthoritiesAndUsers() {
        Assert.True(ExternalUrlPolicy.AcceptsLocalDocument(new(true, false, true, null)));
        Assert.True(ExternalUrlPolicy.AcceptsLocalDocument(new(true, false, true, "LocalHost")));
        Assert.False(ExternalUrlPolicy.AcceptsLocalDocument(new(true, false, true, "server")));
        Assert.False(ExternalUrlPolicy.AcceptsLocalDocument(new(true, true, true, null)));
        Assert.False(ExternalUrlPolicy.AcceptsLocalDocument(new(true, false, false, null)));
        Assert.False(ExternalUrlPolicy.AcceptsLocalDocument(new(false, false, true, null)));
    }

    [Fact]
    public void NotificationRequestsPromptOnlyWithActivation() {
        Assert.Equal(HostedNotificationRequestAction.PromptForSitePermission, HostedNotificationRequestAction.For(SitePermissionDecision.Ask, true));
        Assert.Equal(HostedNotificationRequestAction.RespondDefault, HostedNotificationRequestAction.For(SitePermissionDecision.Ask, false));
        Assert.Equal(HostedNotificationRequestAction.RespondDenied, HostedNotificationRequestAction.For(SitePermissionDecision.DenyForSession, true));
        Assert.Equal(HostedNotificationRequestAction.ResolveSystemAuthorization,
            HostedNotificationRequestAction.For(SitePermissionDecision.GrantPersistently, false));
    }

    [Fact]
    public void ADocumentShowsOneBlockedPopupIndicationUntilItNavigates() {
        var blocked = BlockedPopupPageState.Empty.Apply(BlockedPopupEvent.Blocked, "doc-1", Site)!;
        Assert.Equal(BlockedPopupStatus.Blocked, blocked.Status);
        Assert.Equal(1, blocked.IndicationRevision);
        Assert.Null(blocked.Apply(BlockedPopupEvent.Blocked, "doc-1", Site));
        Assert.Null(blocked.Apply(BlockedPopupEvent.PopupAllowed, null, null));

        var allowed = blocked.Apply(BlockedPopupEvent.PermissionAllowed, null, null)!;
        Assert.Equal(BlockedPopupStatus.AllowedAwaitingRetry, allowed.Status);
        Assert.Equal(BlockedPopupStatus.Blocked, allowed.Apply(BlockedPopupEvent.PermissionBlockedAgain, null, null)!.Status);

        var cleared = allowed.Apply(BlockedPopupEvent.PopupAllowed, null, null)!;
        Assert.Null(cleared.Status);
        Assert.Null(cleared.DocumentIdentifier);
        Assert.Equal(1, cleared.IndicationRevision);
        Assert.Null(cleared.Apply(BlockedPopupEvent.Navigation, null, null));
        Assert.Null(blocked.Apply(BlockedPopupEvent.Navigation, null, null)!.Status);
        Assert.Throws<BrowserRuleException>(() => cleared.Apply(BlockedPopupEvent.Blocked, null, Site));
    }

    [Fact]
    public void BasicAndDigestPromptThreeTimesAndProxiesKeepSystemHandling() {
        Assert.Equal(AuthenticationHandling.PromptForCredentials, AuthenticationPolicy.Handling(AuthenticationMethod.HttpBasic, false, 2));
        Assert.Equal(AuthenticationHandling.Cancel, AuthenticationPolicy.Handling(AuthenticationMethod.HttpDigest, false, 3));
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, AuthenticationPolicy.Handling(AuthenticationMethod.HttpBasic, true, 0));
        Assert.Equal(AuthenticationHandling.PerformDefaultHandling, AuthenticationPolicy.Handling(AuthenticationMethod.Other, false, 0));
    }

    [Fact]
    public void TheAuthenticationPromptNamesTheServerWithANonDefaultPort() {
        Assert.Equal("intranet.example", AuthenticationPolicy.SourceLabel("intranet.example", 443, "HTTPS"));
        Assert.Equal("intranet.example:8443", AuthenticationPolicy.SourceLabel("intranet.example", 8443, "https"));
        Assert.Equal("proxy.example:80", AuthenticationPolicy.SourceLabel("proxy.example", 80, null));
        Assert.Null(AuthenticationPolicy.SourceLabel("", 443, "https"));
    }

    [Fact]
    public void OnlyTheFixtureBuildTrustsOnlyItsPinnedCertificate() {
        string pinned = new('a', 64);
        Assert.True(AuthenticationPolicy.TrustsPhysicalValidationServer(AuthenticationPolicy.PhysicalValidationBundleIdentifier,
            pinned, pinned.ToUpperInvariant()));
        Assert.False(AuthenticationPolicy.TrustsPhysicalValidationServer("com.pauldavis.crest", pinned, pinned));
        Assert.False(AuthenticationPolicy.TrustsPhysicalValidationServer(AuthenticationPolicy.PhysicalValidationBundleIdentifier, null, pinned));
        Assert.False(AuthenticationPolicy.TrustsPhysicalValidationServer(AuthenticationPolicy.PhysicalValidationBundleIdentifier,
            new string('g', 64), new string('g', 64)));
        Assert.False(AuthenticationPolicy.TrustsPhysicalValidationServer(AuthenticationPolicy.PhysicalValidationBundleIdentifier,
            pinned, new string('b', 64)));
    }
}
