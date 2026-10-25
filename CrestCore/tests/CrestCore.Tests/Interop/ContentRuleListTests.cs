using System.IO.Compression;
using System.Text;

using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed class ContentRuleListTests {
    #region Actions - Snapshots

    [Fact]
    public void SnapshotIdentityChangesWithContentAndRoundTripsThroughGzip() {
        var first = Snapshot("block", "script");
        var second = first.Replace("example", "different", StringComparison.Ordinal);
        var rules = ContentRuleList.FromSnapshot(first);
        Assert.Equal(rules, ContentRuleList.FromArchive(Archive(first)));
        Assert.NotEqual(rules.Identifier, ContentRuleList.FromSnapshot(second).Identifier);
    }

    [Theory]
    [InlineData("redirect", "script")]
    [InlineData("block", "document")]
    [InlineData("scriptlet", "script")]
    public void SnapshotsCannotIntroduceCodeOrBlockTopLevelNavigation(string action, string resource) {
        Assert.Throws<ArgumentException>(() => ContentRuleList.FromSnapshot(Snapshot(action, resource)));
    }

    [Fact]
    public void OversizedCompressedAndExpandedSnapshotsAreRejected() {
        Assert.Throws<ArgumentException>(() => ContentRuleList.FromArchive(new byte[ContentRuleList.MaximumArchiveBytes + 1]));
        var bomb = Archive(new string(' ', 64 * 1024 * 1024 + 1));
        Assert.Throws<InvalidDataException>(() => ContentRuleList.FromArchive(bomb));
    }

    private static string Snapshot(string action, string resource) => $$$"""
        {"version":1,"rules":[{"trigger":{"url-filter":"example","resource-type":["{{{resource}}}"]},"action":{"type":"{{{action}}}"}}]}
        """;

    private static byte[] Archive(string text) {
        using var output = new MemoryStream();
        using (var gzip = new GZipStream(output, CompressionLevel.Fastest, leaveOpen: true)) {
            gzip.Write(Encoding.UTF8.GetBytes(text));
        }
        return output.ToArray();
    }

    #endregion
}
