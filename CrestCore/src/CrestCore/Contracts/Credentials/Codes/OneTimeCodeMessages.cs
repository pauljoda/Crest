namespace CrestCore.Contracts;

#region Answers

/// What text sets up: the setup it reads as, or why it reads as none.
[HoldsSecrets]
public sealed record ParsedCodeSetup(OneTimeCodeSetup? Setup, CodeSetupRefusal? Refusal);

/// What to enter in each field a one-time code goes into, in the fields' order.
[HoldsSecrets]
public sealed record OneTimeCodeFill(IReadOnlyList<OneTimeCodeEntry> Entries);

#endregion

#region Rejections

/// A setup makes no codes, for the reason `Refusal` names.
public sealed record InvalidCodeSetup(CodeSetupRefusal Refusal) : Rejection;

/// A code's time is not finite, or is before 1970 or after the year 9999.
public sealed record InvalidCodeTime() : Rejection;

/// A code of `Length` characters doesn't fit `Fields` fields: one field takes
/// a whole code, and split fields one character each.
public sealed record MismatchedCodeLength(int Fields, int Length) : Rejection;

#endregion
