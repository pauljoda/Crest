// The popup half of the probe. `__probe` reports what
// `chrome.extension.getViews()` answers from a popup page — untyped, and under
// each of the type filters WebKit could classify a view with — and `__reload`
// runs the post-two-factor sweep verbatim: enumerate the views, drop anything
// whose href is absent or names a background page, exempt the view whose href
// equals the popup's own, and reload the rest. Chrome hands that sweep nothing
// to do, because the popup is the only view it returns and its href matches
// exactly. Anything else is what this fixture exists to show.
const getExtensionViews = (filter) => {
  if (
    typeof chrome === "undefined"
    || typeof chrome.extension === "undefined"
    || typeof chrome.extension.getViews === "undefined"
  ) {
    return [];
  }
  return chrome.extension.getViews(filter) ?? [];
};

const describeView = (view) => {
  try {
    return {
      href: view.location.href == null ? null : String(view.location.href),
      sameWindow: view === window
    };
  } catch (error) {
    return { error: String(error) };
  }
};

const describeViews = (filter) => {
  try {
    return getExtensionViews(filter).map(describeView);
  } catch (error) {
    return [{ error: String(error) }];
  }
};

const currentWindowID = () => {
  try {
    if (
      typeof chrome === "undefined"
      || typeof chrome.windows === "undefined"
    ) {
      return undefined;
    }
    return chrome.windows.WINDOW_ID_CURRENT;
  } catch (error) {
    return undefined;
  }
};

window.__probe = () => {
  const windowID = currentWindowID();
  const probe = {
    self: self.location.href,
    views: describeViews(),
    tabViews: describeViews({ type: "tab" }),
    popupViews: describeViews({ type: "popup" }),
    currentWindowID: windowID === undefined ? null : windowID,
    hasGetContexts:
      typeof chrome === "undefined"
        || typeof chrome.runtime === "undefined"
        ? "undefined"
        : typeof chrome.runtime.getContexts
  };
  probe.currentWindowTabViews =
    windowID === undefined
      ? null
      : describeViews({ type: "tab", windowId: windowID });
  return probe;
};

window.__reload = () => {
  const outcome = { reloaded: [], skipped: [], errors: [] };
  let views;
  try {
    views = getExtensionViews();
  } catch (error) {
    outcome.errors.push({ stage: "enumerate", error: String(error) });
    return outcome;
  }
  if (!views.length) return outcome;
  const own = self.location.href;
  const candidates = [];
  for (const view of views) {
    let href;
    try {
      href = view.location.href;
    } catch (error) {
      outcome.errors.push({ stage: "read", error: String(error) });
      continue;
    }
    if (href == null || href.includes("background.html")) {
      outcome.skipped.push({
        href: href == null ? null : String(href),
        reason: "filtered"
      });
      continue;
    }
    if (href === own) {
      outcome.skipped.push({ href: String(href), reason: "exempt" });
      continue;
    }
    candidates.push({ view, href: String(href) });
  }
  for (const candidate of candidates) {
    try {
      candidate.view.location.reload();
      outcome.reloaded.push(candidate.href);
    } catch (error) {
      outcome.errors.push({
        stage: "reload",
        href: candidate.href,
        error: String(error)
      });
    }
  }
  return outcome;
};


// The popup half of the internal-sender contract. Both transports are driven
// from the popup page itself, because what the worker judges is the sender
// object WebKit builds for a popup document — not for a tab.
window.__portProbe = () =>
  new Promise((resolve) => {
    const port = chrome.runtime.connect({ name: "probe" });
    const timer = setTimeout(() => resolve({ timeout: true }), 4000);
    port.onMessage.addListener((message) => {
      clearTimeout(timer);
      resolve(message);
    });
    port.onDisconnect.addListener(() =>
      resolve({
        disconnected: true,
        lastError: chrome.runtime.lastError?.message
      })
    );
  });

window.__messageProbe = () =>
  new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ timeout: true }), 4000);
    chrome.runtime.sendMessage({ kind: "probe" }, (reply) => {
      clearTimeout(timer);
      resolve({ reply, lastError: chrome.runtime.lastError?.message });
    });
  });

// Drives one of the worker's multi-listener message kinds from the popup. The
// callback form is used deliberately: it is the form whose reply the worker's
// listeners compete to supply.
window.__multiProbe = (kind) =>
  new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ timeout: true }), 4000);
    chrome.runtime.sendMessage({ kind }, (reply) => {
      clearTimeout(timer);
      resolve({ reply, lastError: chrome.runtime.lastError?.message });
    });
  });

// Every observation the worker reports out-of-band is collected here, at popup
// load, before any probe runs. Storage and this channel are the two the worker
// reports on; collecting both is what lets an unrun listener be told apart
// from an unlanded write.
window.__dispatchRecords = [];
window.__storageSurface = null;
chrome.runtime.onMessage.addListener((message) => {
  if (message?.kind === "storageSurface") {
    // Announced at worker startup, before this popup existed, so it usually
    // arrives only via the probe replies. Kept here for the case where a
    // worker restarts while the popup is open.
    window.__storageSurface = message.surface ?? null;
    return;
  }
  if (message?.kind === "dispatchRecord") {
    window.__dispatchRecords.push({
      key: message.key,
      label: message.label
    });
    return;
  }

});

// Resolves in bounded time no matter what the promise does. The popup's own
// storage call is raced for the same reason the worker's are: if the popup
// side is what hangs, this probe must still answer rather than stranding the
// evaluation that called it.
window.__settle = (work, milliseconds) =>
  new Promise((resolve) => {
    let done = false;
    let timer;
    const finish = (outcome) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      resolve(outcome);
    };
    timer = setTimeout(() => finish({ state: "timedOut" }), milliseconds);
    try {
      Promise.resolve(work).then(
        (value) => finish({ state: "resolved", value: value ?? null }),
        (error) =>
          finish({
            state: "rejected",
            error: String(error && error.message ? error.message : error)
          })
      );
    } catch (error) {
      finish({
        state: "rejected",
        error: String(error && error.message ? error.message : error)
      });
    }
  });

// Reads one storage key with a bound on how long it may hang, so a hanging
// read reports itself instead of stranding the caller.
window.__readStorage = async (key, milliseconds) => {
  const outcome = await window.__settle(
    chrome.storage.local.get(key),
    milliseconds ?? 2000
  );
  if (outcome.state === "resolved") {
    return { state: "resolved", value: outcome.value?.[key] ?? null };
  }
  return outcome;
};

// How many listeners the worker believes it registered, answered from the
// worker's first-registered listener so the count is reachable even if later
// listeners are never invoked.
window.__listenerCountProbe = () =>
  new Promise((resolve) => {
    const timer = setTimeout(() => resolve({ timeout: true }), 4000);
    chrome.runtime.sendMessage({ kind: "listenerCount" }, (reply) => {
      clearTimeout(timer);
      resolve({ reply, lastError: chrome.runtime.lastError?.message });
    });
  });

// Set last, so that a popup reporting readiness has every probe defined.
window.__probeReady = true;
