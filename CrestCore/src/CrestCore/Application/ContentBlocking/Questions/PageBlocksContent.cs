using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a page blocks ads and trackers in the document at `Url` it is about
/// to show: the device blocks at a level that blocks, and blocking is not off
/// for the site. A page the core does not host on that engine blocks nothing.
public sealed record PageBlocksContent(Guid PageId, string Url) : EngineQuestion<bool> {
    #region Actions - Answering

    internal override bool Answer(CrestApp app, Engine engine) =>
        app.Pages.Hosted(PageId) is { } page && ReferenceEquals(page.Engine, engine)
            && app.Device.Blocks(page.SpaceId, new WebAddress(Url).Origin);

    #endregion
}
