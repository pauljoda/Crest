namespace CrestCore.Contracts;

/// What makes a custom search engine unusable.
public enum SearchEngineFlaw {
    InvalidIdentity,
    EmptyName,
    NameTooLong,
    TemplateTooLong,
    MissingPlaceholder,
    AmbiguousPlaceholder,
    InvalidTemplate,
    RequiresHttps,
    UnsafeHost,
    NonstandardPort,
    CredentialsInTemplate,
    PlaceholderInFragment,
    SecretInTemplate
}
