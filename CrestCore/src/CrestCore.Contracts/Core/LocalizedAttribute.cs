namespace CrestCore.Contracts;

/// Marks a fixed set's string member as user-facing English text. The
/// generator gives Swift a `LocalizedStringResource` built from the literal, so
/// Xcode extracts it into the string catalog. A string member named after it
/// with `Comment` appended, such as `TitleComment` for `Title`, is the note for
/// translators and reaches Swift only as the resource's comment.
[AttributeUsage(AttributeTargets.Property)]
public sealed class LocalizedAttribute : Attribute;
