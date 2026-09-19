using CrestCore.Domain;
using Xunit;

namespace CrestCore.Tests;

public sealed class SplitContractsTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-19T12:00:00Z");
    private static BrowserSpace Space() => new(new(Guid.NewGuid()), new(Guid.NewGuid()), "Splits");
    private static BrowserTab Tab(BrowserSpace space, string title, TabPlacement placement = TabPlacement.Current, Guid? split = null)
    {
        var tab = BrowserTab.Restore(new(new(Guid.NewGuid()), TabKind.Web, "https://example.com/" + title, title,
            placement, null, placement == TabPlacement.Current ? null : "https://saved.example/", "Custom " + title,
            Now, null, null, true, split, null));
        space.Add(tab, null); return tab;
    }
    [Fact]
    public void OpeningFromSavedTabsOrSplitMembersHonorsTheCurrentSectionAndWholeRun()
    {
        var space = Space(); var pinned = Tab(space, "pinned", TabPlacement.Pinned);
        var saved = Tab(space, "saved", TabPlacement.Saved); var group = Guid.NewGuid();
        var first = Tab(space, "first", split: group); var second = Tab(space, "second", split: group);
        var third = Tab(space, "third", split: group);
        var fromSaved = new BrowserTab(new(Guid.NewGuid()), TabKind.Web, "https://example.org", null);
        space.AddOpenedTab(fromSaved, saved.Id);
        Assert.Equal(new[] { pinned.Id, saved.Id, fromSaved.Id, first.Id, second.Id, third.Id }, space.Tabs.Select(t => t.Id));
        var fromSplit = new BrowserTab(new(Guid.NewGuid()), TabKind.Web, "https://example.org/next", null);
        space.AddOpenedTab(fromSplit, second.Id);
        Assert.Equal(fromSplit.Id, space.Tabs[^1].Id);
        space.Place(second.Id, TabPlacement.Pinned, null, Now);
        Assert.Equal(new[] { pinned.Id, second.Id, saved.Id, fromSaved.Id, first.Id, third.Id, fromSplit.Id }, space.Tabs.Select(t => t.Id));
        Assert.Null(second.SplitGroupId); Assert.Equal(second.Url, second.SavedUrl);
        Assert.Equal(group, first.SplitGroupId); Assert.Equal(group, third.SplitGroupId);
    }
    [Fact]
    public void JoiningDurableTabsCopiesTheDestinationRunAndKeepsOriginalsUntouched()
    {
        var space = Space(); var group = Guid.NewGuid();
        var first = Tab(space, "first", TabPlacement.Saved, group);
        var second = Tab(space, "second", TabPlacement.Saved, group);
        var source = Tab(space, "source", TabPlacement.Pinned);
        var originals = space.Tabs.Select(t => t.Capture()).ToArray();
        var result = space.JoinSplit(source.Id, first.Id, 1, new SystemIdSource(), Now.AddMinutes(1));
        Assert.Equal(originals, space.Tabs.Take(3).Select(t => t.Capture()));
        Assert.Equal(3, result.Copies.Count);
        var members = space.SplitMembers(result.SelectedTab);
        Assert.Equal(new[] { "first", "source", "second" }, members.Select(t => t.Title));
        Assert.All(members, t => {
            Assert.Equal(TabPlacement.Current, t.Placement); Assert.Null(t.SavedUrl); Assert.Null(t.FolderId);
            Assert.Equal(TabPhase.Dormant, t.Phase); Assert.Null(t.PageId); Assert.False(t.KeepsPageLoaded);
            Assert.Equal("Custom " + t.Title, t.CustomTitle); Assert.NotEqual(group, t.SplitGroupId);
        });
        Assert.Single(members.Select(t => t.SplitGroupId).Distinct());
    }
    [Fact]
    public void ReorderingDurableMembersKeepsTheirIdentityAndPlacement()
    {
        var space = Space(); var group = Guid.NewGuid();
        var first = Tab(space, "first", TabPlacement.Saved, group); var second = Tab(space, "second", TabPlacement.Saved, group);
        var result = space.JoinSplit(second.Id, first.Id, 0, new SystemIdSource(), Now);
        Assert.Empty(result.Copies); Assert.Equal(new[] { second.Id, first.Id }, space.Tabs.Select(t => t.Id));
        Assert.All(space.Tabs, t => { Assert.Equal(TabPlacement.Saved, t.Placement); Assert.Equal(group, t.SplitGroupId); });
    }
    [Fact]
    public void LeavingMiddleOfRunKeepsSurvivorsContiguousAndExplicitMutationDissolvesSingleton()
    {
        var space = Space(); var group = Guid.NewGuid();
        var first = Tab(space, "first", split: group); var second = Tab(space, "second", split: group);
        var third = Tab(space, "third", split: group); var tail = Tab(space, "tail");
        space.LeaveSplit(second.Id, Now);
        Assert.Equal(new[] { first.Id, third.Id, second.Id, tail.Id }, space.Tabs.Select(t => t.Id));
        Assert.Equal(group, first.SplitGroupId); Assert.Equal(group, third.SplitGroupId); Assert.Null(second.SplitGroupId);
        space.LeaveSplit(first.Id, Now.AddMinutes(1));
        Assert.Null(first.SplitGroupId); Assert.Null(third.SplitGroupId);
        Assert.Equal(Now.AddMinutes(1), third.PositionModifiedAt);
    }
    [Fact]
    public void FullSplitRefusesWithoutCopyingOrChangingAnyTab()
    {
        var space = Space(); var group = Guid.NewGuid();
        var first = Tab(space, "first", TabPlacement.Saved, group);
        for (int i = 0; i < 3; i++) Tab(space, "member" + i, TabPlacement.Saved, group);
        var source = Tab(space, "source"); var before = space.Tabs.Select(t => t.Capture()).ToArray();
        Assert.Equal("split_limit", Assert.Throws<BrowserRuleException>(() =>
            space.JoinSplit(source.Id, first.Id, null, new SystemIdSource(), Now)).Code);
        Assert.Equal(before, space.Tabs.Select(t => t.Capture()));
    }
    [Fact]
    public void RestoreRepairsMalformedRunsWithoutErasingSingletonMembershipOrPositionClock()
    {
        var space = Space(); var group = Guid.NewGuid(); var single = Tab(space, "single", split: group);
        Tab(space, "separator"); var repeated = Tab(space, "repeated", split: group);
        var pinned = Tab(space, "pinned", TabPlacement.Pinned, Guid.NewGuid());
        var restored = BrowserSpace.Restore(space.Capture(null));
        Assert.Equal(group, restored.Tab(single.Id).SplitGroupId);
        Assert.Null(restored.Tab(repeated.Id).SplitGroupId); Assert.Null(restored.Tab(pinned.Id).SplitGroupId);
        Assert.All(restored.Tabs, t => Assert.Null(t.PositionModifiedAt));
        var again = BrowserSpace.Restore(restored.Capture(null));
        Assert.Equal(restored.Tabs.Select(t => t.Capture()), again.Tabs.Select(t => t.Capture()));
    }
}
