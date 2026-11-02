using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Whether a notification without a live page may appear for a profile.
/// Native engines verify an extension's notification permission; the core
/// still requires an accessible, non-private Space of the profile, of a group
/// the one used last. Web origins additionally require that Space's
/// notification grant.
public sealed record ProfileNotificationDisplayCheck(Guid ProfileId, SiteOrigin Origin, ProfileNotificationSource Source)
    : Query<NotificationDisplayVerdict> {
    #region Actions - Answering

    internal override NotificationDisplayVerdict Answer(CrestApp app) {
        if (app.Device.SpaceOf(ProfileId) is not { } space || app.Device.IsPrivate(space)) return new(false);
        return Source == ProfileNotificationSource.Extension
            ? new(Origin.Scheme == UrlScheme.ChromeExtension.Name && Origin.Host.Length > 0)
            : app.Query(new NotificationDisplayCheck(space, Origin));
    }

    #endregion
}
