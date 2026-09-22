namespace CrestCore.Domain;

/// What finishing setup does.
public enum OnboardingCompletion {
    /// The workspace setup belonged to is gone; nothing is committed.
    SourceChanged,

    /// Commit the setup and retire the launch gate without a guide.
    Complete,

    /// Commit the setup, then open the Getting Started guide in the first Space.
    OpenGuide
}
