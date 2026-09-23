namespace CrestCore.Application;

internal enum SessionOperation {
    Unknown,
    UnknownHistory,
    UnknownPreferences,
    UnknownRecords,
    UnknownSpace,
    UnknownTransient,
    ArchiveRestore,
    FolderCollapse,
    FolderColor,
    FolderCreate,
    FolderDelete,
    FolderMove,
    FolderRename,
    FolderSymbol,
    HistoryClear,
    HistoryRemoveRange,
    HistoryRemoveUrl,
    HistoryVisit,
    LaunchPlan,
    PreferencesImport,
    PreferencesSet,
    PreferencesTranslationRule,
    RecordsCleanup,
    RecordsSweep,
    SpaceAccess,
    SpaceBranding,
    SpaceBrowsingPreferences,
    SpaceCreate,
    SpaceCredentialPreferences,
    SpaceDefault,
    SpaceDeletionBegin,
    SpaceIdentity,
    SpaceRemove,
    SpaceReorder,
    SpaceResetPrivate,
    SpaceSavedExpansion,
    SpaceSearchProviderRemove,
    SpaceSearchProviderUpsert,
    SplitDissolve,
    SplitIcon,
    SplitJoin,
    SplitJoinInPlace,
    SplitLeave,
    SplitMove,
    SplitOpenLink,
    SplitReorder,
    SplitTint,
    SplitTitle,
    TabActivate,
    TabArchiveTransient,
    TabCleanup,
    TabClearCurrent,
    TabClose,
    TabCloseDurable,
    TabCopy,
    TabDelete,
    TabFaviconCache,
    TabIcon,
    TabMove,
    TabObserve,
    TabOpen,
    TabPromoteTransient,
    TabRename,
    TabResidency,
    TabRestoreArchive,
    TabSavedLocation,
    TabTransfer,
    TabsBatch,
    TabsFile,
    TransientArchive,
    TransientPromote,
    WorkspaceImport,
}

internal static class SessionOperationCodes {
    #region Actions - Encoding

    public static SessionOperation Parse(string? value) => value switch {
        "archive.restore" => SessionOperation.ArchiveRestore,
        "folder.collapse" => SessionOperation.FolderCollapse,
        "folder.color" => SessionOperation.FolderColor,
        "folder.create" => SessionOperation.FolderCreate,
        "folder.delete" => SessionOperation.FolderDelete,
        "folder.move" => SessionOperation.FolderMove,
        "folder.rename" => SessionOperation.FolderRename,
        "folder.symbol" => SessionOperation.FolderSymbol,
        "history.clear" => SessionOperation.HistoryClear,
        "history.remove_range" => SessionOperation.HistoryRemoveRange,
        "history.remove_url" => SessionOperation.HistoryRemoveUrl,
        "history.visit" => SessionOperation.HistoryVisit,
        "launch.plan" => SessionOperation.LaunchPlan,
        "preferences.import" => SessionOperation.PreferencesImport,
        "preferences.set" => SessionOperation.PreferencesSet,
        "preferences.translation_rule" => SessionOperation.PreferencesTranslationRule,
        "records.cleanup" => SessionOperation.RecordsCleanup,
        "records.sweep" => SessionOperation.RecordsSweep,
        "space.access" => SessionOperation.SpaceAccess,
        "space.branding" => SessionOperation.SpaceBranding,
        "space.browsing_preferences" => SessionOperation.SpaceBrowsingPreferences,
        "space.create" => SessionOperation.SpaceCreate,
        "space.credential_preferences" => SessionOperation.SpaceCredentialPreferences,
        "space.default" => SessionOperation.SpaceDefault,
        "space.deletion.begin" => SessionOperation.SpaceDeletionBegin,
        "space.identity" => SessionOperation.SpaceIdentity,
        "space.remove" => SessionOperation.SpaceRemove,
        "space.reorder" => SessionOperation.SpaceReorder,
        "space.reset_private" => SessionOperation.SpaceResetPrivate,
        "space.saved_expansion" => SessionOperation.SpaceSavedExpansion,
        "space.search_provider.remove" => SessionOperation.SpaceSearchProviderRemove,
        "space.search_provider.upsert" => SessionOperation.SpaceSearchProviderUpsert,
        "split.dissolve" => SessionOperation.SplitDissolve,
        "split.icon" => SessionOperation.SplitIcon,
        "split.join" => SessionOperation.SplitJoin,
        "split.join_in_place" => SessionOperation.SplitJoinInPlace,
        "split.leave" => SessionOperation.SplitLeave,
        "split.move" => SessionOperation.SplitMove,
        "split.open_link" => SessionOperation.SplitOpenLink,
        "split.reorder" => SessionOperation.SplitReorder,
        "split.tint" => SessionOperation.SplitTint,
        "split.title" => SessionOperation.SplitTitle,
        "tab.activate" => SessionOperation.TabActivate,
        "tab.archive_transient" => SessionOperation.TabArchiveTransient,
        "tab.cleanup" => SessionOperation.TabCleanup,
        "tab.clear_current" => SessionOperation.TabClearCurrent,
        "tab.close" => SessionOperation.TabClose,
        "tab.close_durable" => SessionOperation.TabCloseDurable,
        "tab.copy" => SessionOperation.TabCopy,
        "tab.delete" => SessionOperation.TabDelete,
        "tab.favicon.cache" => SessionOperation.TabFaviconCache,
        "tab.icon" => SessionOperation.TabIcon,
        "tab.move" => SessionOperation.TabMove,
        "tab.observe" => SessionOperation.TabObserve,
        "tab.open" => SessionOperation.TabOpen,
        "tab.promote_transient" => SessionOperation.TabPromoteTransient,
        "tab.rename" => SessionOperation.TabRename,
        "tab.residency" => SessionOperation.TabResidency,
        "tab.restore_archive" => SessionOperation.TabRestoreArchive,
        "tab.saved_location" => SessionOperation.TabSavedLocation,
        "tab.transfer" => SessionOperation.TabTransfer,
        "tabs.batch" => SessionOperation.TabsBatch,
        "tabs.file" => SessionOperation.TabsFile,
        "transient.archive" => SessionOperation.TransientArchive,
        "transient.promote" => SessionOperation.TransientPromote,
        "workspace.import" => SessionOperation.WorkspaceImport,
        _ when value?.StartsWith("history.", StringComparison.Ordinal) == true => SessionOperation.UnknownHistory,
        _ when value?.StartsWith("preferences.", StringComparison.Ordinal) == true => SessionOperation.UnknownPreferences,
        _ when value?.StartsWith("records.", StringComparison.Ordinal) == true => SessionOperation.UnknownRecords,
        _ when value?.StartsWith("space.", StringComparison.Ordinal) == true => SessionOperation.UnknownSpace,
        _ when value?.StartsWith("transient.", StringComparison.Ordinal) == true => SessionOperation.UnknownTransient,
        _ => SessionOperation.Unknown
    };

