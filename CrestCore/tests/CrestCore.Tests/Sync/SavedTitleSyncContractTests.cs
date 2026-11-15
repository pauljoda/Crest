using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A saved page's title syncs with the address it was written for, so a build
/// that changes the saved address without knowing the title can't make the
/// title name another page.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASyncedSavedTitleCountsOnlyForTheSavedAddressItWasWrittenFor() {
        var (space, profile, tab) = (Fixed(280), Fixed(281), Fixed(282));
        var pinned = TabOf(tab, "Away page", "https://example.com/away", placement: "pinned");
        pinned["savedURL"] = "https://example.com/";
        pinned["savedTitle"] = "Home";
        var session = SessionOf(SpaceOf(space, profile, tabs: [pinned]));
        var journal = new JournalUnderTest(Fixed(283));
        journal.Stage(session);
        var value = journal.Value(SyncRecordKind.Tab, tab)!;
        Assert.Equal(("Home", "https://example.com/"),
            (value["savedTitle"]?.GetValue<string>(), value["savedTitleURL"]?.GetValue<string>()));

        // A build that keeps the title as an unknown field replaces the saved
        // address: the title it carries forward no longer counts.
        var replaced = value.DeepClone().AsObject();
        replaced["savedURL"] = "https://example.com/other";
        journal.Merge(SavedRecord(SyncRecordKind.Tab, replaced, journal.Clock + 10, Fixed(284)));
        var merged = FirstSpace(journal.Materialize(session))["tabs"]![0]!;
        Assert.Equal(("https://example.com/other", null),
            (merged["savedURL"]?.GetValue<string>(), merged["savedTitle"]?.GetValue<string>()));

        // A title written for that address counts.
        var titled = replaced.DeepClone().AsObject();
        titled["savedTitle"] = "Other page";
        titled["savedTitleURL"] = "https://example.com/other";
        journal.Merge(SavedRecord(SyncRecordKind.Tab, titled, journal.Clock + 20, Fixed(284)));
        merged = FirstSpace(journal.Materialize(session))["tabs"]![0]!;
        Assert.Equal("Other page", merged["savedTitle"]?.GetValue<string>());
    }
}
