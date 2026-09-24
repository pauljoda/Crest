using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class NativePresentationPolicyTests {
    private static readonly string Work = "00000000-0000-4000-8000-000000000031";
    private static readonly string Personal = "00000000-0000-4000-8000-000000000032";
    private static readonly string Profile = "00000000-0000-4000-8000-000000000041";

    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static string Presentation(string selection, bool page, bool navigation = false, bool process = false,
        string unloaded = "remainUnloaded") => Evaluate(new() {
            ["operation"] = "page.presentation",
            ["selection"] = selection,
            ["hasActivePage"] = page,
            ["hasNavigationFailure"] = navigation,
            ["hasProcessFailure"] = process,
            ["unloadedBehavior"] = unloaded
        })["presentation"]!.GetValue<string>();

    [Fact]
    public void PagePresentationFollowsTheTabKindThenThePagesState() {
        Assert.Equal("noSelection", Presentation("none", true, true, true));
        Assert.Equal("nativeContent", Presentation("nativeContent", false));
        Assert.Equal("startPage", Presentation("startPage", true, true));
        Assert.Equal("unloaded", Presentation("webPage", false, true));
        Assert.Equal("automaticRestore", Presentation("webPage", false, unloaded: "restoreAutomatically"));
        Assert.Equal("navigationFailure", Presentation("webPage", true, true, true));
        Assert.Equal("processFailure", Presentation("webPage", true, process: true));
        Assert.Equal("livePage", Presentation("webPage", true));
        Assert.Equal(ProtocolErrorCodes.InvalidPagePresentation,
            Assert.Throws<ProtocolException>(() => Presentation("reader", true)).Code);
    }

    [Fact]
    public void QuickWindowsArchiveOnceAndRetargetOnlyOnChange() {
        static bool Archives(bool archived, bool promoted, bool page) => Evaluate(new() {
            ["operation"] = "quick_window.dismissal",
            ["wasArchived"] = archived,
            ["wasPromoted"] = promoted,
            ["hasPage"] = page
        })["archives"]!.GetValue<bool>();
        Assert.True(Archives(false, false, true));
        Assert.False(Archives(true, false, true));
        Assert.False(Archives(false, true, true));
        Assert.False(Archives(false, false, false));

        static JsonObject At(string url, string space) => new() { ["url"] = url, ["spaceID"] = space, ["profileID"] = Profile };
        static JsonNode Retarget(JsonObject current, JsonObject next, string? page) => Evaluate(new() {
            ["operation"] = "quick_window.retarget",
            ["current"] = current,
            ["next"] = next,
            ["pageURL"] = page
        });
        var same = Retarget(At("https://example.com/a", Work), At("https://example.com/a", Work), "https://example.com/a");
        Assert.False(same["revises"]!.GetValue<bool>());
        var navigated = Retarget(At("https://example.com/a", Work), At("https://example.com/b", Work), "https://example.com/b");
        Assert.True(navigated["revises"]!.GetValue<bool>());
        Assert.False(navigated["remembersSpace"]!.GetValue<bool>());
        var moved = Retarget(At("https://example.com/a", Work), At("https://example.com/a", Personal), "https://example.com/a");
        Assert.True(moved["revises"]!.GetValue<bool>());
        Assert.True(moved["remembersSpace"]!.GetValue<bool>());
        // An empty lookup has no site to remember.
        var lookup = Retarget(At("crest://quick-window", Work), At("crest://quick-window", Personal), null);
        Assert.True(lookup["revises"]!.GetValue<bool>());
        Assert.False(lookup["remembersSpace"]!.GetValue<bool>());
    }


    [Fact]
    public void BrandingNormalizationClampsBannerRangesAndCrestLayersAndReadsTermsAsTheNativeReaderDoes() {
        var branding = new JsonObject {
            ["colors"] = new JsonArray(Color(2, 0.5, -1), Color(0.1, 0.2, 0.3), Color(0.4, 0.5, 0.6), Color(0.7, 0.8, 0.9)),
            ["bannerStrength"] = 1.4,
            ["readabilityFade"] = -0.2,
            ["gradientAngle"] = -90.0,
            ["folderColorIntensity"] = 3.0,
            ["bannerPattern"] = "futurePattern",
            ["crest"] = new JsonObject {
                ["symbol"] = "mountain",
                ["charge"] = new JsonObject { ["future"] = true },
                ["symbolColorIndex"] = 5,
                ["trimColorIndex"] = 2,
                ["palette"] = new JsonArray(),
                ["plateScale"] = 3.0,
                ["chargeOffset"] = -1.0,
                ["sealTeeth"] = 40
            }
        };
        var result = Evaluate(new() { ["operation"] = "branding.normalize", ["branding"] = branding })["branding"]!;
        Assert.Equal(3, result["colors"]!.AsArray().Count);
        Assert.Equal(1.0, result["colors"]![0]!["red"]!.GetValue<double>());
        Assert.Equal(0.0, result["colors"]![0]!["blue"]!.GetValue<double>());
        Assert.Equal(1.0, result["bannerStrength"]!.GetValue<double>());
        Assert.Equal(0.0, result["readabilityFade"]!.GetValue<double>());
        Assert.Equal(270.0, result["gradientAngle"]!.GetValue<double>());
        Assert.Equal(1.0, result["folderColorIntensity"]!.GetValue<double>());
        Assert.Equal("solid", result["bannerPattern"]!.GetValue<string>());
        var crest = result["crest"]!;
        Assert.Null(crest["palette"]);
        Assert.Equal(0, crest["symbolColorIndex"]!.GetValue<int>());
        Assert.Equal(2, crest["trimColorIndex"]!.GetValue<int>());
        Assert.Equal("none", crest["charge"]!["kind"]!.GetValue<string>());
        Assert.Equal(1.15, crest["plateScale"]!.GetValue<double>());
        Assert.Equal(-0.2, crest["chargeOffset"]!.GetValue<double>());
        Assert.Equal(24, crest["sealTeeth"]!.GetValue<int>());

        // A custom figure that is the crest's own symbol is no custom figure; a
        // monogram keeps two capitals.
        JsonNode Figure(JsonObject charge) => Evaluate(new() {
            ["operation"] = "branding.normalize",
            ["branding"] = new JsonObject { ["crest"] = new JsonObject { ["symbol"] = "mountain", ["charge"] = charge } }
        })["branding"]!["crest"]!;
        Assert.Null(Figure(new() { ["kind"] = "heraldic", ["value"] = "mountain" })["charge"]);
        Assert.Equal("PD", Figure(new() { ["kind"] = "monogram", ["value"] = " pdx " })["charge"]!["value"]!.GetValue<string>());

        var empty = Evaluate(new() { ["operation"] = "branding.normalize", ["branding"] = new JsonObject { ["colors"] = new JsonArray() } });
        Assert.Single(empty["branding"]!["colors"]!.AsArray());
        Assert.Equal(ProtocolErrorCodes.InvalidBranding, Assert.Throws<ProtocolException>(() =>
            Evaluate(new() { ["operation"] = "branding.normalize", ["branding"] = "indigo" })).Code);
    }

    private static JsonObject Color(double red, double green, double blue) =>
        new() { ["red"] = red, ["green"] = green, ["blue"] = blue, ["alpha"] = 1.0 };
}
