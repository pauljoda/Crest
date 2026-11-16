using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// The look `Text` stored, read as the stored session reads branding: a
/// member it lacks takes the reader's default and one it doesn't know is left
/// out, so a look kept by any build reads back in this one. Text that isn't a
/// look, or holds a member of the wrong kind, gives no look. It reads no
/// state, so a host may ask it without an app.
public sealed record RestoreLook(string Text) : StandaloneQuery<RestoredLook> {
    #region Actions - Answering

    internal override RestoredLook Answer(StandaloneContext context) {
        try {
            return JsonNode.Parse(Text) is JsonObject stored
                ? new(SpaceBranding.Normalized(StoredSessionCodec.DecodeBranding(stored)))
                : new(null);
        } catch (Exception error) when (error is JsonException or InvalidOperationException or FormatException) {
            return new(null);
        }
    }

    #endregion
}
