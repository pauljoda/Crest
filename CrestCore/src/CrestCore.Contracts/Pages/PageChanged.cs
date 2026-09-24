namespace CrestCore.Contracts;

/// A page moved to another owner, or its engine created, failed or closed it.
public sealed record PageChanged(PageState Page) : Change;
