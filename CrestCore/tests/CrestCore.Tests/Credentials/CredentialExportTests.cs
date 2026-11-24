using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Writing a Space's password file: its columns and quoting, the order of
/// its rows, and the file name cleaned from the Space's name.
public sealed class CredentialExportTests {
    private static readonly CrestApp Area = new();

    private static ExportedCredential Credential(string host, string username, string password, string? name = null, int port = 443,
        string note = "", string? link = null, Guid? id = null) =>
        new(id ?? Guid.NewGuid(), new CredentialOrigin("https", host, port), username, name, password, note, link);

    [Fact]
    public void EveryFieldIsQuotedAndARowWithoutANameTakesItsHost() {
        var file = Area.Query(new CredentialExport([
            Credential("accounts.crest.test", "work,person@example.com", "line one\n\"line two\"", name: "Crest, Account"),
            Credential("realm.crest.test", "ada", "secret", port: 8443, note: "HTTP Basic authentication")
        ], "Work", "Space"));

        Assert.Equal("\"name\",\"url\",\"username\",\"password\",\"note\",\"otpauth\"\r\n"
            + "\"Crest, Account\",\"https://accounts.crest.test\",\"work,person@example.com\",\"line one\n\"\"line two\"\"\",\"\",\"\"\r\n"
            + "\"realm.crest.test\",\"https://realm.crest.test:8443\",\"ada\",\"secret\",\"HTTP Basic authentication\",\"\"\r\n",
            Encoding.UTF8.GetString(file.Contents));
        Assert.Equal("Crest Passwords - Work.csv", file.FileName);
    }

    [Fact]
    public void NotesAndOneTimeCodeLinksReadBackFromAnExportedFile() {
        const string link = "otpauth://totp/Crest:ada?secret=JBSWY3DPEHPK3PXP&issuer=Crest";
        var file = Area.Query(new CredentialExport([
            Credential("accounts.crest.test", "ada", "secret", note: "Recovery codes are in the safe,\n\"top\" drawer", link: link),
            Credential("plain.crest.test", "grace", "hidden")
        ], "Work", "Space"));

        var plan = Area.Query(new CredentialImportPreview(file.Contents, []));
        Assert.Equal(CredentialFileFormat.Browser, plan.Format);
        Assert.Equal([("ada", "Recovery codes are in the safe,\n\"top\" drawer", link), ("grace", null, null)],
            plan.Groups.Select(group => (group.Username, group.Candidates[0].Note, group.Candidates[0].OneTimeCodeLink)));
    }
}
