namespace CrestCore.Contracts;

/// Captures what the page's view shows, all of it or `Area` in view points,
/// scaled to `Width` points wide or at its own size when `Width` is 0, and
/// answers `PageCaptured` with `CaptureId`. False when the page shows nothing
/// to capture.
public sealed record CapturePage(Guid PageId, Guid CaptureId, PageArea? Area, double Width) : PageRequest<bool>;
