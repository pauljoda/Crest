using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - App preferences

    /// The app-wide behavior preferences belong to the persistent workspace and
    /// stay on this device: sync neither uploads nor replaces them, and no
    /// edit of them reaches the journal.
    internal void RequirePreferenceOwner() {
        if (!workspaceKind.KeepsAppPreferences) throw new Rejected(new PersistentWorkspaceRequired(workspaceId));
    }

    /// `basis` with `preferences`, keeping its record when they are equal.
    internal SessionEdit Preferred(SessionState basis, AppPreferences preferences) =>
        new(preferences == basis.AppPreferences ? basis : basis with { AppPreferences = preferences }, Staging: null);

    /// The app's preferences `basis` follows: its own, or, in a workspace
    /// that keeps none, the persistent session's.
    internal AppPreferences Preferences(SessionState basis) =>
        basis.AppPreferences ?? device?.PersistentPreferences() ?? AppPreferences.Default;

    #endregion
}
