namespace CrestCore.Contracts;

/// Carries the site permission choices an installed release kept in its
/// defaults into the device store, once, and publishes every Space's choices.
/// `Records` is the document that release saved under
/// `crest.site-permissions.v1`, or null when it saved none. Entries this build
/// cannot read, repeats of an earlier choice and anything but a persistent
/// answer are left out. The store is written before the intent returns; a
/// device that adopted them before, or keeps no file, adopts nothing and still
/// publishes what it holds.
public sealed record AdoptSitePermissions(byte[]? Records) : SitePermissionIntent;
