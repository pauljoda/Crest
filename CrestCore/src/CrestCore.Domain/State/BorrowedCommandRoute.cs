namespace CrestCore.Domain;

/// Which authority applies a command issued from a workspace. A borrowed
/// workspace applies its own organization, sends profile settings to the
/// Space it borrows from, and cannot add, remove or reorder Spaces.
public enum BorrowedCommandRoute { Local, Source, Rejected }
