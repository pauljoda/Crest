using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Reading a password file for an import: its limits, its encoding, the
/// headers each browser and password manager writes, the rows it leaves out
/// or warns about, and what each account means against the passwords the
/// Space keeps.
public sealed class CredentialImportTests {
    private static readonly CrestApp Area = new();
    private static readonly CredentialOrigin Accounts = new("https", "accounts.example", 443);

    private static CredentialImportPlan Preview(string text, params ExistingCredential[] existing) =>
        Area.Query(new CredentialImportPreview(Encoding.UTF8.GetBytes(text), existing));

    private static CredentialFileFlaw Flaw(byte[] document) =>
        Assert.IsType<InvalidCredentialFile>(Assert.Throws<Rejected>(() =>
            Area.Query(new CredentialImportPreview(document, []))).Rejection).Flaw;

    private static CredentialFileFlaw Flaw(string text) => Flaw(Encoding.UTF8.GetBytes(text));

    private static ExistingCredential Saved(string username, string password, double updatedAt = 1_000, double? lastUsedAt = null,
        bool isWebForm = true, CredentialOrigin? origin = null, string? note = null, string? link = null) =>
        new(Guid.NewGuid(), origin ?? Accounts, username, isWebForm, updatedAt, lastUsedAt, password, note, link);

    private static IEnumerable<CredentialRowRejection> Rows(int first, CredentialRowFlaw flaw, int count = 1) =>
        Enumerable.Range(first, count).Select(row => new CredentialRowRejection(row, flaw));

    [Fact]
    public void EachBrowsersHeadersNameTheColumnsAndTheFormat() {
        var browser = Preview("name,url,username,password,note\nWork,https://accounts.example/login,ada,secret,\n");
        Assert.Equal((CredentialFileFormat.Browser, "Work"), (browser.Format, browser.Groups[0].Candidates[0].DisplayName));
        Assert.Equal(CredentialFileFormat.Firefox, Preview(
            "\"url\",\"username\",\"password\",\"httpRealm\",\"formActionOrigin\",\"guid\"\n\"https://accounts.example\",\"ada\",\"s\",,,\"{1}\"\n")
            .Format);
        Assert.Equal(CredentialFileFormat.Safari, Preview("Title,URL,Username,Password,Notes,OTPAuth\nWork,https://accounts.example,ada,s,,\n")
            .Format);
        var bitwarden = Preview(
            "folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp\n,,login,Work,,,0,https://accounts.example,ada,s,\n");
        Assert.Equal((CredentialFileFormat.Bitwarden, "ada"), (bitwarden.Format, bitwarden.Groups[0].Username));

        Assert.Equal(CredentialFileFlaw.SeveralSiteColumns, Flaw("url,origin,username,password\nhttps://one.example,https://two.example,u,s"));
        Assert.Equal(CredentialFileFlaw.SeveralPasswordColumns, Flaw("url,username,password,pass\nhttps://one.example,u,s,t"));
        Assert.Equal(CredentialFileFlaw.NoPasswordColumn, Flaw("url,username\nhttps://one.example,user"));
        Assert.Equal(CredentialFileFlaw.NoSiteColumn, Flaw("username,password\nuser,secret"));
        Assert.Equal(CredentialFileFlaw.Malformed, Flaw("url,username,password\n\"https://one.example,user,secret"));
        Assert.Equal(CredentialFileFlaw.Malformed, Flaw("url,username,password\nhttps://one.example,us\"er,secret"));
    }

    [Fact]
    public void BrokenRowsAreLeftOutAndPlainHttpRowsWarnWithoutLosingValidRows() {
        var plan = Preview("""
            url,username,password
            https://valid.example/path,,valid-secret

            http://insecure.example,user,insecure-secret
            not a url,user,bad-secret
            https://empty.example,user,
            https://wide.example,user,secret,extra
            accounts.example,bare,secret
            """);
        // Blank rows are skipped before rows are numbered.
        Assert.Equal([2, 3, 7], plan.Groups.SelectMany(group => group.Candidates).Select(candidate => candidate.RowNumber).Order());
        Assert.Equal([new(4, CredentialRowFlaw.InvalidOrigin), new(5, CredentialRowFlaw.EmptyPassword), new(6, CredentialRowFlaw.MalformedRow)],
            plan.Rejections);
        Assert.Equal([new CredentialRowWarning(3, CredentialRowCaution.InsecureOrigin)], plan.Warnings);
        // A site without a scheme is HTTPS; an origin keeps a port only when it is not the default.
        Assert.Contains(plan.Groups, group => group.Origin == new CredentialOrigin("https", "accounts.example", 443));
        Assert.Equal(new CredentialOrigin("http", "xn--bcher-kva.example", 8080),
            Preview("url,username,password\nHTTP://Bücher.Example:08080/login,u,s").Groups[0].Origin);
    }

