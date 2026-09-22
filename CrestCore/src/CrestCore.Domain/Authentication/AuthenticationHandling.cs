namespace CrestCore.Domain;

/// How one authentication challenge is answered.
public enum AuthenticationHandling { PromptForCredentials, PerformDefaultHandling, Cancel }
