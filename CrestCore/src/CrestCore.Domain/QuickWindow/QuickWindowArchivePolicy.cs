namespace CrestCore.Domain;

/// How long an inactive Quick Window stays open before it archives itself.
public enum QuickWindowArchivePolicy { After1Hour, After6Hours, After12Hours, After24Hours, Never }