    [Fact]
    public void ABracketedHostMustBeAnIPv6AddressWithoutAZoneId() {
        var plan = Preview("""
            url,username,password
            https://[2001:DB8::1]:8443/,u,s
            https://[a b]/,u,s
            https://[a%2Fb]/,u,s
            https://[%5B::1%5D]/,u,s
            https://[1.2.3.4]/,u,s
            https://[v1.x]/,u,s
            https://[:::]/,u,s
            https://[fe80::1%25en0]/,u,s
            https://[fe80::1%41]/,u,s
            """);
        Assert.Equal(new CredentialOrigin("https", "2001:db8::1", 8443), Assert.Single(plan.Groups).Origin);
        // A page never reports a zone ID, so a saved password cannot hold one
        // either, escaped or not.
        Assert.Equal([.. Rows(3, CredentialRowFlaw.NotIPv6Address, count: 6), .. Rows(9, CredentialRowFlaw.ZoneIdentifier, count: 2)],
            plan.Rejections);
        Assert.False(new CredentialOrigin("https", "fe80::1%en0", 443).IsValid);
    }

    [Fact]
    public void AnIPAddressIsSpelledAsAPageReportsItSoThePasswordFillsAndMerges() {
        var saved = Saved("ada", "secret", origin: new("https", "127.0.0.1", 443));
        var plan = Preview("""
            url,username,password
            https://127.1/,ada,secret
            https://0x7f.0.0.1./,bob,secret
            https://[2001:db8:0:0:0:0:0:1]/,ada,secret
            https://[::ffff:1.2.3.4]/,ada,secret
            https://999.1.1.1/,ada,secret
            https://1.2.3.4.5/,ada,secret
            https://08.1.1.1/,ada,secret
            https://[::ffff:1.2.3.04]/,ada,secret
            """, saved);
        Assert.Equal([("127.0.0.1", "ada"), ("127.0.0.1", "bob"), ("2001:db8::1", "ada"), ("::ffff:102:304", "ada")],
            plan.Groups.Select(group => (group.Origin.Host, group.Username)));
        Assert.Equal(saved.Id, plan.Groups[0].ExistingId);
        // A host ending in a number must be an IPv4 address, and an IPv6 address
        // must spell any IPv4 address it ends in without leading zeros, or no
        // page can have it.
        Assert.Equal([.. Rows(6, CredentialRowFlaw.NotIPv4Address, count: 3), .. Rows(9, CredentialRowFlaw.NotIPv6Address)], plan.Rejections);
        Assert.False(new CredentialOrigin("https", "2001:db8:0:0:0:0:0:1", 443).IsValid);
        Assert.False(new CredentialOrigin("https", "127.1", 443).IsValid);

        // A password an earlier import saved in such a spelling still fills the
        // page, which spells the address canonically; a different address,
        // scheme or port, or a spelling no page reads, does not.
        CredentialOrigin[] earlier = [new("https", "127.1", 443), new("https", "0x7f.0.0.1", 443), new("https", "127.0.0.2", 443),
            new("http", "127.1", 443), new("https", "127.1", 8443), new("https", "08.1.1.1", 443)];
        Assert.Equal([true, true, false, false, false, false],
            Area.Query(new CredentialsFillingPage(new("https", "127.0.0.1", 443), earlier)).Fills);
        Assert.Equal([true, true], Area.Query(new CredentialsFillingPage(new("https", "2001:db8::1", 443),
            [new("https", "2001:db8:0:0:0:0:0:1", 443), new("https", "2001:DB8::1", 443)])).Fills);
        Assert.Equal(new InvalidCredentialOrigin(),
            Assert.Throws<Rejected>(() => Area.Query(new CredentialsFillingPage(new("https", "127.1", 443), earlier))).Rejection);
    }

