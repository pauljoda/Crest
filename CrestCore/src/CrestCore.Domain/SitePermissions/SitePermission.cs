namespace CrestCore.Domain;

/// A capability a site asks for. Declaration order is the order saved choices
/// are listed in within one origin.
public enum SitePermission {
    AutomaticDownloads,
    Camera,
    CameraAndMicrophone,
    ExternalApplications,
    Location,
    Microphone,
    Notifications,
    Popups,
}
