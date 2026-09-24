namespace CrestCore.Contracts;

/// <summary>A source language's chosen destination. Disabling keeps the destination.</summary>
public readonly record struct TranslationRule(string TargetId, bool IsEnabled);
