namespace CrestCore.Contracts;

/// The device store holds the window records an installed release kept.
/// `Layouts` are the sidebar values those records also carried, which the
/// platform keeps as its own; the core keeps none of them.
public sealed record WindowRecordsAdopted(IReadOnlyList<WindowLayout> Layouts) : Change;
