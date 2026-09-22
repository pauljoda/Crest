namespace CrestCore.Domain;

/// A source language's chosen destination. Disabling keeps the destination.
public readonly record struct TranslationRule(string TargetId, bool IsEnabled);
