using CrestCore.Domain;

namespace CrestCore.Application;

/// The one rule for commands issued from a borrowed workspace. Its tabs,
/// folders, history, archive and splits are local; a Space's identity,
/// appearance and profile settings belong to the Space it borrows from, so
/// those commands go to the source authority; Space creation, removal,
/// ordering and imports have no meaning in a borrowed workspace.
internal static class BorrowedCommandRouting {
    #region Actions - Routing

    public static BorrowedCommandRoute Route(SessionOperation operation, bool borrowed) => !borrowed ? BorrowedCommandRoute.Local
        : operation switch {
            SessionOperation.SpaceAccess
                or SessionOperation.SpaceBranding
                or SessionOperation.SpaceBrowsingPreferences
                or SessionOperation.SpaceCredentialPreferences
                or SessionOperation.SpaceDefault
                or SessionOperation.SpaceIdentity
                or SessionOperation.SpaceSavedExpansion
                or SessionOperation.SpaceSearchProviderRemove
                or SessionOperation.SpaceSearchProviderUpsert => BorrowedCommandRoute.Source,
            SessionOperation.SpaceCreate
                or SessionOperation.SpaceDeletionBegin
                or SessionOperation.SpaceRemove
                or SessionOperation.SpaceReorder
                or SessionOperation.SpaceResetPrivate
                or SessionOperation.UnknownSpace
                or SessionOperation.WorkspaceImport => BorrowedCommandRoute.Rejected,
            _ => BorrowedCommandRoute.Local
        };

    /// A borrowed authority applies only local commands; the rejection names
    /// whether the source owns the command or nobody may apply it here.
    public static void RequireLocal(SessionOperation operation, bool borrowed) {
        switch (Route(operation, borrowed)) {
            case BorrowedCommandRoute.Source: throw new BrowserRuleException(BrowserRuleCodes.BorrowedProfileRequiresOwner);
            case BorrowedCommandRoute.Rejected: throw new BrowserRuleException(BrowserRuleCodes.BorrowedProfile);
        }
    }

    #endregion
}
