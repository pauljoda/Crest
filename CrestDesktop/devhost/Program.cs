using CrestDesktop.DevHost;

// dotnet run --project CrestDesktop/devhost -- --core <path to CrestCore.Native.dll> [--port 8787]
string Option(string name, string? fallback) {
    int index = Array.IndexOf(args, name);
    return index >= 0 && index + 1 < args.Length ? args[index + 1]
        : fallback ?? throw new ArgumentException($"{name} is required.");
}

CoreLibrary.Load(Option("--core", Environment.GetEnvironmentVariable("CREST_CORE_LIBRARY")));
int port = int.Parse(Option("--port", "8787"), System.Globalization.CultureInfo.InvariantCulture);

var builder = WebApplication.CreateSlimBuilder();
builder.WebHost.UseUrls($"http://127.0.0.1:{port}");
var host = builder.Build();
host.UseWebSockets();
host.Map("/core", async context => {
    if (!context.WebSockets.IsWebSocketRequest) {
        context.Response.StatusCode = StatusCodes.Status400BadRequest;
        return;
    }
    using var socket = await context.WebSockets.AcceptWebSocketAsync();
    await using var session = new CoreSession(socket);
    try {
        await session.Serve(context.RequestAborted);
    } catch (Exception error) when (error is OperationCanceledException or System.Net.WebSockets.WebSocketException) {
        // The interface went away.
    }
});
Console.WriteLine($"Crest core bridge on ws://127.0.0.1:{port}/core");
await host.RunAsync();
