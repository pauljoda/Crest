namespace CrestCore.Contracts;

/// An intent from the cloud transport about the session the core keeps in its
/// file, which alone syncs. Refused with `NoStoredSession` when the core keeps
/// no file, its file holds no session, or that session is not open yet, which
/// the transport never meets since it starts after `OpenWorkspace`; and with
/// `StoredSessionClosed` once that session closed. Each is saved with its
/// journal before it returns; a save that fails is `SaveFailed` and changes
/// nothing. A locked Space never refuses one: sync converges in the background.
///
/// Records the core cannot take are `InvalidSyncRecords`, and a journal that
/// cannot record the result is `SyncStagingRefused`; either changes nothing.
public abstract record CloudSyncIntent : Intent;
