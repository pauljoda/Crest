namespace CrestCore.Contracts;

/// The export `ExportId` asked for: its document, or why there is none.
public sealed record PageExported(Guid PageId, Guid ExportId, byte[]? Document, PageExportFailure? Failure) : EnginePresentation;
