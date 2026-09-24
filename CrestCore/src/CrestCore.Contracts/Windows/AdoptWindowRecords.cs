namespace CrestCore.Contracts;

/// Carries the window records an installed release kept in its defaults into
/// the device store, once: what each window showed, the Spaces it had seen and
/// its split columns, folded with the selection that release kept in the
/// session. The store is written before the intent returns; a device that has
/// adopted them before publishes nothing. `Records` are the raw bytes, or
/// null when the release kept none.
public sealed record AdoptWindowRecords(byte[]? Records) : WindowIntent;
