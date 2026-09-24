namespace CrestCore.Contracts;

/// Marks a fixed set that also has members made at runtime, such as a
/// Space's custom search engines beside the built-in ones. Its static
/// instances are still the members `All` lists and `Named` finds; a runtime
/// member is made by the set's own factory and is told apart by its `Name`.
///
/// A runtime member has no index in `All`, so an open set never crosses the
/// wire. Swift receives a struct with a memberwise initializer, so a platform
/// can describe a runtime member it keeps, and two values are equal when their
/// names are.
[AttributeUsage(AttributeTargets.Class, Inherited = false)]
public sealed class OpenSetAttribute : Attribute;
