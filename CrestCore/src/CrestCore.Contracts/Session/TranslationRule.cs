namespace CrestCore.Contracts;

/// <summary>A source language's chosen destination. Disabling keeps the destination.</summary>
public sealed record TranslationRule(string SourceLanguage, string TargetId, bool IsEnabled);
