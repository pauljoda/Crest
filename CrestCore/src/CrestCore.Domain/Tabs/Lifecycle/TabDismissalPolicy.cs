using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What dismissing the selected tab means. Durable tabs keep their record and
/// only give up their page; a current tab closes; the last Start Page has
/// nothing left to close but the window.
public static class TabDismissalPolicy {
    #region Actions - Lifecycle

    public static TabDismissalAction Decide(TabPlacement? placement, bool isStartPage, int tabCount) {
        if (tabCount < 0) throw new BrowserRuleException(BrowserRuleCodes.InvalidTabCount);
        if (placement is null) return TabDismissalAction.CloseWindow;
        if (placement is TabPlacement.Pinned or TabPlacement.Saved) return TabDismissalAction.UnloadPage;
        return isStartPage && tabCount < 2 ? TabDismissalAction.CloseWindow : TabDismissalAction.CloseTab;
    }

    #endregion
}
