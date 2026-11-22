using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// How an address is escaped before a URL parser reads it: only what its
/// path, query or fragment cannot hold, never an escape the page spelled, so
/// a saved, restored, imported or agent-loaded address reaches the site with
/// the query the page asked for. The Apple platforms read addresses this way.
public sealed partial class BrowserContractsTests {
    [Theory]
    // What an engine leaves raw is escaped where it stands, and the page's
    // escapes stay as they are.
    [InlineData("https://example.com/search.php?s={%22com%22:{%22resultType%22:[1]}}",
        "https://example.com/search.php?s=%7B%22com%22:%7B%22resultType%22:%5B1%5D%7D%7D")]
    [InlineData("https://example.com/a b/%41?q=a|b&r[]=1#f{%20}", "https://example.com/a%20b/%41?q=a%7Cb&r%5B%5D=1#f%7B%20%7D")]
    // A `%` that starts no escape is escaped, and text that is not ASCII is
    // escaped as UTF-8.
    [InlineData("https://example.com/a%%41?q=%zz", "https://example.com/a%25%41?q=%25zz")]
    [InlineData("https://example.com/ä?q=😀", "https://example.com/%C3%A4?q=%F0%9F%98%80")]
    // A valid address keeps its spelling, and the scheme and authority are
    // never escaped; an address that is not http or https escapes the same way.
    [InlineData("https://user@Example.COM:8080/a%7bb?q=%22#top", "https://user@Example.COM:8080/a%7bb?q=%22#top")]
    [InlineData("about:blank", "about:blank")]
    [InlineData("data:text/html,<b>", "data:text/html,%3Cb%3E")]
    public void AnAddressEscapesOnlyWhatItCannotHoldAndKeepsItsEscapes(string spelling, string escaped) {
        Assert.Equal(escaped, new WebAddress(spelling).Escaped);
        // Escaping it again changes nothing.
        Assert.Equal(escaped, new WebAddress(escaped).Escaped);
    }

    [Fact]
    public void ASavedAddressIsTheSamePageWhenAnEngineEscapesMoreOfIt() {
        var saved = new WebAddress("https://example.com/search.php?s={%22com%22:[1]}");
        Assert.True(saved.IsSamePage(new WebAddress("https://example.com/search.php?s=%7B%22com%22:%5B1%5D%7D#results")));
        // An escape escaped again is another query.
        Assert.False(saved.IsSamePage(new WebAddress("https://example.com/search.php?s=%7B%2522com%2522:%5B1%5D%7D")));
    }
}
