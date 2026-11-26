using CrestDesktop.DevHost;

// dotnet run --project CrestDesktop/devhost -- --core <path to CrestCore.Native.dll> [--port 8787]
string Option(string name, string? fallback) {
    int index = Array.IndexOf(args, name);
    return index >= 0 && index + 1 < args.Length ? args[index + 1]
        : fallback ?? throw new ArgumentException($"{name} is required.");
}

CoreLibrary.Load(Option("--core", Environment.GetEnvironmentVariable("CREST_CORE_LIBRARY")));
int port = int.Parse(Option("--port", "8787"), System.Globalization.CultureInfo.InvariantCulture);

// Only the local interface that started this session may open its native bridge.
var origin = new Uri(Option("--origin", "http://127.0.0.1:5173"));
bool localInterface = origin.Scheme == Uri.UriSchemeHttp && origin.Host == "127.0.0.1";
bool comparisonInterface = origin.Scheme == "chrome" && origin.Host == "crest-comparison" && origin.IsDefaultPort;
if ((!localInterface && !comparisonInterface) || origin.PathAndQuery != "/" ||
    origin.UserInfo.Length != 0 || origin.Fragment.Length != 0)
    throw new ArgumentException("--origin must identify the local interface or chrome://crest-comparison.");

var builder = WebApplication.CreateSlimBuilder();
builder.WebHost.UseUrls($"http://127.0.0.1:{port}");
var host = builder.Build();
host.UseWebSockets();
host.MapGet("/health", () => Results.Ok());
int readyWindows = 0;
host.MapGet("/session", () => Volatile.Read(ref readyWindows) > 0
    ? Results.Ok() : Results.StatusCode(StatusCodes.Status503ServiceUnavailable));

host.Map("/core", async context => {
    if (!context.WebSockets.IsWebSocketRequest) {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }
    if (!string.Equals(context.Request.Headers.Origin, origin.GetLeftPart(UriPartial.Authority), StringComparison.Ordinal)) {
        context.Response.StatusCode = StatusCodes.Status403Forbidden;
        return;
    }
    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await using var session = new CoreSession(socket);
    bool ready = false;
    void ComparisonReady() {
        if (ready) return;
        ready = true;
        Interlocked.Increment(ref readyWindows);
    }
    try {
        await session.Serve(context.RequestAborted, ComparisonReady);
    } catch (Exception error) when (error is OperationCanceledException or System.Net.WebSockets.WebSocketException) {
        // The interface went away.
    } finally {
        if (ready) Interlocked.Decrement(ref readyWindows);
    }
});
Console.WriteLine($"Crest core bridge on ws://127.0.0.1:{port}/core");
await host.RunAsync();
