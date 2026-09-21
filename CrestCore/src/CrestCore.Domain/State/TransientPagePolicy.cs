namespace CrestCore.Domain;

public static class TransientPagePolicy {
    #region Actions - State policy

    public static bool CanAdopt(TransientProfile source, TransientProfile? lease, TransientProfile destination,
        bool sourceAccessible, bool destinationAccessible, bool supportsLiveAdoption) {
        if (!sourceAccessible || !destinationAccessible) throw new BrowserRuleException(BrowserRuleCodes.TransientSpaceLocked);
        if (lease is { } identity && identity != source) throw new BrowserRuleException(BrowserRuleCodes.WrongTransientProfile);
        return supportsLiveAdoption && lease == destination;
    }

    #endregion
}
