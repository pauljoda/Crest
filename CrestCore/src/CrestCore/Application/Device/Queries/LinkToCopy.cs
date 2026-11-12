using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The address Crest copies for a page at `Url`. While this device's link
/// preferences clean copied links, a redirect wrapper's destination stands
/// for it, and that address leaves out what only tracks who followed it, by
/// Crest's own rules and the maintained list the device keeps; otherwise
/// `Url` as it is. Answered without the app's lock, since the first ask after
/// a copy of the list arrives reads it from its file.
public sealed record LinkToCopy(string Url) : Query<string> {
    #region Variables

    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override string Answer(CrestApp app) {
        LinkPreferences preferences;
        lock (app.Device.Gate) preferences = app.Device.Links;
        return preferences.CleansCopiedLinks ? LinkTracking.Cleaned(Url, app.Filters.LinkTrackingFilters()) : Url;
    }

    #endregion
}
