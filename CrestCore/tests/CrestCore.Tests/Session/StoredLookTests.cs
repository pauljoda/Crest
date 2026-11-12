using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests.Session;

public sealed class StoredLookTests {
    [Fact]
    public void ALookStoredByOneBuildReadsBackInAnother() {
        var answers = new StandaloneAnswers();
        var look = SpaceBranding.Normalized(SpaceHouse.Lion.Look with { FolderColorIntensity = 0.4 });
        var stored = answers.Query(new StoreLook(look)).Text;

        Assert.Equal(look, answers.Query(new RestoreLook(stored)).Look);

        // A build from before a member existed stored no value for it, and one
        // from after may store a member this build doesn't know.
        var older = (JsonObject)JsonNode.Parse(stored)!;
        older.Remove("folderColorIntensity");
        older["memberFromALaterBuild"] = "kept elsewhere";
        var restored = answers.Query(new RestoreLook(older.ToJsonString())).Look;

        Assert.NotNull(restored);
        Assert.Equal(look with { FolderColorIntensity = 0 }, restored);
        Assert.Null(answers.Query(new RestoreLook("not a look")).Look);
        Assert.Null(answers.Query(new RestoreLook("""{"keepsControlsReadable":"yes"}""")).Look);
    }
}
