namespace CrestCore.Contracts;

#region Queries

/// What a card number says: its `Network`, its last four digits, and whether
/// it is complete, of a length its network issues and passing the Luhn
/// check. A number that holds anything but digits, spaces and dashes, or more
/// digits than a card number has, is `CardNetwork.Unknown`, has no last four
/// digits and is not complete.
public sealed record CardSummary(CardNetwork Network, string LastFour, bool IsValid);

/// The section of a form that holds the focused field, or null when that
/// field is in none worth filling.
public sealed record AutofillSectionAnswer(AutofillSection? Section);

#endregion

#region Rejections

/// An address or card a question carries breaks its limits: a text longer
/// than its record keeps, too many street lines, a country that is not a
/// two-letter code, or a card number, expiry or security code that is not
/// one.
public sealed record InvalidAutofillRecord() : Rejection;

#endregion
