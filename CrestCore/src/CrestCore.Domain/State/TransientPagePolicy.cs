namespace CrestCore.Domain;

public static class TransientPagePolicy {
    public static bool CanAdopt(TransientProfile source, TransientProfile? lease, TransientProfile destination,
        bool sourceAccessible, bool destinationAccessible, bool supportsLiveAdoption) {
        if (!sourceAccessible || !destinationAccessible) throw new BrowserRuleException("transient_space_locked");
        if (lease is { } identity && identity != source) throw new BrowserRuleException("wrong_transient_profile");
        return supportsLiveAdoption && lease == destination;
    }
}
