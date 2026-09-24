using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class NativeSitePermissionTests {
    private const string Space = "03E3E543-21FB-44F0-87BB-EF4375796517";
    private const string Camera = "B0479F10-CECA-4D7B-A4C9-86B41CB624A4";
    private const string Mailto = "7C9E6679-7425-40DE-944B-E07FC1F90AE7";
    private static readonly string SpaceID = Space.ToLowerInvariant();

    /// Exactly what the native store has written under `crest.site-permissions.v1`:
    /// Swift's JSONEncoder output, with a record from before `detail` existed.
    private const string SavedDocument = $$"""
        [{"id":"{{Camera}}","spaceID":{"rawValue":"{{Space}}"},"origin":{"scheme":"https","host":"meet.example","port":443},"permission":"camera","decision":"grantPersistently","modifiedAt":120.5},
         {"id":"{{Mailto}}","spaceID":{"rawValue":"{{Space}}"},"origin":{"scheme":"https","host":"mail.example","port":443},"permission":"externalApplications","detail":"mailto","decision":"denyPersistently","modifiedAt":130},
         {"id":"5A8B1B3E-3C39-4C7A-9E4B-6C8C7E1B2D01","spaceID":{"rawValue":"{{Space}}"},"origin":{"scheme":"https","host":"old.example","port":443},"permission":"camera","decision":"grantForSession","modifiedAt":0},
         {"id":"6B8B1B3E-3C39-4C7A-9E4B-6C8C7E1B2D02","spaceID":{"rawValue":"{{Space}}"},"origin":{"scheme":"https","host":"new.example","port":443},"permission":"futureCapability","decision":"grantPersistently","modifiedAt":0}]
        """;

    private static readonly JsonObject MeetOrigin = new() { ["scheme"] = "https", ["host"] = "meet.example", ["port"] = 443 };

    private static JsonNode Apply(NativeSitePermissionLedger ledger, JsonObject command) {
        command["version"] = 1;
        return JsonNode.Parse(ledger.Apply(Encoding.UTF8.GetBytes(command.ToJsonString())))!;
    }

    private static JsonNode Policy(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    private static NativeSitePermissionLedger Loaded() {
        var ledger = new NativeSitePermissionLedger();
        Assert.Equal(2, Apply(ledger, new() { ["command"] = "load", ["document"] = SavedDocument })["restored"]!.GetValue<int>());
        return ledger;
    }

    private static string Decision(NativeSitePermissionLedger ledger, JsonObject origin, string permission, string? detail = null,
        bool locked = false) =>
        Apply(ledger, new() {
            ["command"] = "decision",
            ["spaceID"] = SpaceID,
            ["origin"] = origin.DeepClone(),
            ["permission"] = permission,
            ["detail"] = detail,
            ["locked"] = locked
        })["decision"]!.GetValue<string>();

    [Fact]
    public void SavedRecordsLoadUnchangedAndAnswerAsBefore() {
        var ledger = Loaded();
        var mail = new JsonObject { ["scheme"] = "HTTPS", ["host"] = "Mail.Example", ["port"] = 0 };

        Assert.Equal("grantPersistently", Decision(ledger, MeetOrigin, "camera"));
        Assert.Equal("denyPersistently", Decision(ledger, mail, "externalApplications", "mailto"));
        Assert.Equal("ask", Decision(ledger, mail, "externalApplications", "tel"));
        Assert.Equal("ask", Decision(ledger, MeetOrigin, "camera", locked: true));

        var records = Apply(ledger, new() { ["command"] = "records", ["spaceID"] = SpaceID, ["locked"] = false })["records"]!.AsArray();
        Assert.Equal([Mailto, Camera], records.Select(record => record!["id"]!.GetValue<string>()));
        Assert.Equal(JsonNode.Parse(SavedDocument)![0]!.ToJsonString(), records[1]!.ToJsonString());
        Assert.Empty(Apply(ledger, new() { ["command"] = "records", ["spaceID"] = SpaceID, ["locked"] = true })["records"]!.AsArray());
    }

    /// The saved document and the ledger's JSON spell capabilities and
    /// decisions by name, so a renamed member would orphan saved choices.
    [Fact]
    public void SavedSpellingsNeverChange() {
        Assert.Equal(["camera", "microphone", "cameraAndMicrophone", "location", "notifications", "popups", "automaticDownloads",
            "externalApplications"], SitePermission.All.Select(permission => permission.Name));
        Assert.Equal(["ask", "grantForSession", "denyForSession", "grantPersistently", "denyPersistently"],
            SitePermissionDecision.All.Select(decision => decision.Name));
    }

    [Fact]
    public void AnUnreadableDocumentLoadsNothing() {
        var ledger = new NativeSitePermissionLedger();
        Assert.Equal(0, Apply(ledger, new() { ["command"] = "load", ["document"] = "not-json" })["restored"]!.GetValue<int>());
        Assert.Equal(0, Apply(ledger, new() { ["command"] = "load", ["document"] = null })["restored"]!.GetValue<int>());
        Assert.Equal("ask", Decision(ledger, MeetOrigin, "camera"));
    }

    [Fact]
    public void OnlyPersistentChoicesRewriteTheDocumentInItsSavedFormat() {
        var ledger = Loaded();
        var session = Apply(ledger, new() {
            ["command"] = "set",
            ["spaceID"] = SpaceID,
            ["origin"] = MeetOrigin.DeepClone(),
            ["permission"] = "microphone",
            ["decision"] = "grantForSession",
            ["recordID"] = Guid.NewGuid().ToString(),
            ["now"] = 200,
            ["locked"] = false
        });
        Assert.True(session["applied"]!.GetValue<bool>());
        Assert.Null(session["document"]);
        Assert.False(session["changes"]![0]!["revokesAuthorization"]!.GetValue<bool>());

        string recordID = Guid.NewGuid().ToString();
        var saved = Apply(ledger, new() {
            ["command"] = "set",
            ["spaceID"] = SpaceID,
            ["origin"] = MeetOrigin.DeepClone(),
            ["permission"] = "location",
            ["decision"] = "denyPersistently",
            ["recordID"] = recordID,
            ["now"] = 210.25,
            ["locked"] = false
        });
        var document = JsonNode.Parse(saved["document"]!.GetValue<string>())!.AsArray();
        var original = JsonNode.Parse(SavedDocument)!.AsArray();
        Assert.Equal([original[0]!.ToJsonString(), original[1]!.ToJsonString()], document.Take(2).Select(record => record!.ToJsonString()));
        var added = document[2]!;
        Assert.Equal(recordID.ToUpperInvariant(), added["id"]!.GetValue<string>());
        Assert.Equal(Space, added["spaceID"]!["rawValue"]!.GetValue<string>());
        Assert.Null(added["detail"]);
        Assert.Equal(210.25, added["modifiedAt"]!.GetValue<double>());
        Assert.Equal(3, document.Count);
        Assert.Equal(SpaceID, saved["changes"]![0]!["spaceID"]!.GetValue<string>());
        Assert.True(saved["changes"]![0]!["revokesAuthorization"]!.GetValue<bool>());

        var reset = Apply(ledger, new() { ["command"] = "reset_session" });
        Assert.Null(reset["document"]);
        Assert.Equal("microphone", reset["changes"]![0]!["permission"]!.GetValue<string>());
    }

    [Fact]
    public void ALockedSpaceRejectsWritesButCanBeReset() {
        var ledger = Loaded();
        var locked = Apply(ledger, new() {
            ["command"] = "set",
            ["spaceID"] = SpaceID,
            ["origin"] = MeetOrigin.DeepClone(),
            ["permission"] = "camera",
            ["decision"] = "denyPersistently",
            ["recordID"] = Guid.NewGuid().ToString(),
            ["now"] = 1,
            ["locked"] = true
        });
        Assert.False(locked["applied"]!.GetValue<bool>());
        Assert.Empty(locked["changes"]!.AsArray());

        var reset = Apply(ledger, new() { ["command"] = "reset_space", ["spaceID"] = SpaceID });
        Assert.Equal("[]", reset["document"]!.GetValue<string>());
        Assert.Null(reset["changes"]![0]!["origin"]);
        Assert.Equal("ask", Decision(ledger, MeetOrigin, "camera"));
    }

    [Fact]
    public void MalformedCommandsAreRejectedWithoutAnAnswer() {
        var ledger = Loaded();
        Assert.Throws<BrowserRuleException>(() => Apply(ledger, new() { ["command"] = "grant_everything" }));
        Assert.Empty(ledger.LastResult);
        Assert.Throws<ProtocolException>(() => Decision(ledger, MeetOrigin, "superpowers"));
        Assert.Throws<ProtocolException>(() => Apply(ledger, new() {
            ["command"] = "media_decision",
            ["spaceID"] = SpaceID,
            ["origin"] = MeetOrigin.DeepClone(),
            ["media"] = "screen",
            ["locked"] = false
        }));
        Assert.Equal("grantPersistently", Apply(ledger, new() {
            ["command"] = "media_decision",
            ["spaceID"] = SpaceID,
            ["origin"] = MeetOrigin.DeepClone(),
            ["media"] = "camera",
            ["locked"] = false
        })["decision"]!.GetValue<string>());
    }

    [Fact]
    public void OriginAndSchemePoliciesAnswerThroughTheEvaluator() {
        Assert.True(Policy(new() { ["operation"] = "geolocation.origin", ["origin"] = MeetOrigin.DeepClone() })["allowed"]!.GetValue<bool>());
        Assert.False(Policy(new() {
            ["operation"] = "notifications.origin",
            ["origin"] = new JsonObject { ["scheme"] = "http", ["host"] = "news.example", ["port"] = 80 }
        })["allowed"]!.GetValue<bool>());
        Assert.Equal("promptForSitePermission", Policy(new() {
            ["operation"] = "notifications.permission_request",
            ["decision"] = "ask",
            ["hasUserActivation"] = true
        })["action"]!.GetValue<string>());
        Assert.Equal("handOff", Policy(new() { ["operation"] = "external.scheme", ["scheme"] = "mailto", ["appInitiated"] = false })["disposition"]!.GetValue<string>());
        Assert.Equal("engine", Policy(new() { ["operation"] = "external.scheme", ["scheme"] = null, ["appInitiated"] = false })["disposition"]!.GetValue<string>());
        Assert.True(Policy(new() { ["operation"] = "external.url", ["scheme"] = "https", ["host"] = "example.com" })["accepted"]!.GetValue<bool>());
        Assert.False(Policy(new() { ["operation"] = "external.url", ["scheme"] = "file", ["host"] = null })["accepted"]!.GetValue<bool>());
        Assert.False(Policy(new() {
            ["operation"] = "external.local_document",
            ["isFile"] = true,
            ["hasUser"] = false,
            ["hasPath"] = true,
            ["host"] = "server"
        })["accepted"]!.GetValue<bool>());
        Assert.Throws<ProtocolException>(() => Policy(new() {
            ["operation"] = "notifications.permission_request",
            ["decision"] = "always",
            ["hasUserActivation"] = true
        }));
    }

    [Fact]
    public void PopupNoticeStateRoundTripsThroughTheEvaluator() {
        var empty = new JsonObject { ["status"] = null, ["origin"] = null, ["documentIdentifier"] = null, ["indicationRevision"] = 4 };
        var blocked = Policy(new() {
            ["operation"] = "popups.notice",
            ["state"] = empty,
            ["event"] = "blocked",
            ["documentIdentifier"] = "doc",
            ["origin"] = MeetOrigin.DeepClone()
        });
        Assert.True(blocked["changed"]!.GetValue<bool>());
        Assert.Equal("blocked", blocked["state"]!["status"]!.GetValue<string>());
        Assert.Equal(5, blocked["state"]!["indicationRevision"]!.GetValue<int>());

        var again = Policy(new() {
            ["operation"] = "popups.notice",
            ["state"] = blocked["state"]!.DeepClone(),
            ["event"] = "blocked",
            ["documentIdentifier"] = "doc",
            ["origin"] = MeetOrigin.DeepClone()
        });
        Assert.False(again["changed"]!.GetValue<bool>());
        Assert.Throws<ProtocolException>(() => Policy(new() { ["operation"] = "popups.notice", ["state"] = empty.DeepClone(), ["event"] = "stack" }));
    }

    [Fact]
    public void AuthenticationPoliciesAnswerThroughTheEvaluator() {
        Assert.Equal("cancel", Policy(new() {
            ["operation"] = "authentication.handling",
            ["method"] = "httpBasic",
            ["isProxy"] = false,
            ["previousFailureCount"] = 3
        })["handling"]!.GetValue<string>());
        Assert.Equal("intranet.example:8080", Policy(new() {
            ["operation"] = "authentication.source_label",
            ["host"] = "intranet.example",
            ["port"] = 8080,
            ["scheme"] = "http"
        })["label"]!.GetValue<string>());
        Assert.Null(Policy(new() { ["operation"] = "authentication.source_label", ["host"] = "", ["port"] = 443, ["scheme"] = "https" })["label"]);
        Assert.False(Policy(new() {
            ["operation"] = "authentication.fixture_trust",
            ["bundleIdentifier"] = "com.pauldavis.crest",
            ["expectedCertificateSHA256"] = new string('a', 64),
            ["actualCertificateSHA256"] = new string('a', 64)
        })["allowed"]!.GetValue<bool>());
        Assert.Throws<ProtocolException>(() => Policy(new() {
            ["operation"] = "authentication.handling",
            ["method"] = "ntlm",
            ["isProxy"] = false,
            ["previousFailureCount"] = 0
        }));
    }
}
