namespace CrestCore.Contracts;

/// Creates the engine's page for a page the core opened, in the profile of the
/// page's Space, hosted by the window `WindowId` names. A private page keeps
/// nothing once it closes. The binding answers with `PageCreated` or
/// `PageCreationFailed`.
public sealed record CreatePage(Guid PageId, Guid ProfileId, bool IsPrivate, Guid WindowId) : EngineCommand;
