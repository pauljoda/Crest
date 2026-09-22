namespace CrestCore.Domain;

/// Whether Crest may offer a saved password to the system's Passwords app.
public enum SystemPasswordWriteThroughAvailability {
    Available,
    UnsupportedPlatform,
    IsolatedLaunch,
    SystemVersionRequired,
    ManagedBrowserCapabilityRequired
}
