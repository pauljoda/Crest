using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A person in window `WindowId` picked `Row` after typing `Text`. The
/// palette of the Space the window shows, or of `SpaceId` when the palette
/// spoke for it, remembers the address as typed and, when the person lets it
/// learn, the pick for that text. A private window, or a Space the persistent
/// session does not hold, remembers nothing. In any window, the page the row
/// just started loading falls back to http when https can't reach it, when
/// the row opens the https address Crest chose for a site `Text` named without
/// a scheme, never one the Space holds.
public sealed record RecordPaletteChoice(Guid WindowId, string Text, PaletteRow Row, Guid? SpaceId = null) : PaletteIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        if (Row.Kind == PaletteRowKind.OpenAddress && Row.HttpFallback is { } http && AddressResolution.Schemeless(Text) is { } typed
            && typed.Url == Row.Address && typed.HttpFallback == http && Uri.TryCreate(typed.Url, UriKind.Absolute, out var chosen))
            turn.Pages.All.Where(page => page.WindowId == WindowId && page.IsHeadingTo(chosen))
                .MaxBy(page => page.LoadedAt)?.FallBackToHttp(typed);
        device.RecordPaletteChoice(WindowId, SpaceId, Text, Row, turn.Now);
    }

    #endregion
}
