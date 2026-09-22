namespace CrestCore.Domain;

/// What a page's `Notification.requestPermission()` call leads to.
public enum HostedNotificationRequestAction { RespondDefault, RespondDenied, ResolveSystemAuthorization, PromptForSitePermission }
