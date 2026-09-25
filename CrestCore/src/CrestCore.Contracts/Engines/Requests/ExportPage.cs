namespace CrestCore.Contracts;

/// Exports the page's document as `Format`, a full-page image `Width` points
/// wide or at its own width when `Width` is 0, and answers `PageExported` with
/// `ExportId`. The export ends when the page navigates, closes or loses its
/// renderer.
public sealed record ExportPage(Guid PageId, Guid ExportId, PageExportFormat Format, double Width) : PageRequest<bool>;
