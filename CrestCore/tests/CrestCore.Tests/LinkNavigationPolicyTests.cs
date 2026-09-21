using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed class LinkNavigationPolicyTests {
    [Theory]
    [InlineData(true, false, false, LinkPeekModifier.Option, LinkNavigationDecision.BackgroundTab)]
    [InlineData(false, true, false, LinkPeekModifier.Option, LinkNavigationDecision.PeekModifier)]
    [InlineData(true, false, false, LinkPeekModifier.Command, LinkNavigationDecision.PeekModifier)]
    [InlineData(false, true, false, LinkPeekModifier.Command, LinkNavigationDecision.BackgroundTab)]
    [InlineData(true, true, false, LinkPeekModifier.Option, LinkNavigationDecision.PeekModifier)]
    [InlineData(true, true, false, LinkPeekModifier.Command, LinkNavigationDecision.PeekModifier)]
    [InlineData(false, false, true, LinkPeekModifier.Option, LinkNavigationDecision.BackgroundTab)]
    [InlineData(false, false, true, LinkPeekModifier.Command, LinkNavigationDecision.BackgroundTab)]
    [InlineData(false, true, true, LinkPeekModifier.Option, LinkNavigationDecision.PeekModifier)]
    public void ConfigurableModifiersAndMiddleClickUseOneNavigationPolicy(bool command, bool option, bool middle,
        LinkPeekModifier preference, LinkNavigationDecision expected) {
        var (peek, newTab) = LinkNavigationPolicy.Modifiers(command, option, middle, preference);
        Assert.Equal(expected, Decide(peek: peek, newTab: newTab));
        Assert.Equal(expected == LinkNavigationDecision.BackgroundTab ? LinkNavigationDecision.ForegroundTab : expected,
            Decide(peek: peek, newTab: newTab, shift: true));
    }

    [Fact]
    public void HoldingBothKeysDoesNotTurnDeclinedPeekIntoANewTab() {
        var (peek, newTab) = LinkNavigationPolicy.Modifiers(true, true, false, LinkPeekModifier.Option);
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: peek, newTab: newTab, owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: peek, newTab: newTab, topLevel: false));
    }

    [Theory]
    [InlineData("https://www.apple.com/news/", "saved", true, LinkNavigationDecision.Navigate)]
    [InlineData("http://APPLE.com:8080/news/", "pinned", true, LinkNavigationDecision.Navigate)]
    [InlineData("https://developer.apple.com/", "saved", true, LinkNavigationDecision.PeekSavedSite)]
    [InlineData("https://example.com/", "pinned", true, LinkNavigationDecision.PeekSavedSite)]
    [InlineData("https://example.com/", "open", true, LinkNavigationDecision.Navigate)]
    [InlineData("https://example.com/", "saved", false, LinkNavigationDecision.Navigate)]
    [InlineData("mailto:test@example.com", "saved", true, LinkNavigationDecision.Navigate)]
    [InlineData("file:///tmp/example.html", "saved", true, LinkNavigationDecision.Navigate)]
    [InlineData("crest://extensions/", "saved", true, LinkNavigationDecision.Navigate)]
    public void SavedSiteProtectionPreservesHostsPlacementAndOptOut(string url, string placement,
        bool automaticallyOpensPeek, LinkNavigationDecision expected) =>
        Assert.Equal(expected, Decide(url, placement: placement, automatic: automaticallyOpensPeek));

    [Theory]
    [InlineData(false, false, LinkNavigationDecision.BackgroundTab)]
    [InlineData(false, true, LinkNavigationDecision.ForegroundTab)]
    [InlineData(true, false, LinkNavigationDecision.ForegroundTab)]
    [InlineData(true, true, LinkNavigationDecision.BackgroundTab)]
    public void ExplicitNewTabOverridesSavedSiteAndShiftReversesSelection(bool focus, bool shift,
        LinkNavigationDecision expected) => Assert.Equal(expected, Decide(newTab: true, shift: shift, focus: focus));

    [Fact]
    public void PeekModifierWinsOverNewTabButRequiresAnOwnedTopLevelLink() {
        Assert.Equal(LinkNavigationDecision.PeekModifier, Decide(peek: true, newTab: true));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(peek: true, userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide("javascript:alert(1)", peek: true));
    }

    [Fact]
    public void EngineNavigationsAndMissingSavedContextNeverBecomeAutomaticPeek() {
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(userLink: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(topLevel: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(owned: false));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(savedUrl: null));
        Assert.Equal(LinkNavigationDecision.Navigate, Decide(null));
    }

    [Fact]
    public void InternationalHostSpellingsDoNotSplitTheSavedSite() =>
        Assert.Equal(LinkNavigationDecision.Navigate, Decide("https://www.xn--bcher-kva.example/page",
            savedUrl: "https://bücher.example/"));

    private static LinkNavigationDecision Decide(string? url = "https://example.com/", bool userLink = true,
        bool topLevel = true, bool peek = false, bool newTab = false, bool shift = false, bool focus = false,
        bool owned = true, string? placement = "saved", string? savedUrl = "https://apple.com/", bool automatic = true) =>
        LinkNavigationPolicy.Decide(url, userLink, topLevel, peek, newTab, shift, focus, owned, placement, savedUrl, automatic);
}
