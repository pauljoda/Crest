"use strict";

// Crest Conformance Probe -- content script (http://127.0.0.1/* only).
//
// Records which storage.onChanged events actually reach a content script:
//   (a) the background's `bgToCs` write, which arrives ~2 s after worker start;
//   (b) any change whose key is `forged`, which the fixture page tries to inject
//       over a BroadcastChannel. Seeing `forged` proves web content can fabricate
//       extension storage events.
//
// It writes its findings ONCE, 3500 ms after load, in a single set() call, and
// ignores the `__cs` / `__report` keys so it never feeds its own listener.

(function () {
  const api = globalThis.chrome ?? globalThis.browser;
  const LOAD_AT = Date.now();
  const IGNORED = new Set(["__cs", "__report"]);
  const seen = [];

  let sawBgToCs = false;
  let sawForged = false;
  let listenerError = null;
  let writeError = null;

  const show = (e) => (e && e.message ? e.message : String(e));

  try {
    api.storage.onChanged.addListener((changes, areaName) => {
      for (const key of Object.keys(changes || {})) {
        if (IGNORED.has(key)) continue;
        if (seen.length < 40) {
          seen.push({ key, areaName, at: Date.now() - LOAD_AT });
        }
        if (key === "bgToCs") sawBgToCs = true;
        if (key === "forged") sawForged = true;
      }
    });
  } catch (error) {
    listenerError = show(error);
  }

  try {
    api.storage.local.set({ csWrite: Date.now() });
  } catch (error) {
    writeError = "csWrite: " + show(error);
  }

  setTimeout(function report() {
    const payload = {
      at: Date.now(),
      loadedAt: new Date(LOAD_AT).toISOString(),
      href: location.href,
      context: "content-script",
      userAgent: navigator.userAgent,
      sawBgToCs: sawBgToCs,
      sawForged: sawForged,
      listenerError: listenerError,
      writeError: writeError,
      onChangedType: typeof (api && api.storage && api.storage.onChanged && api.storage.onChanged.addListener),
      seen: seen
    };
    try {
      const result = api.storage.local.set({ __cs: payload });
      if (result && typeof result.catch === "function") {
        result.catch((error) => console.error("probe cs: set failed", show(error)));
      }
    } catch (error) {
      console.error("probe cs: set threw", show(error));
    }
  }, 3500);
})();
