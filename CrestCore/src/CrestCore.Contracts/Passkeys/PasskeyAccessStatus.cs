namespace CrestCore.Contracts;

/// Whether websites in Crest can use the system's passkey providers.
public enum PasskeyAccessStatus { ManagedCapabilityRequired, DeviceNotConfigured, NotDetermined, Authorized, Denied }
