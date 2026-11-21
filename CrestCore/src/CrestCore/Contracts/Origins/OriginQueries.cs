namespace CrestCore.Contracts;

/// Whether Crest takes the address.
public sealed record ExternalAddressVerdict(bool Accepted);

/// Whether an address is the person's own development work.
public sealed record DevelopmentAddressVerdict(bool IsLocal);

/// Who owns the navigation.
public sealed record SchemeHandled(ExternalSchemeDisposition Disposition);