    public static string Name(SessionOperation operation) => operation switch {
        SessionOperation.ArchiveRestore => "archive.restore",
        SessionOperation.FolderCollapse => "folder.collapse",
        SessionOperation.FolderColor => "folder.color",
        SessionOperation.FolderCreate => "folder.create",
        SessionOperation.FolderDelete => "folder.delete",
        SessionOperation.FolderMove => "folder.move",
        SessionOperation.FolderRename => "folder.rename",
        SessionOperation.FolderSymbol => "folder.symbol",
        SessionOperation.HistoryClear => "history.clear",
        SessionOperation.HistoryRemoveRange => "history.remove_range",
        SessionOperation.HistoryRemoveUrl => "history.remove_url",
        SessionOperation.HistoryVisit => "history.visit",
        SessionOperation.LaunchPlan => "launch.plan",
        SessionOperation.PreferencesImport => "preferences.import",
        SessionOperation.PreferencesSet => "preferences.set",
        SessionOperation.PreferencesTranslationRule => "preferences.translation_rule",
        SessionOperation.RecordsCleanup => "records.cleanup",
        SessionOperation.RecordsSweep => "records.sweep",
        SessionOperation.SpaceAccess => "space.access",
        SessionOperation.SpaceBranding => "space.branding",
        SessionOperation.SpaceBrowsingPreferences => "space.browsing_preferences",
        SessionOperation.SpaceCreate => "space.create",
        SessionOperation.SpaceCredentialPreferences => "space.credential_preferences",
        SessionOperation.SpaceDefault => "space.default",
        SessionOperation.SpaceDeletionBegin => "space.deletion.begin",
        SessionOperation.SpaceIdentity => "space.identity",
        SessionOperation.SpaceRemove => "space.remove",
        SessionOperation.SpaceReorder => "space.reorder",
        SessionOperation.SpaceResetPrivate => "space.reset_private",
        SessionOperation.SpaceSavedExpansion => "space.saved_expansion",
        SessionOperation.SpaceSearchProviderRemove => "space.search_provider.remove",
        SessionOperation.SpaceSearchProviderUpsert => "space.search_provider.upsert",
        SessionOperation.SplitDissolve => "split.dissolve",
        SessionOperation.SplitIcon => "split.icon",
        SessionOperation.SplitJoin => "split.join",
        SessionOperation.SplitJoinInPlace => "split.join_in_place",
        SessionOperation.SplitLeave => "split.leave",
        SessionOperation.SplitMove => "split.move",
        SessionOperation.SplitOpenLink => "split.open_link",
        SessionOperation.SplitReorder => "split.reorder",
        SessionOperation.SplitTint => "split.tint",
        SessionOperation.SplitTitle => "split.title",
        SessionOperation.TabActivate => "tab.activate",
        SessionOperation.TabArchiveTransient => "tab.archive_transient",
        SessionOperation.TabCleanup => "tab.cleanup",
        SessionOperation.TabClearCurrent => "tab.clear_current",
        SessionOperation.TabClose => "tab.close",
        SessionOperation.TabCloseDurable => "tab.close_durable",
        SessionOperation.TabCopy => "tab.copy",
        SessionOperation.TabDelete => "tab.delete",
        SessionOperation.TabFaviconCache => "tab.favicon.cache",
        SessionOperation.TabIcon => "tab.icon",
        SessionOperation.TabMove => "tab.move",
        SessionOperation.TabObserve => "tab.observe",
        SessionOperation.TabOpen => "tab.open",
        SessionOperation.TabPromoteTransient => "tab.promote_transient",
        SessionOperation.TabRename => "tab.rename",
        SessionOperation.TabResidency => "tab.residency",
        SessionOperation.TabRestoreArchive => "tab.restore_archive",
        SessionOperation.TabSavedLocation => "tab.saved_location",
        SessionOperation.TabTransfer => "tab.transfer",
        SessionOperation.TabsBatch => "tabs.batch",
        SessionOperation.TabsFile => "tabs.file",
        SessionOperation.TransientArchive => "transient.archive",
        SessionOperation.TransientPromote => "transient.promote",
        SessionOperation.WorkspaceImport => "workspace.import",
        _ => throw new ArgumentOutOfRangeException(nameof(operation))
    };

