using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether the person's own filters hide elements on the site `PageUrl` shows,
/// so the page can offer to show them again.
public sealed record PageBlocksElements(string PageUrl) : Query<bool> {
    #region Actions - Answering

    internal override bool Answer(CrestApp app) =>
        ElementRule.HostOf(PageUrl) is { } host && app.Device.HoldsCustomFilter(line => ElementRule.Hides(line, host));

    #endregion
}
