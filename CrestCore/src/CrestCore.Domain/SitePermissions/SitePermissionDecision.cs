namespace CrestCore.Domain;

/// A person's answer for one capability, origin and Space. Session answers
/// last until the process ends; persistent answers are saved on this device.
public enum SitePermissionDecision { Ask, GrantForSession, DenyForSession, GrantPersistently, DenyPersistently }
