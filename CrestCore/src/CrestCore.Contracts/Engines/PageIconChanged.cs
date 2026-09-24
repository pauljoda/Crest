namespace CrestCore.Contracts;

/// The engine found an icon for the document a page shows at `Url`, or the
/// color the page's theme puts behind it changed. The binding keeps the
/// image; once the document is recorded, the core has the page's tab wear it
/// when the tab's icon follows its page.
public sealed record PageIconChanged(Guid PageId, string Url, TabIconAccent? Accent) : EngineEvent;
