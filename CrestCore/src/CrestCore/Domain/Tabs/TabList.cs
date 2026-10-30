namespace CrestCore.Domain;

/// A Space's tabs in sidebar order, each found by identity without a search.
/// Every change to the order or the membership goes through the list, which
/// keeps its index in step, so an edit over many tabs never scans the Space
/// once per tab. Of tabs that share an identity, the first in order is the one
/// found, as a search of the list would find it.
internal sealed class TabList : IReadOnlyList<BrowserTab> {
    #region Variables

    private readonly List<BrowserTab> tabs = [];
    private readonly Dictionary<Guid, BrowserTab> byId = [];
    /// Whether two tabs ever shared an identity, which only a stored Space can
    /// bring; until then a removed identity is gone for good.
    private bool shared;

    public int Count => tabs.Count;

    public BrowserTab this[int index] => tabs[index];

    #endregion

    #region Actions - Membership

    /// The tab `id` names, or null when the list does not hold it.
    public BrowserTab? Find(Guid id) => byId.GetValueOrDefault(id);

    /// Whether the list holds the tab `id` names.
    public bool Holds(Guid id) => byId.ContainsKey(id);

    public void Insert(int index, BrowserTab tab) {
        Remember(tab);
        tabs.Insert(index, tab);
    }

    public void InsertRange(int index, IEnumerable<BrowserTab> added) {
        var inserted = added.ToList();
        foreach (var tab in inserted) Remember(tab);
        tabs.InsertRange(index, inserted);
    }

    public void AddRange(IEnumerable<BrowserTab> added) => InsertRange(tabs.Count, added);

    /// Removes the tab, and answers whether the list held it.
    public bool Remove(BrowserTab tab) {
        int index = tabs.IndexOf(tab);
        if (index < 0) return false;
        tabs.RemoveAt(index);
        Forget(tab);
        return true;
    }

    /// Removes every tab `match` answers for, and answers how many went.
    public int RemoveAll(Predicate<BrowserTab> match) {
        HashSet<BrowserTab> removed = [.. tabs.Where(tab => match(tab))];
        if (removed.Count == 0) return 0;
        tabs.RemoveAll(removed.Contains);
        foreach (var tab in removed) Forget(tab);
        return removed.Count;
    }

    /// Replaces the list with `ordered`: the same tabs in another order, or
    /// with some added or removed.
    public void Replace(IEnumerable<BrowserTab> ordered) {
        var replaced = ordered.ToList();
        tabs.Clear();
        byId.Clear();
        AddRange(replaced);
    }

    #endregion

    #region Actions - Order

    public int IndexOf(BrowserTab tab) => tabs.IndexOf(tab);

    public int FindIndex(Predicate<BrowserTab> match) => tabs.FindIndex(match);

    public int FindLastIndex(Predicate<BrowserTab> match) => tabs.FindLastIndex(match);

    public List<BrowserTab> GetRange(int index, int count) => tabs.GetRange(index, count);

    public IEnumerator<BrowserTab> GetEnumerator() => tabs.GetEnumerator();

    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();

    #endregion

    #region Mutators

    /// Indexes `tab`, unless an earlier tab already answers for its identity.
    private void Remember(BrowserTab tab) {
        if (!byId.TryAdd(tab.Id, tab)) shared = true;
    }

    /// Drops `tab` from the index, and points its identity at the next tab
    /// that shares it when one remains.
    private void Forget(BrowserTab tab) {
        if (!byId.Remove(tab.Id) || !shared) return;
        if (tabs.Find(other => other.Id == tab.Id) is { } remaining) byId[tab.Id] = remaining;
    }

    #endregion
}
