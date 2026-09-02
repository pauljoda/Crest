# Conformance Probe fixture site

A plain web page served over HTTP so the Crest Conformance Probe's content script
(`matches: ["http://127.0.0.1/*"]`) is injected into it.

Serve it from the repository root with:

```
python3 -m http.server 8765 --bind 127.0.0.1 --directory CrestTests/Fixtures/ConformanceProbeSite
```

Then open <http://127.0.0.1:8765/> in the browser under test and leave it open for
about ten seconds.

## What the page does

- Subscribes to `BroadcastChannel("__crestWebExtensionStorageBridgeV1")` and appends every
  message it receives to the **Leaked messages** pane (also kept in `window.__crestLeak`).
  In Chrome this pane stays empty. Anything here is extension storage traffic that escaped
  into web content; if it contains the `secret` value shown in the probe's `storage.leak`
  row, the leak is proven end to end.
- After 1500 ms it forges a storage-change message on that channel claiming
  `{ forged: { newValue: "from-web-page" } }`. If the probe's `storage.contentScript.echo`
  row reports `sawForged: true`, a web page can fabricate extension storage events.

Screenshot this page alongside the extension's `results.html`.
