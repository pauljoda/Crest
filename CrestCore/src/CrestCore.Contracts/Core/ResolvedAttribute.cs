namespace CrestCore.Contracts;

/// Marks a record's computed property as a value the core resolves from the
/// record's fields and publishes with it, so no platform works out the rule
/// again: a tab arrives with its icon mode already decided.
///
/// It crosses the wire after the record's fields, and Swift receives it as a
/// field of its own. The core never reads it back, since it computes it, and
/// no stored or synced format holds it, since the hand-written codecs write
/// only the fields.
[AttributeUsage(AttributeTargets.Property, Inherited = false)]
public sealed class ResolvedAttribute : Attribute;