    [Fact]
    public void AnAccountsRowsGroupAgainstItsMostRecentSavedPassword() {
        var older = Saved("ADA", "old-secret", updatedAt: 3_000);
        var newer = Saved("ada", "current-secret", updatedAt: 1_000, lastUsedAt: 5_000);
        var httpAuth = Saved("grace", "realm-secret", isWebForm: false);
        var plan = Preview("""
            url,username,password
            https://accounts.example,Ada,current-secret
            https://accounts.example,ada,new-secret
            https://accounts.example,ADA,current-secret
            https://accounts.example,grace,grace-secret
            https://zeta.example,bob,bob-secret
            https://accounts.example,alan,alan-secret
            """, older, newer, httpAuth);

        Assert.Equal([("accounts.example", "Ada"), ("accounts.example", "alan"), ("accounts.example", "grace"), ("zeta.example", "bob")],
            plan.Groups.Select(group => (group.Origin.Host, group.Username)));
        var ada = plan.Groups[0];
        Assert.Equal((newer.Id, (int?)null, 1, true), (ada.ExistingId, ada.SuggestedRow, ada.CollapsedDuplicateRowCount, ada.RequiresChoice));
        Assert.Equal([(2, CredentialImportEffect.Matches), (3, CredentialImportEffect.Replaces)],
            ada.Candidates.Select(candidate => (candidate.RowNumber, candidate.Effect)));
        // Only a web form's password stands for an account a file imports.
        var grace = plan.Groups[2];
        Assert.Equal((null, (int?)5, false, CredentialImportEffect.Adds),
            (grace.ExistingId, grace.SuggestedRow, grace.RequiresChoice, grace.Candidates[0].Effect));
        Assert.Equal(6, plan.ValidRowCount);

        // A file that repeats the saved password needs no choice.
        var same = Preview("url,username,password\nhttps://accounts.example,ada,current-secret", newer).Groups[0];
        Assert.Equal((false, CredentialImportEffect.Matches), (same.RequiresChoice, same.Candidates[0].Effect));
    }

    [Fact]
    public void ARowLeftOutNamesItsColumnAndReasonAndThePlanCountsEachReason() {
        var plan = Preview("""
            url,username,password,notes
            ,u,s,
            androidapp://com.example.app,u,s,
            https://accounts.example:99999/,u,s,
            https://accounts.example:0/,u,s,
            https://accounts.example,u,,
            https://accounts.example,u,s,note,extra
            https://[::1%25lo0]/,u,s,
            accounts.example/?next=https://elsewhere.example,v,s,
            """);

        Assert.Equal([new(2, CredentialRowFlaw.NoSite), new(3, CredentialRowFlaw.NotWebAddress), .. Rows(4, CredentialRowFlaw.InvalidPort, count: 2),
            new(6, CredentialRowFlaw.EmptyPassword), new(7, CredentialRowFlaw.MalformedRow), new(8, CredentialRowFlaw.ZoneIdentifier)],
            plan.Rejections);
        Assert.Equal([CredentialFileColumn.Site, CredentialFileColumn.Site, CredentialFileColumn.Site, CredentialFileColumn.Site,
            CredentialFileColumn.Password, null, CredentialFileColumn.Site], plan.Rejections.Select(rejection => rejection.Flaw.Column));
        Assert.Equal([new(CredentialRowFlaw.EmptyPassword, 1), new(CredentialRowFlaw.MalformedRow, 1), new(CredentialRowFlaw.NoSite, 1),
            new(CredentialRowFlaw.NotWebAddress, 1), new(CredentialRowFlaw.ZoneIdentifier, 1), new CredentialRowFlawCount(CredentialRowFlaw.InvalidPort, 2)],
            plan.RejectionCounts);
        // A site without a scheme may still hold one later, in its query.
        Assert.Equal(new CredentialOrigin("https", "accounts.example", 443), Assert.Single(plan.Groups).Origin);
    }

