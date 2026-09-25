namespace CrestCore.Contracts;

/// The capture `CaptureId` asked for, as a PNG, or nothing when the page's
/// view showed nothing to capture.
public sealed record PageCaptured(Guid PageId, Guid CaptureId, byte[]? Png) : EnginePresentation;
