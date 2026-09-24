namespace CrestCore.Contracts;

/// A session the core was asked to hold, such as a seed a workspace opens
/// from, is one no workspace can hold, for the reason `Flaw` names.
public sealed record InvalidSession(SessionFlaw Flaw) : Rejection;
