namespace CrestCore.Contracts;

/// Marks a record whose constructor normalizes its fields, so two spellings of
/// one value are equal: `SiteOrigin` lowercases its scheme and host and fills a
/// web scheme's default port. Every stored value is already normalized, so
/// equality and hashing over the fields are correct, and Swift receives the
/// struct as `Hashable`.
///
/// Swift's struct has no memberwise initializer. The codec makes it through a
/// labeled wire initializer, `init(normalized …)`, from values the core wrote
/// after normalizing them, and nothing else may call it; the generator refuses
/// a Swift source that does. The platform writes the initializer with the
/// natural labels, which normalizes the same way the constructor does.
///
/// It changes nothing on the wire: the schema fingerprint does not name it.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class NormalizedOnConstructionAttribute : Attribute;
