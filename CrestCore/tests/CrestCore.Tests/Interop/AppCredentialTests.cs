using CrestCore.Contracts;
using CrestCore.Domain;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// The credentials area through the native app boundary: encoded queries in,
/// encoded answers or one rejection out, and no password on either side.
public sealed class AppCredentialTests {
    /// Passwords never cross the boundary: the only text a credential question
    /// carries is an origin, where accounts are matched a username, and what
    /// the page says about a form's fields, never their values.
    [Fact]
    public void NoCredentialQueryCarriesAPassword() {
        Type[] queries = [typeof(CredentialCapture), typeof(CredentialFill), typeof(CredentialSaveCheck), typeof(MostRecentCredential),
            typeof(CredentialSaveMatch), typeof(CredentialSave), typeof(StrongPassword), typeof(CredentialAccess)];
        var found = new HashSet<Type>();
        var pending = new Queue<Type>(queries);
        var text = new SortedSet<string>(StringComparer.Ordinal);
        while (pending.TryDequeue(out var type)) {
            // A fixed set travels as its index in `All`, so it carries no text.
            if (!found.Add(type) || type.GetProperty("All") is not null) continue;
            foreach (var parameter in type.GetConstructors().Single().GetParameters()) {
                var parameterType = Nullable.GetUnderlyingType(parameter.ParameterType) ?? parameter.ParameterType;
                if (parameterType.IsGenericType) parameterType = parameterType.GetGenericArguments()[0];
                if (parameterType == typeof(string)) text.Add($"{type.Name}.{parameter.Name}");
                else if (parameterType.IsClass && parameterType.Assembly == typeof(Query<>).Assembly) pending.Enqueue(parameterType);
            }
        }
        Assert.Equal([
            "CredentialOrigin.Host", "CredentialOrigin.Scheme", "CredentialRecord.Username", "CredentialSaveMatch.Username",
            "FormField.Autocomplete", "FormField.IdAttribute", "FormField.Label", "FormField.Name", "FormField.PasswordRules",
            "FormField.Placeholder", "FormSubmission.ControlLabel", "PasswordRequirements.Rules"
        ], text);
    }
}
