namespace CrestCore.Contracts;

/// The name, symbol, accent and look an imported or drafted Space takes. A
/// blank name reads as "Untitled Space" and a blank symbol as the default one;
/// the look is kept within the ranges every device draws.
public sealed record SpaceCustomization(string Name, string Symbol, SpaceAccent Accent, SpaceBranding Branding);
