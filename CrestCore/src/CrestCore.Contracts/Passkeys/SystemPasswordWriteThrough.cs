namespace CrestCore.Contracts;

/// Whether this launch can offer saved passwords to the system's Passwords app.
/// `SupportsSystemPasswordSaving` says the operating system has the API that
/// saves one; `IsLaunchIsolated` says this launch keeps away from the person's
/// own stores.
public sealed record SystemPasswordWriteThrough(bool IsMobilePlatform, bool SupportsSystemPasswordSaving,
    bool HasManagedBrowserCapability, bool IsLaunchIsolated) : Query<SystemPasswordWriteThroughSupport>;
