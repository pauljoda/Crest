namespace CrestCore.Contracts;

/// What an installed release kept in its defaults, exactly as the host read it:
/// the session without its history or images (`Core`), the whole-graph session
/// the releases before that split wrote (`WholeGraph`), each Space's history
/// beside `Core`, and the sync journal. The core decodes all of it. When `Core`
/// is present it is the installed session and `WholeGraph` is ignored.
public sealed record LegacySession(byte[]? Core, byte[]? WholeGraph, IReadOnlyList<LegacyHistory> History, byte[]? Journal);
