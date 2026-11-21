using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests.Session;

public sealed class StoredBrandingTests {
    [Fact]
    public void ALookStoredByOneBuildReadsBackInAnother() {
        var look = SpaceBranding.Normalized(SpaceHouse.Lion.Look with { FolderColorIntensity = 0.4 });
        var stored = Store(look);

        Assert.Equal(look, Restore(stored));

        // A build from before a member existed stored no value for it, and one
        // from after may store a member this build doesn't know.
        var older = (JsonObject)JsonNode.Parse(stored)!;
        older.Remove("folderColorIntensity");
        older["memberFromALaterBuild"] = "kept elsewhere";
        var restored = Restore(older.ToJsonString());

        Assert.NotNull(restored);
        Assert.Equal(look with { FolderColorIntensity = 0 }, restored);
        Assert.Null(Restore("not a look"));
        Assert.Null(Restore("""{"keepsControlsReadable":"yes"}"""));
    }

    [Fact]
    public void ATextureReadsAlikeInBuildsWithAndWithoutItsStrength() {
        var look = SpaceBranding.Normalized(SpaceHouse.Lion.Look with { TextureStrength = 0.4 });
        var stored = (JsonObject)JsonNode.Parse(Store(look))!;
        double? Texture(Action<JsonObject> change) {
            var copy = (JsonObject)stored.DeepClone();
            change(copy);
            return Restore(copy.ToJsonString())?.TextureStrength;
        }

        // A build that keeps only the switch reads it beside the strength.
        Assert.True(stored["showsTexture"]!.GetValue<bool>());
        Assert.Equal(0.4, Texture(_ => { }));
        // Such a build stores the switch alone, which shows a full texture,
        // and can turn it off, or on over a strength of none.
        Assert.Equal(1, Texture(copy => copy.Remove("textureStrength")));
        Assert.Equal(0, Texture(copy => copy["showsTexture"] = false));
        Assert.Equal(1, Texture(copy => copy["textureStrength"] = 0));
    }

    /// `look` as the stored session keeps branding.
    private static string Store(SpaceBranding look) => StoredSessionCodec.Encode(look).ToJsonString();

    /// The look `text` stored, read as the stored session reads branding, or
    /// null for text that holds none.
    private static SpaceBranding? Restore(string text) {
        try {
            return JsonNode.Parse(text) is JsonObject stored
                ? SpaceBranding.Normalized(StoredSessionCodec.DecodeBranding(stored))
                : null;
        } catch (Exception error) when (error is JsonException or InvalidOperationException or FormatException) {
            return null;
        }
    }
}