    [Fact]
    public void ANameThatBreaksTheBidiRuleIsLeftOutAsThePlatformsRefuseIt() {
        var plan = Preview("""
            url,username,password
            https://ل.example/,u,s
            https://עברית.example/,u,s
            https://ب1.example/,u,s
            https://bücher.example/,u,s
            https://لA.com/,u,s
            https://xn--a-moc.com/,u,s
            https://١٢٣.com/,u,s
            https://אa.example/,u,s
            https://a١.example/,u,s
            https://ب١1.example/,u,s
            """);

        // A name with right-to-left text has each label read one way; one
        // without, however it is spelled, has nothing to meet.
        Assert.Equal([2, 3, 4, 5], plan.Groups.Select(group => group.Candidates[0].RowNumber).Order());
        Assert.Contains(plan.Groups, group => group.Origin.Host == "xn--ghb.example");
        Assert.Equal(Rows(6, CredentialRowFlaw.MixedDirectionName, count: 6), plan.Rejections);
    }

    [Fact]
    public void NotesAndOneTimeCodeLinksImportUnderTheHeadersFilesUse() {
        const string link = "otpauth://totp/Crest:ada?secret=JBSWY3DPEHPK3PXP";
        foreach (string headers in new[] { "Notes,OTPAuth", "comments,totp", "note,One-Time Code", "notes,otp", "note,login_totp" }) {
            var candidate = Preview($"url,username,password,{headers}\nhttps://accounts.example,ada,s,In the desk, {link} \n")
                .Groups[0].Candidates[0];
            Assert.Equal(("In the desk", link), (candidate.Note, candidate.OneTimeCodeLink));
        }

        // A row with the saved password that brings a note or a link the saved
        // password lacks gives it them without asking; one that leaves them
        // out, or repeats them, changes nothing.
        string file = $"url,username,password,note,otpauth\nhttps://accounts.example,ada,s,In the desk,{link}\n";
        var details = Preview(file, Saved("ada", "s")).Groups[0];
        Assert.Equal((CredentialImportEffect.UpdatesDetails, false, (int?)2),
            (details.Candidates[0].Effect, details.RequiresChoice, details.SuggestedRow));
        Assert.Equal(CredentialImportEffect.Matches,
            Preview(file, Saved("ada", "s", note: "In the desk", link: link)).Groups[0].Candidates[0].Effect);
        Assert.Equal(CredentialImportEffect.Matches,
            Preview("url,username,password,note,otpauth\nhttps://accounts.example,ada,s,,\n", Saved("ada", "s", note: "Kept", link: link))
                .Groups[0].Candidates[0].Effect);
        Assert.Equal(CredentialImportEffect.Replaces, Preview(file, Saved("ada", "old")).Groups[0].Candidates[0].Effect);
    }

    [Fact]
    public void ASavedOriginSpelledOtherwiseThanAPageSpellsItIsRespelled() {
        Guid[] ids = [.. Enumerable.Range(0, 8).Select(_ => Guid.NewGuid())];
        SavedCredentialOrigin[] saved = [
            new(ids[0], new("https", "127.1", 443)),
            new(ids[1], new("https", "accounts.example", 443)),
            new(ids[2], new("https", "2001:DB8:0:0:0:0:0:1", 8443)),
            new(ids[3], new("http", "0x7f.0.0.1.", 80)),
            new(ids[4], new("https", "08.1.1.1", 443)),
            new(ids[5], new("https", "::ffff:1.2.3.4", 443)),
            new(ids[6], new("https", "127.0.0.1", 443)),
            new(ids[7], new("https", "Accounts.Example", 443))
        ];

        Assert.Equal([new(ids[0], new("https", "127.0.0.1", 443)), new(ids[2], new("https", "2001:db8::1", 8443)),
            new(ids[3], new("http", "127.0.0.1", 80)), new(ids[5], new("https", "::ffff:102:304", 443)),
            new SavedCredentialOrigin(ids[7], new("https", "accounts.example", 443))],
            Area.Query(new CredentialsToRespell(saved)).Respelled);
        Assert.Equal(new DuplicateCredential(),
            Assert.Throws<Rejected>(() => Area.Query(new CredentialsToRespell([saved[0], saved[0]]))).Rejection);
    }
}
