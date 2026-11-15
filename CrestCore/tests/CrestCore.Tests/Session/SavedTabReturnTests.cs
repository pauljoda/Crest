using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a saved tab shows once closing puts its page away: the saved page's
/// title and image when it returns to its saved address from another page,
/// and the page it left otherwise.
public sealed partial class BrowserContractsTests {
    /// A saved tab with no rename, whose icon follows its page, that closes
    /// as `policy` says, showing `url`, and a live page for it.
    private static (CrestApp App, Engine Engine, Guid Page, Guid Workspace, Guid Window, Guid Space, Guid Tab)
        SavedTabClosing(string policy, string url = "https://example.com/") {
        var (document, space, tab) = SavedSession();
        var session = document["session"]!;
        var saved = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        saved["url"] = url;
        saved["symbol"] = TabIconMode.WebSymbol;
        saved.Remove("customTitle");
        saved.Remove("titleModifiedAt");
        saved.Remove("splitGroupID");
        session["appPreferences"] = new JsonObject { ["savedTabClosePolicy"] = policy };
        var (app, engine, _, workspace, window) = PageHost(session);
        var page = Guid.NewGuid();
        app.Send(new OpenPage(page, workspace, space, tab, window));
        app.Report(engine, new PageCreated(page));
        app.Drain();
        return (app, engine, page, workspace, window, space, tab);
    }

    /// Shows the document at `url`, titled `title`, with its own icon and
    /// `accent` behind it, and answers what the image kept for the tab's saved
    /// page became.
    private static IReadOnlyList<TabSavedImageChanged> ShowDocument(CrestApp app, Engine engine, Guid page, string url,
        string title, TabIconAccent? accent = null) {
        var changes = Browse(app, engine, page, url, title);
        app.Report(engine, new PageIconChanged(page, url, accent));
        app.Drain();
        return [.. changes.OfType<TabSavedImageChanged>()];
    }

    [Fact]
    public void ASavedTabClosingBackToItsSavedAddressShowsTheSavedPagesTitleAndImage() {
        var (app, engine, page, workspace, window, space, tab) = SavedTabClosing("returnToSavedURL");
        using var disposal = app;
        var authority = app.Workspace(workspace);
        TabState Tab() => authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);

        // Leaving the saved page keeps its title, favicon address and color, and
        // the platform keeps the image the tab wears for it before the next page's.
        var red = new TabIconAccent(0.9, 0.1, 0.1);
        Assert.Empty(ShowDocument(app, engine, page, "https://example.com/", "Home", red));
        Assert.Equal([new TabSavedImageChanged(workspace, tab, TabSavedImageChange.Keep, "https://example.com/")],
            ShowDocument(app, engine, page, "https://example.com/away", "Away page", new TabIconAccent(0.1, 0.2, 0.9)));
        Assert.Equal(("Away page", "https://example.com/away"), (Tab().Title, Tab().FaviconUrl));
        Assert.Equal(("Home", "https://example.com/"), (Tab().SavedTitle, Tab().SavedFaviconUrl));
        // Moving on from there keeps nothing more.
        Assert.Empty(ShowDocument(app, engine, page, "https://example.com/further", "Further page"));

