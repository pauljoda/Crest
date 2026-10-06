using CrestCore.Application;

namespace CrestCore.Contracts;

/// The Spaces an import of `Profiles` from `Source` brings, read from the
/// files each profile names, without importing anything. A source that names
/// its own Spaces brings them as named there; any other brings one Space for
/// each profile, holding its bookmarks as saved tabs and its open tabs, and
/// named after it. A file that cannot be read is skipped while another brings
/// a Space.
///
/// The platform holds any access the files need while the core reads them,
/// and asks away from the main thread: the core answers without waiting for
/// any other work. Chrome's and Arc's Spaces also offer the extensions their
/// profile has installed from the Chrome Web Store. Refused with the rejection of the last file that could not
/// be read, such as `SessionUnrecognized` or `BookmarksOverLimits`, when
/// nothing could be brought, `SessionHasNoTabs` when no profile names a file,
/// and `SessionOverLimits` when the source brings more Spaces than a
/// workspace keeps.
public sealed record ReadImport(ImportSource Source, IReadOnlyList<ImportProfile> Profiles) : Query<ImportedSpaces> {
    #region Variables

    /// It reads files, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    internal override ImportedSpaces Answer(CrestApp app) {
        var portability = app.Portability;
        return InstalledBrowser.Of(Source).Read(Profiles, portability.Names(Source), portability.Ids, portability.Clock.Now);
    }

    #endregion
}
