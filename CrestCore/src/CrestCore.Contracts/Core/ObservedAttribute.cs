namespace CrestCore.Contracts;

/// Marks a record the Apple read model keeps as an object views observe field
/// by field. Swift receives `<Record>Model`, a main-actor observable class with
/// one property per field, built from a value and updated from the next one by
/// assigning only the fields that differ, so a tab's new title notifies the
/// readers of that title and no one else. A record with an `Id` keeps it as the
/// model's fixed identity.
///
/// It changes nothing on the wire: the schema fingerprint does not name it.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class ObservedAttribute : Attribute;
