namespace CrestCore.Contracts;

/// Whether websites in Crest can use the system's passkey providers, from the
/// platform's build, device and authorization facts.
public sealed record PasskeyAccess(bool HasManagedCapability, PasskeyDeviceConfiguration DeviceConfiguration,
    PasskeyAuthorizationState AuthorizationState) : Query<PasskeyAccessVerdict>;
