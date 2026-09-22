using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class NativeCredentialPolicyTests {
    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static JsonObject Origin(string host = "accounts.example.com", string scheme = "https") =>
        new() { ["scheme"] = scheme, ["host"] = host, ["port"] = scheme == "https" ? 443 : 80 };

    private static JsonObject Capture(string kind) => new() {
        ["operation"] = "credentials.capture",
        ["event"] = kind,
        ["frameOrigin"] = Origin(),
        ["topLevelOrigin"] = Origin(),
        ["isMainFrame"] = true,
        ["hasFormID"] = true,
        ["hasUsername"] = false,
        ["hasPassword"] = true,
        ["passwordKind"] = "current",
        ["hasVisiblePasswordField"] = null,
        ["hasFillTarget"] = true,
        ["now"] = 1_001.0,
        ["usernameHint"] = new JsonObject { ["origin"] = Origin(), ["topLevelOrigin"] = Origin(), ["capturedAt"] = 1_000.0 },
        ["pendingCandidate"] = null
    };

    [Fact]
    public void ASubmitWithAHintIsCapturedAndCarriesTheLifetimes() {
        var result = Evaluate(Capture("submit"));
        Assert.Equal("captureCandidate", result["action"]!.GetValue<string>());
        Assert.Equal("hint", result["usernameSource"]!.GetValue<string>());
        Assert.False(result["clearsUsernameHint"]!.GetValue<bool>());
        Assert.Equal(CredentialCapturePolicy.CandidateLifetime, result["candidateLifetime"]!.GetValue<double>());
        Assert.Equal(CredentialCapturePolicy.UsernameHintLifetime, result["usernameHintLifetime"]!.GetValue<double>());
    }

    [Fact]
    public void TheCaptureContractCarriesNoCredentialValues() {
        var request = Capture("submit");
        request["password"] = "secret";
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember,
            Assert.Throws<ProtocolException>(() => Evaluate(request)).Code);
        var withName = Capture("submit");
        withName["usernameHint"]!["username"] = "person";
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember,
            Assert.Throws<ProtocolException>(() => Evaluate(withName)).Code);
        var match = new JsonObject {
            ["operation"] = "credentials.save_plan",
            ["matchID"] = Guid.NewGuid().ToString(),
            ["stored"] = new JsonObject { ["id"] = Guid.NewGuid().ToString(), ["password"] = "secret" }
        };
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember, Assert.Throws<ProtocolException>(() => Evaluate(match)).Code);
    }

    [Fact]
    public void InvalidOriginsAndEventsAreRejected() {
        var request = Capture("submit");
        request["frameOrigin"] = Origin(scheme: "ftp");
        Assert.Equal(BrowserRuleCodes.InvalidCredentialOrigin, Assert.Throws<BrowserRuleException>(() => Evaluate(request)).Code);
        var geometry = Capture("fieldGeometry");
        Assert.Equal(ProtocolErrorCodes.InvalidCredentialEvent, Assert.Throws<ProtocolException>(() => Evaluate(geometry)).Code);
    }

    [Fact]
    public void TheSavePlanTakesTheMatchThenThePlatformComparison() {
        var older = Guid.NewGuid();
        var newer = Guid.NewGuid();
        var match = Evaluate(new() {
            ["operation"] = "credentials.save_match",
            ["username"] = "Person",
            ["records"] = new JsonArray(
                new JsonObject { ["id"] = older.ToString(), ["username"] = "person", ["updatedAt"] = 1.0, ["lastUsedAt"] = null },
                new JsonObject { ["id"] = newer.ToString(), ["username"] = "PERSON", ["updatedAt"] = 2.0, ["lastUsedAt"] = null })
        });
        Assert.Equal(newer.ToString(), match["id"]!.GetValue<string>());

        var plan = Evaluate(new() {
            ["operation"] = "credentials.save_plan",
            ["matchID"] = newer.ToString(),
            ["stored"] = new JsonObject { ["id"] = newer.ToString(), ["passwordMatches"] = false }
        });
        Assert.Equal("update", plan["plan"]!.GetValue<string>());
        Assert.Equal(newer.ToString(), plan["id"]!.GetValue<string>());
        Assert.True(plan["requiresConfirmation"]!.GetValue<bool>());

        var created = Evaluate(new() { ["operation"] = "credentials.save_plan", ["matchID"] = null, ["stored"] = null });
        Assert.Equal("create", created["plan"]!.GetValue<string>());
        Assert.Null(created["id"]);
    }

    [Fact]
    public void RecencyNeedsNoUsernames() {
        var used = Guid.NewGuid();
        var result = Evaluate(new() {
            ["operation"] = "credentials.most_recent",
            ["records"] = new JsonArray(
                new JsonObject { ["id"] = Guid.NewGuid().ToString(), ["updatedAt"] = 5.0, ["lastUsedAt"] = null },
                new JsonObject { ["id"] = used.ToString(), ["updatedAt"] = 1.0, ["lastUsedAt"] = 9.0 })
        });
        Assert.Equal(used.ToString(), result["id"]!.GetValue<string>());
        Assert.Null(Evaluate(new() { ["operation"] = "credentials.most_recent", ["records"] = new JsonArray() })["id"]);
    }

    [Fact]
    public void TheGeneratorOperationReturnsARecipeNeverAPassword() {
        var recipe = Evaluate(new() { ["operation"] = "credentials.password_recipe", ["length"] = null });
        Assert.Equal(StrongPasswordPolicy.DefaultLength, recipe["length"]!.GetValue<int>());
        Assert.Equal(4, recipe["groups"]!.AsArray().Count);
        Assert.Equal(BrowserRuleCodes.InvalidPasswordLength, Assert.Throws<BrowserRuleException>(() =>
            Evaluate(new() { ["operation"] = "credentials.password_recipe", ["length"] = 8 })).Code);
    }

    [Fact]
    public void PasskeyAndWriteThroughOperationsUseTheNativeCaseNames() {
        Assert.Equal("deviceNotConfigured", Evaluate(new() {
            ["operation"] = "passkeys.access_status",
            ["hasManagedCapability"] = true,
            ["deviceConfiguration"] = "notConfigured",
            ["authorizationState"] = "authorized"
        })["status"]!.GetValue<string>());
        Assert.Equal("isolatedLaunch", Evaluate(new() {
            ["operation"] = "credentials.system_write_through",
            ["isMobilePlatform"] = true,
            ["supportsSystemAPI"] = true,
            ["hasManagedBrowserCapability"] = true,
            ["isLaunchIsolated"] = true
        })["availability"]!.GetValue<string>());
        Assert.False(Evaluate(new() {
            ["operation"] = "credentials.system_write_through_offer",
            ["offersSaveToSystemPasswords"] = true,
            ["availability"] = "available",
            ["isPrivateBrowsing"] = true
        })["offers"]!.GetValue<bool>());
        Assert.True(Evaluate(new() {
            ["operation"] = "credentials.fill",
            ["passwordKind"] = "new",
            ["source"] = "generated"
        })["allowed"]!.GetValue<bool>());
    }
}
