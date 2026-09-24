namespace CrestCore.Contracts;

/// An intent about which workspaces this device's windows may show: opening
/// one, borrowing a Space into one and closing one. The core gives each
/// workspace its identity and publishes `WorkspaceOpened` with its whole
/// session, which every later change to that session names.
public abstract record WorkspaceIntent : Intent;
