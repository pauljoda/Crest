using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests.Session;

/// A Space's icon and its colors are separate choices: a crest worn as the
/// icon changes only the icon, wherever the look then travels, while a
/// template is a full set and replaces both.
public sealed class SpaceIconChoiceTests {
    [Fact]
    public void ACrestWornAsTheIconKeepsTheSpacesOwnColors() {
        var own = OwnLook();

        foreach (var house in SpaceHouse.All) {
            var crowned = house.WearingCrest(own);

            Assert.Equal(SpaceIconStyle.LayeredCrest, crowned.IconStyle);
            Assert.Equal((house.Look.Crest.Backplate, house.Look.Crest.Symbol, house.Name),
                (crowned.Crest.Backplate, crowned.Crest.Symbol, crowned.Crest.StartingPresetId));
            // Nothing but the icon changed: the colors, the gradients they run
            // on into, the icon's own color, the sidebar and its strengths.
            Assert.Equal(own, crowned with {
                IconStyle = own.IconStyle,
                Crest = own.Crest,
                RenderingVersion = own.RenderingVersion
            });
            // A relaunch reads the icon and the colors back as they were.
            Assert.Equal(crowned, SpaceBranding.Normalized(StoredSessionCodec.DecodeBranding(StoredSessionCodec.Encode(crowned))));
        }
    }

    [Fact]
    public void ATemplateReplacesTheColorsAndTheIconTogether() {
        var own = OwnLook();
        var house = SpaceHouse.Winter;

        var started = house.Applying(own);

        Assert.Equal(house.Look.Colors, started.Colors);
        Assert.Equal(house.Look.ColorGradients, started.ColorGradients);
        Assert.Null(started.SymbolColor);
        Assert.Equal(SpaceIconStyle.LayeredCrest, started.IconStyle);
        Assert.Equal(house.Name, started.Crest.StartingPresetId);
        Assert.False(started.HasCustomAppearance);
        // Wearing the house's own crest over its own colors leaves the template whole.
        Assert.Equal(started, house.WearingCrest(started));
    }

    /// A look the person made before the wells: three colors set by hex
    /// running as one gradient down the sidebar, under a plain symbol in a
    /// color of its own.
    private static SpaceBranding OwnLook() => SpaceBranding.Normalized(SpaceBranding.Legacy(SpaceAccent.Teal, "leaf.fill") with {
        Colors = new([Hex(0x1D2340), Hex(0x5B2A86), Hex(0xF6C85F)]),
        ThemeMode = SpaceThemeMode.Gradient,
        GradientAngle = 120,
        SymbolColor = Hex(0xF6C85F),
        ColorGradients = new([BrandGradient.Plain, new(new([Hex(0xE07A5F)]), Kind: null, Angle: 90)]),
        TextureStrength = 0.3,
        HasCustomAppearance = true
    });

    private static BrandColor Hex(int rgb) => new((rgb >> 16 & 0xFF) / 255.0, (rgb >> 8 & 0xFF) / 255.0, (rgb & 0xFF) / 255.0);
}
