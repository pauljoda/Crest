using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The app's behavior preferences sync as one record for the account, which no
/// Space owns: it stays off the cloud until a person changes it, a later edit
/// wins whole, and no device deletes it.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    [Fact]
    public void AppPreferencesNeverChosenStayOffTheCloud() {
        var journal = new JournalUnderTest(Fixed(2_100));

        journal.Stage(WithAppPreferences(OneSpaceSession(), AppPreferences.Default));
        journal.Stage(OneSpaceSession());

        Assert.Empty(journal.Values(SyncRecordKind.AppPreferences));
    }

    [Fact]
    public void ChangedAppPreferencesTravelAsOneRecordNoSpaceOwns() {
        var journal = new JournalUnderTest(Fixed(2_101));
        var chosen = Chosen();

        journal.Stage(WithAppPreferences(OneSpaceSession(), chosen));

        var value = Assert.Single(journal.Values(SyncRecordKind.AppPreferences));
        Assert.Equal(AppPreferencesPayload.RecordId, StoredSessionCodec.Identity(value["id"]));
        Assert.Equal(chosen, StoredSessionCodec.DecodeAppPreferences(value));
        var record = journal.Record(SyncRecordKind.AppPreferences, AppPreferencesPayload.RecordId)!;
        Assert.Equal(AppPreferencesPayload.RecordId, StoredSessionCodec.Identity(record["spaceID"]));
        Assert.Contains(SyncRecordKind.AppPreferences.RecordName(AppPreferencesPayload.RecordId), journal.Pending);
        var uploading = journal.Journal.Uploading(new(SyncRecordKind.AppPreferences, AppPreferencesPayload.RecordId))!;
        Assert.Equal(4, uploading.Schema);
    }

    [Fact]
    public void AnotherDeviceTakesTheAppPreferencesFromTheCloud() {
        var chosen = Chosen();
        var sender = new JournalUnderTest(Fixed(2_102));
        sender.Stage(WithAppPreferences(OneSpaceSession(), chosen));
        var receiver = new JournalUnderTest(Fixed(2_103));
        receiver.Merge(sender.Records);

        var materialized = receiver.Materialize(WithAppPreferences(OneSpaceSession(), AppPreferences.Default));

        Assert.Equal(chosen, StoredSessionCodec.DecodeAppPreferences(materialized["appPreferences"]));
    }

    [Fact]
    public void ADeviceThatNeverChoseDoesNotOverwriteTheCloudsChoices() {
        var chosen = Chosen();
        var sender = new JournalUnderTest(Fixed(2_104));
        sender.Stage(WithAppPreferences(OneSpaceSession(), chosen));
        var receiver = new JournalUnderTest(Fixed(2_105));

        receiver.Stage(WithAppPreferences(OneSpaceSession(), AppPreferences.Default));
        receiver.Merge(sender.Records);
        receiver.Stage(WithAppPreferences(OneSpaceSession(), chosen));

        Assert.Equal(chosen, StoredSessionCodec.DecodeAppPreferences(
            receiver.Materialize(WithAppPreferences(OneSpaceSession(), AppPreferences.Default))["appPreferences"]));
        Assert.DoesNotContain(SyncRecordKind.AppPreferences.RecordName(AppPreferencesPayload.RecordId), receiver.Pending);
    }

    [Fact]
    public void TheLaterAppPreferencesEditWins() {
        var first = new JournalUnderTest(Fixed(2_106));
        first.Stage(WithAppPreferences(OneSpaceSession(), Chosen()));
        var second = new JournalUnderTest(Fixed(2_107));
        second.Merge(first.Records);
        var edited = Chosen() with { ChecksSpelling = true, SavedTabClose = SavedTabClosePolicy.ResumeLastLocation };
        second.Stage(WithAppPreferences(OneSpaceSession(), edited), at: 200);

        first.Merge(second.Records);

        Assert.Equal(edited, StoredSessionCodec.DecodeAppPreferences(
            first.Materialize(WithAppPreferences(OneSpaceSession(), Chosen()))["appPreferences"]));
    }

    [Fact]
    public void ResettingAppPreferencesToTheDefaultsSyncsOnceTheCloudHoldsThem() {
        var journal = new JournalUnderTest(Fixed(2_108));
        journal.Stage(WithAppPreferences(OneSpaceSession(), Chosen()));

        journal.Stage(WithAppPreferences(OneSpaceSession(), AppPreferences.Default), at: 200);

        Assert.Equal(AppPreferences.Default, StoredSessionCodec.DecodeAppPreferences(
            Assert.Single(journal.Values(SyncRecordKind.AppPreferences))));
    }

    [Fact]
    public void NoDeviceDeletesTheAppPreferences() {
        var journal = new JournalUnderTest(Fixed(2_109));
        journal.Stage(WithAppPreferences(OneSpaceSession(), Chosen()));

        journal.Stage(OneSpaceSession(), at: 200);

        Assert.Single(journal.Values(SyncRecordKind.AppPreferences));
    }

    [Fact]
    public void AnotherDevicesAppPreferencesReachTheSessionThroughTheCore() {
        var chosen = Chosen();
        var sender = new JournalUnderTest(Fixed(2_110));
        sender.Stage(WithAppPreferences(OneSpaceSession(), chosen));
        using var device = new SyncingDevice(WithAppPreferences(OneSpaceSession(), AppPreferences.Default), Fixed(2_111));

        var session = device.Merge(sender.Records);

        Assert.Equal(chosen, StoredSessionCodec.DecodeAppPreferences(session["appPreferences"]));
    }

    #endregion

    #region Actions - Sessions

    private static AppPreferences Chosen() => AppPreferences.Default with {
        Startup = StartupBehavior.Named("lastActiveTab")!,
        OffersTranslation = false,
        AutomaticallyTranslates = true,
        ChecksSpelling = true,
        SplitFocusFollowsMouse = true
    };

    private static JsonObject WithAppPreferences(JsonObject session, AppPreferences preferences) {
        var result = session.DeepClone().AsObject();
        result["appPreferences"] = StoredSessionCodec.Encode(preferences);
        return result;
    }

    #endregion
}
