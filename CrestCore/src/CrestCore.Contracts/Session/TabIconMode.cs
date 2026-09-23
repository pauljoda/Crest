namespace CrestCore.Contracts;

/// <summary>Which source fills a tab's icon slot: the page's own favicon as it
/// changes, a favicon pulled once and kept, or a chosen emoji.</summary>
public enum TabIconMode { Automatic, Pulled, Emoji }
