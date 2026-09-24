using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Actions - App preferences

    /// The app-wide behavior preferences belong to the persistent workspace and
    /// stay on this device: sync neither uploads nor replaces them, and no
    /// edit of them reaches the journal.
    private void RequirePreferenceOwner() {
        if (workspaceKind != WorkspaceKind.Persistent) throw new Rejected(new PersistentWorkspaceRequired(workspaceId));
    }

    private SessionEdit SettingPreferences(SessionState basis, SetAppPreferences intent) {
        RequirePreferenceOwner();
        var preferences = intent.Preferences with {
            TranslationRules = AutomaticTranslationRules.Restore(intent.Preferences.TranslationRules).Rules
        };
        return Preferred(basis, preferences);
    }

    private SessionEdit SettingTranslationRule(SessionState basis, SetTranslationRule intent) {
        RequirePreferenceOwner();
        return Preferred(basis, (basis.AppPreferences ?? AppPreferencesPolicy.Default)
            .WithTranslationRule(intent.SourceLanguage, intent.TargetLanguage, intent.IsEnabled));
    }

    /// An import applies only while the session holds no preferences, so a
    /// later launch never imports over a choice.
    private SessionEdit ImportingPreferences(SessionState basis, ImportAppPreferences intent) {
        RequirePreferenceOwner();
        return basis.AppPreferences is not null ? new(basis, Staging: null)
            : Preferred(basis, StoredSessionCodec.ImportAppPreferences(intent.Legacy));
    }

    /// `basis` with `preferences`, keeping its record when they are equal.
    private static SessionEdit Preferred(SessionState basis, AppPreferences preferences) =>
        new(preferences == basis.AppPreferences ? basis : basis with { AppPreferences = preferences }, Staging: null);

    /// How this launch treats the person's data and what its first window
    /// opens, with the startup choice this workspace keeps. Throws `Rejected`
    /// with `PersistentWorkspaceRequired` for any other workspace.
    internal LaunchDecision Plan(LaunchPlan query) {
        ArgumentNullException.ThrowIfNull(query);
        lock (Gate) {
            RequirePreferenceOwner();
            return LaunchPolicy.Plan(query.Environment, query.Platform, session.AppPreferences?.Startup, query.HasActiveLaunchGate);
        }
    }

    #endregion
}
