namespace CrestCore.Domain;

/// What an accepted report does to its session: retire the document for good,
/// withdraw its card while keeping its identity, or publish it.
public enum MediaSessionDisposition { Retire, Clear, Publish }
