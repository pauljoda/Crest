using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A saved tab that closing returns to its saved address keeps the name the
/// person gave it, and a record older than saved pages' titles and images
/// wears no image rather than the page it left.
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
}
