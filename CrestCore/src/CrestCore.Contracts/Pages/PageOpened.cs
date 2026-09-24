namespace CrestCore.Contracts;

/// A page opened, and its engine is creating it.
public sealed record PageOpened(PageState Page) : Change;
