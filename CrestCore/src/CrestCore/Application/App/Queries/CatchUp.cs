using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a read model that starts after the app missed: the engines and the
/// shortcuts they offer as the core last published them, the search catalog,
/// every page open now, every profile's downloads, and the questions still
/// waiting on the person. A host whose views share one read model, as the
/// Mac's do, never asks. One whose windows each keep their own, as the desktop
/// interface's do, asks once a window's read model has opened its workspace,
/// and applies the answer as a batch: a window that opens late, or whose
/// interface loads again over pages its engine still holds, shows those pages
/// instead of asking for new ones.
public sealed record CatchUp : Query<CaughtUp> {
    #region Actions - Answering

    internal override CaughtUp Answer(CrestApp app) {
        var engines = app.PublishedEngines;
        ShortcutsChanged shortcuts;
        SearchCatalog catalog;
        lock (app.Device.Gate) {
            shortcuts = app.Device.Shortcuts(Engines.OfferedCommands(engines));
            catalog = app.Device.SearchCatalog;
        }
        Change[] pages;
        lock (app.Gate) pages = [.. app.Pages.All.Select(page => (Change)new PageOpened(page.State))];
        return new([
            new EnginesChanged(engines),
            shortcuts,
            SearchCatalogChanged.Of(catalog),
            .. pages,
            .. app.Downloads.Ledger.Items.Select((download, position) => (Change)new DownloadUpdated(download, position)),
            .. app.AskedQuestions.Waiting,
        ]);
    }

    #endregion
}
