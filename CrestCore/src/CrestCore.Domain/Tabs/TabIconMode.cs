namespace CrestCore.Domain;

/// Which source fills a tab's icon slot: the page's own favicon as it
/// changes, a favicon pulled once and kept, or a chosen emoji.
public enum TabIconMode { Automatic, Pulled, Emoji }