        // Closing returns it there, showing that page's title, image and color
        // before the page loads again.
        var closed = app.Send(new CloseTab(workspace, window, space, tab));
        Assert.Equal(("https://example.com/", "Home", "https://example.com/", red),
            (Tab().Url, Tab().DisplayTitle, Tab().FaviconUrl, Tab().IconAccent));
        Assert.Equal([new TabSavedImageChanged(workspace, tab, TabSavedImageChange.Restore, "https://example.com/")],
            closed.OfType<TabSavedImageChanged>());
    }

    [Fact]
    public void ASavedTabsNameStaysAndAnOlderRecordShowsNoImageWhenClosingReturnsThem() {
        // A name the person gave the tab stays across the return.
        var (app, engine, page, workspace, window, space, tab) = SavedTabClosing("returnToSavedURL");
        using (app) {
            var authority = app.Workspace(workspace);
            app.Send(new RenameTab(workspace, space, tab, "Mine"));
            ShowDocument(app, engine, page, "https://example.com/", "Home");
            ShowDocument(app, engine, page, "https://example.com/away", "Away page");
            app.Send(new CloseTab(workspace, window, space, tab));
            var returned = authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);
            Assert.Equal(("https://example.com/", "Mine", "Home"), (returned.Url, returned.DisplayTitle, returned.Title));
        }

        // A tab written away from its saved page before saved pages kept a
        // title and image keeps its title, and wears no image rather than the
        // page it left.
        (app, _, _, workspace, window, space, tab) = SavedTabClosing("returnToSavedURL", "https://example.com/article#one");
        using (app) {
            var authority = app.Workspace(workspace);
            var closed = app.Send(new CloseTab(workspace, window, space, tab));
            var returned = authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);
            Assert.Equal(("https://example.com/", "Observed page", null), (returned.Url, returned.DisplayTitle, returned.FaviconUrl));
            Assert.Equal([new TabSavedImageChanged(workspace, tab, TabSavedImageChange.Restore, null)],
                closed.OfType<TabSavedImageChanged>());
        }
    }

    [Fact]
    public void ReplacingASavedAddressKeepsThePageItShowsAsTheSavedPage() {
        var (app, engine, page, workspace, window, space, tab) = SavedTabClosing("returnToSavedURL");
        using var disposal = app;
        var authority = app.Workspace(workspace);
        TabState Tab() => authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);

        ShowDocument(app, engine, page, "https://example.com/", "Home");
        ShowDocument(app, engine, page, "https://example.com/away", "Away page");
        var replaced = app.Send(new ReplaceSavedAddress(workspace, space, tab));
        Assert.Equal(("https://example.com/away", "Away page", "https://example.com/away"),
            (Tab().SavedUrl, Tab().SavedTitle, Tab().SavedFaviconUrl));
        Assert.Equal([new TabSavedImageChanged(workspace, tab, TabSavedImageChange.Keep, "https://example.com/away")],
            replaced.OfType<TabSavedImageChanged>());

        // Closing at the new saved address changes nothing it shows.
        var closed = app.Send(new CloseTab(workspace, window, space, tab));
        Assert.Equal(("Away page", "https://example.com/away"), (Tab().DisplayTitle, Tab().FaviconUrl));
        Assert.Empty(closed.OfType<TabSavedImageChanged>());
    }

    [Fact]
    public void AnIconFromThePageBeforeIsNeverKeptAsTheSavedPages() {
        var (app, engine, page, workspace, window, space, tab) = SavedTabClosing("returnToSavedURL");
        using var disposal = app;
        var authority = app.Workspace(workspace);
        TabState Tab() => authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);
        ShowDocument(app, engine, page, "https://example.com/", "Home");
        ShowDocument(app, engine, page, "https://example.com/away", "Away page");

        // Back at the saved page with no title of its own, the tab shows the
        // title kept for it rather than the away page's.
        Browse(app, engine, page, "https://example.com/", "");
        Assert.Equal("Home", Tab().Title);

        // Back at the saved page before its icon arrives, the tab still wears
        // the away page's; leaving again keeps the saved page's title but not
        // that icon, and the image kept for the saved page stays.
        Browse(app, engine, page, "https://example.com/away", "Away page");
        Browse(app, engine, page, "https://example.com/", "Home again");
        Assert.Empty(Browse(app, engine, page, "https://example.com/later", "Later page").OfType<TabSavedImageChanged>());
        Assert.Equal(("Home again", "https://example.com/"), (Tab().SavedTitle, Tab().SavedFaviconUrl));

        // Replacing the saved address before the shown page's icon arrives
        // keeps no icon for it rather than the page before's.
        var replaced = app.Send(new ReplaceSavedAddress(workspace, space, tab));
        Assert.Equal(("https://example.com/later", "Later page", null),
            (Tab().SavedUrl, Tab().SavedTitle, Tab().SavedFaviconUrl));
        Assert.Equal([new TabSavedImageChanged(workspace, tab, TabSavedImageChange.Keep, null)],
            replaced.OfType<TabSavedImageChanged>());
    }

    [Fact]
    public void ASavedTabClosingWhereItWasKeepsThePageItLeft() {
        var (app, engine, page, workspace, window, space, tab) = SavedTabClosing("resumeLastLocation");
        using var disposal = app;
        var authority = app.Workspace(workspace);

        ShowDocument(app, engine, page, "https://example.com/", "Home");
        ShowDocument(app, engine, page, "https://example.com/away", "Away page");
        var closed = app.Send(new CloseTab(workspace, window, space, tab));
        var kept = authority.Current.Spaces[0].Tabs.Single(candidate => candidate.Id == tab);
        Assert.Equal(("https://example.com/away", "Away page", "https://example.com/away"), (kept.Url, kept.DisplayTitle, kept.FaviconUrl));
        Assert.Empty(closed.OfType<TabSavedImageChanged>());
    }
}
