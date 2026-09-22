using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class MediaSessionPolicyTests {
    private static readonly MediaSessionIdentity Fresh = new(false, null, null, false, null);

    private static MediaSessionEvent Report(ulong sequence, MediaPlaybackState playback = MediaPlaybackState.Playing,
        bool active = true, bool invalidated = false) => new(sequence, invalidated, active, playback);

    private static JsonNode Evaluate(JsonObject request) {
        request["version"] = 1;
        return JsonNode.Parse(NativePolicyEvaluator.Evaluate(Encoding.UTF8.GetBytes(request.ToJsonString())))!;
    }

    [Fact]
    public void StaleAndRetiredReportsChangeNothing() {
        var seen = Fresh with { LastSequence = 4, Ordinal = 2 };
        Assert.False(MediaSessionPolicy.Decide(Report(4), seen, 10, 7).Accepted);
        Assert.False(MediaSessionPolicy.Decide(Report(3), seen, 10, 7).Accepted);
        Assert.False(MediaSessionPolicy.Decide(Report(9), seen with { IsRetired = true }, 10, 7).Accepted);
        Assert.False(MediaSessionPolicy.Decide(Report(0), Fresh, 10, 7).Accepted);
        Assert.True(MediaSessionPolicy.Decide(Report(5), seen, 10, 7).Accepted);
    }

    [Fact]
    public void APublishedDocumentKeepsItsOrdinalAndSupersedesItsTabSiblings() {
        var first = MediaSessionPolicy.Decide(Report(1), Fresh, 0, 7);
        Assert.Equal(MediaSessionDisposition.Publish, first.Disposition);
        Assert.True(first.SupersedesTabSiblings);
        Assert.Equal(7UL, first.Ordinal);
        Assert.Equal(8UL, first.NextOrdinal);

        var update = MediaSessionPolicy.Decide(Report(2), Fresh with { LastSequence = 1, Ordinal = 7 }, 1, 8);
        Assert.Equal(7UL, update.Ordinal);
        Assert.Equal(8UL, update.NextOrdinal);
    }

    [Fact]
    public void InvalidationRetiresAndAnInactiveSessionOnlyWithdrawsItsCard() {
        var retired = MediaSessionPolicy.Decide(Report(2, invalidated: true), Fresh with { LastSequence = 1, Ordinal = 3 }, 1, 4);
        Assert.Equal(MediaSessionDisposition.Retire, retired.Disposition);
        Assert.False(retired.SupersedesTabSiblings);
        var cleared = MediaSessionPolicy.Decide(Report(2, active: false), Fresh with { LastSequence = 1, Ordinal = 3 }, 1, 4);
        Assert.Equal(MediaSessionDisposition.Clear, cleared.Disposition);
        Assert.Null(cleared.Ordinal);
        Assert.Equal(4UL, cleared.NextOrdinal);
    }

    [Fact]
    public void AHiddenCardReturnsOnlyWhenPlaybackStartsAfresh() {
        var hidden = Fresh with { LastSequence = 1, Ordinal = 1, IsDismissed = true, PreviousPlayback = MediaPlaybackState.Paused };
        Assert.True(MediaSessionPolicy.Decide(Report(2), hidden, 1, 2).ClearsDismissal);
        Assert.False(MediaSessionPolicy.Decide(Report(2, MediaPlaybackState.Paused), hidden, 1, 2).ClearsDismissal);
        Assert.False(MediaSessionPolicy.Decide(Report(2),
            hidden with { PreviousPlayback = MediaPlaybackState.Playing }, 1, 2).ClearsDismissal);
        Assert.True(MediaSessionPolicy.Decide(Report(2), hidden with { PreviousPlayback = null }, 1, 2).ClearsDismissal);
    }

    [Fact]
    public void RememberedIdentitiesStayWithinTheirWindow() {
        const int limit = MediaSessionPolicy.MaximumRetainedIdentities;
        Assert.Equal(0, MediaSessionPolicy.Decide(Report(1), Fresh, limit - 1, 1).EvictOldest);
        Assert.Equal(1, MediaSessionPolicy.Decide(Report(1, invalidated: true), Fresh, limit, 1).EvictOldest);
        Assert.Equal(0, MediaSessionPolicy.Decide(Report(2), Fresh with { LastSequence = 1 }, limit, 1).EvictOldest);
    }

    [Fact]
    public void SessionsAreShownInFirstPublishedOrderAndTheLivelyOneOwnsNowPlaying() {
        MediaSessionEntry Entry(string id, ulong ordinal, MediaPlaybackState playback, bool audible) => new(id, ordinal, playback, audible);
        var arbitration = MediaSessionPolicy.Arbitrate([
            Entry("c", 9, MediaPlaybackState.Paused, true),
            Entry("a", 2, MediaPlaybackState.Playing, false),
            Entry("b", 5, MediaPlaybackState.Playing, true),
            Entry("d", 1, MediaPlaybackState.None, true)
        ]);
        Assert.Equal([3, 1, 2, 0], arbitration.Order);
        Assert.Equal(2, arbitration.NowPlaying);

        var tie = MediaSessionPolicy.Arbitrate([
            Entry("a", 2, MediaPlaybackState.Paused, true),
            Entry("b", 5, MediaPlaybackState.Paused, true)
        ]);
        Assert.Equal(1, tie.NowPlaying);
        Assert.Null(MediaSessionPolicy.Arbitrate([Entry("a", 1, MediaPlaybackState.None, true)]).NowPlaying);
        Assert.Equal(BrowserRuleCodes.DuplicateMediaSession, Assert.Throws<BrowserRuleException>(() => MediaSessionPolicy.Arbitrate([
            Entry("a", 1, MediaPlaybackState.Paused, true), Entry("a", 2, MediaPlaybackState.Paused, true)
        ])).Code);
    }

    [Fact]
    public void TheOperationsCarryOnlyOrderingAndLifecycleFacts() {
        var decision = Evaluate(new() {
            ["operation"] = "media.session_event",
            ["event"] = new JsonObject { ["sequence"] = 3, ["invalidated"] = false, ["active"] = true, ["playbackState"] = "playing" },
            ["identity"] = new JsonObject {
                ["retired"] = false,
                ["lastSequence"] = 2,
                ["ordinal"] = 4,
                ["dismissed"] = true,
                ["previousPlaybackState"] = "paused"
            },
            ["retainedIdentities"] = 3,
            ["nextOrdinal"] = 6
        });
        Assert.True(decision["accepted"]!.GetValue<bool>());
        Assert.Equal("publish", decision["disposition"]!.GetValue<string>());
        Assert.Equal(4UL, decision["ordinal"]!.GetValue<ulong>());
        Assert.True(decision["clearsDismissal"]!.GetValue<bool>());

        var arbitration = Evaluate(new() {
            ["operation"] = "media.arbitrate",
            ["sessions"] = new JsonArray(
                new JsonObject { ["id"] = "tab:b", ["ordinal"] = 2, ["playbackState"] = "paused", ["audible"] = false },
                new JsonObject { ["id"] = "tab:a", ["ordinal"] = 1, ["playbackState"] = "none", ["audible"] = false })
        });
        Assert.Equal(1, arbitration["order"]![0]!.GetValue<int>());
        Assert.Equal(0, arbitration["nowPlaying"]!.GetValue<int>());

        var withTitle = new JsonObject {
            ["operation"] = "media.arbitrate",
            ["sessions"] = new JsonArray(new JsonObject {
                ["id"] = "tab:a",
                ["ordinal"] = 1,
                ["playbackState"] = "paused",
                ["audible"] = false,
                ["title"] = "Song"
            })
        };
        Assert.Equal(ProtocolErrorCodes.UnexpectedMember, Assert.Throws<ProtocolException>(() => Evaluate(withTitle)).Code);
        var unknownState = new JsonObject {
            ["operation"] = "media.arbitrate",
            ["sessions"] = new JsonArray(new JsonObject { ["id"] = "tab:a", ["ordinal"] = 1, ["playbackState"] = "buffering", ["audible"] = false })
        };
        Assert.Equal(ProtocolErrorCodes.InvalidPlaybackState, Assert.Throws<ProtocolException>(() => Evaluate(unknownState)).Code);
    }
}