    public static bool IsHistory(SessionOperation operation) => operation is
        SessionOperation.UnknownHistory
        or SessionOperation.HistoryClear
        or SessionOperation.HistoryRemoveRange
        or SessionOperation.HistoryRemoveUrl
        or SessionOperation.HistoryVisit;

    /// App-wide behavior preferences and the launch plan that reads them.
    public static bool IsPreferences(SessionOperation operation) => operation is
        SessionOperation.UnknownPreferences
        or SessionOperation.LaunchPlan
        or SessionOperation.PreferencesImport
        or SessionOperation.PreferencesSet
        or SessionOperation.PreferencesTranslationRule;

    public static bool IsRecord(SessionOperation operation) => operation is
        SessionOperation.UnknownHistory
        or SessionOperation.UnknownRecords
        or SessionOperation.ArchiveRestore
        or SessionOperation.HistoryClear
        or SessionOperation.HistoryRemoveRange
        or SessionOperation.HistoryRemoveUrl
        or SessionOperation.HistoryVisit
        or SessionOperation.RecordsCleanup
        or SessionOperation.RecordsSweep
        or SessionOperation.SplitIcon
        or SessionOperation.SplitTint
        or SessionOperation.SplitTitle;

    public static bool IsSplitMetadata(SessionOperation operation) => operation is
        SessionOperation.SplitTitle
        or SessionOperation.SplitIcon
        or SessionOperation.SplitTint;

    public static bool IsTransient(SessionOperation operation) => operation is
        SessionOperation.UnknownTransient
        or SessionOperation.TransientArchive
        or SessionOperation.TransientPromote;

    public static bool IsSpace(SessionOperation operation) => operation is
        SessionOperation.UnknownSpace
        or SessionOperation.SpaceAccess
        or SessionOperation.SpaceBranding
        or SessionOperation.SpaceBrowsingPreferences
        or SessionOperation.SpaceCreate
        or SessionOperation.SpaceCredentialPreferences
        or SessionOperation.SpaceDefault
        or SessionOperation.SpaceDeletionBegin
        or SessionOperation.SpaceIdentity
        or SessionOperation.SpaceRemove
        or SessionOperation.SpaceReorder
        or SessionOperation.SpaceResetPrivate
        or SessionOperation.SpaceSavedExpansion
        or SessionOperation.SpaceSearchProviderRemove
        or SessionOperation.SpaceSearchProviderUpsert;

    #endregion
}
