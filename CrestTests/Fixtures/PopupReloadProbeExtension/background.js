// How many listeners this worker believes it registered. Every registration
// goes through the helpers below, so a dispatcher that only ever invokes the
// first listener can be told apart from a worker that never registered the
// rest.
self.__listenerCount = 0;
self.__messageListenerCount = 0;
self.__connectListenerCount = 0;

// Every step this worker takes, in order. Steps are buffered here as well as
// announced, because the earliest ones happen before any popup exists to hear
// them and would otherwise be lost.
self.__steps = [];
self.__startupSteps = [];

const describeError = (error) =>
  String(error && error.message ? error.message : error);

// NOTHING at top level in this file may throw. A worker that fails to load
// reports nothing at all, which is the least informative outcome available:
// every reading below is captured through this, so a missing API is recorded
// rather than fatal.
const attempt = (work) => {
  try {
    return work();
  } catch (error) {
    return `<threw: ${describeError(error)}>`;
  }
};

// Resolves in bounded time no matter what the promise does. A storage call
// that never settles is one of the hypotheses under test, so nothing here may
// await one unguarded.
const settle = (work, milliseconds) =>
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
        (error) => finish({ state: "rejected", error: describeError(error) })
      );
    } catch (error) {
      finish({ state: "rejected", error: describeError(error) });
    }
  });

// What one `*.storage` root actually looks like from here. The lexical `chrome`
// a rewritten worker bootstrap destructures need not be the native global, so
// each root is read separately and every read is guarded.
const describeStorageRoot = (root) => ({
  typeof: attempt(() => typeof root()),
  typeofLocal: attempt(() => typeof root()?.local),
  typeofLocalSet: attempt(() => typeof root()?.local?.set),
  typeofSession: attempt(() => typeof root()?.session),
  keys: attempt(() => Object.keys(root() ?? {})),
  ownKeys: attempt(() => Reflect.ownKeys(root() ?? {}).map(String))
});

// The whole storage surface, from the lexical roots AND from the native global
// roots that bypass any lexical shadow. If the lexical `chrome` is missing
// `storage` while `globalThis.chrome` has it, the shadow is the defect.
const captureStorageSurface = () => ({
  typeofChrome: attempt(() => typeof chrome),
  typeofBrowser: attempt(() => typeof browser),
  chromeIsGlobalChrome: attempt(() => chrome === globalThis.chrome),
  browserIsGlobalBrowser: attempt(() => browser === globalThis.browser),
  chromeOwnKeys: attempt(() =>
    Reflect.ownKeys(chrome ?? {})
      .map(String)
      .sort()
  ),
  globalChromeOwnKeys: attempt(() =>
    Reflect.ownKeys(globalThis.chrome ?? {})
      .map(String)
      .sort()
  ),
  chromeStorage: describeStorageRoot(() => chrome.storage),
  browserStorage: describeStorageRoot(() => browser.storage),
  globalChromeStorage: describeStorageRoot(() => globalThis.chrome.storage),
  globalBrowserStorage: describeStorageRoot(() => globalThis.browser.storage)
});

self.__storageSurface = attempt(captureStorageSurface);

// The channel that does NOT depend on storage: a fire-and-forget message back
// out to whatever pages are listening. Its rejection is captured rather than
// thrown, because a worker with no listening page must not be a broken worker.
const announce = (payload) => {
  try {
    return Promise.resolve(chrome.runtime.sendMessage(payload)).then(
      () => null,
      (error) => describeError(error)
    );
  } catch (error) {
    return Promise.resolve(describeError(error));
  }
};

// Records a step on both channels. Never awaited by its caller: the point of a
// step is that it is legible even when the next call hangs.
const step = (name, bucket) => {
  (bucket ?? self.__steps).push(name);
  announce({ kind: "step", step: name });
  return name;
};

announce({ kind: "storageSurface", surface: self.__storageSurface });

// Whichever storage area actually exists, in preference order, along with the
// name of the one chosen. A reading taken against an area that turned out to
// be missing would otherwise look like a hang.
const resolveStorageArea = (areaName) => {
  const candidates = [
    ["chrome.storage", () => chrome.storage],
    ["globalThis.chrome.storage", () => globalThis.chrome.storage],
    ["browser.storage", () => browser.storage],
    ["globalThis.browser.storage", () => globalThis.browser.storage]
  ];
  for (const [rootName, root] of candidates) {
    const area = attempt(() => {
      const candidate = root()?.[areaName];
      return candidate
        && typeof candidate.set === "function"
        && typeof candidate.get === "function"
        ? candidate
        : undefined;
    });
    if (area && typeof area !== "string") {
      return { name: `${rootName}.${areaName}`, area };
    }
  }
  return null;
};

// Storage is best-effort everywhere in this fixture. Losing a record must
// never take the worker down, because an absent record is itself an
// observation, and a hanging write must never block the caller.
const writeStorage = (values) => {
  const resolved = resolveStorageArea("local");
  if (!resolved) return;
  try {
    Promise.resolve(resolved.area.set(values)).catch(() => {});
  } catch (error) {
    // Reported by whichever step announcement follows.
  }
};

// STARTUP STORAGE, at top level and outside every handler. Its outcome is the
// control for the same race run from inside an onMessage handler: if the
// startup write settles and the in-handler one does not, the handler context
// is the difference rather than storage itself.
step("startupStorage:start", self.__startupSteps);
const startupArea = resolveStorageArea("local");
if (!startupArea) {
  step("startupStorage:noSurface", self.__startupSteps);
} else {
  step(`startupStorage:using:${startupArea.name}`, self.__startupSteps);
  settle(
    attempt(() => startupArea.area.set({ __startupStorage: Date.now() })),
    2000
  ).then((outcome) => {
    if (outcome.state === "resolved") {
      step("startupStorage:setResolved", self.__startupSteps);
    } else if (outcome.state === "rejected") {
      step(
        `startupStorage:setRejected:${outcome.error}`,
        self.__startupSteps
      );
    } else {
      step("startupStorage:setTimedOut", self.__startupSteps);
    }
  });
}

// A classic MV3 service worker whose first job is to stand up one offscreen
// document at startup, the way a password manager brings up its offscreen
// clipboard host. The popup later enumerates chrome.extension.getViews(), so
// what matters here is only that the document exists by the time the popup
// opens.
async function createProbeOffscreenDocument() {
  let record;
  try {
    await chrome.offscreen.createDocument({
      url: "offscreen.html",
      reasons: ["CLIPBOARD"],
      justification: "probe"
    });
    record = { state: "created" };
    step("offscreen:created");
  } catch (error) {
    record = { state: "failed", message: describeError(error) };
    step(`offscreen:failed:${record.message}`);
  }
  // Deliberately not awaited: a hanging write must not strand this function.
  writeStorage({ offscreenCreation: record });
}

attempt(createProbeOffscreenDocument);

// The internal-sender contract a password manager's worker applies to its
// popup's long-lived `runtime.connect({name: "session"})` port: it accepts the
// port only when `sender.origin` parses and matches the origin of
// `chrome.runtime.getURL("")`, and when the sender either carries no `frameId`
// at all or reports frame 0. A port rejected there is dropped silently, and the
// popup's state channel has no timeout behind it, so the popup waits forever.
// Both transports are reported, because `onMessage` and `onConnect` build their
// sender objects on separate paths.
const describeSender = (sender) => ({
  origin: sender?.origin,
  url: sender?.url,
  frameId: sender?.frameId,
  hasFrameId: sender ? "frameId" in sender : null,
  id: sender?.id,
  hasTab: !!sender?.tab,
  documentId: sender?.documentId
});

const senderReport = (sender) => ({
  kind: "sender",
  sender: describeSender(sender),
  runtimeURL: chrome.runtime.getURL(""),
  runtimeId: chrome.runtime.id
});

const addMessageListener = (listener) => {
  self.__listenerCount += 1;
  self.__messageListenerCount += 1;
  chrome.runtime.onMessage.addListener(listener);
};

const addConnectListener = (listener) => {
  self.__listenerCount += 1;
  self.__connectListenerCount += 1;
  chrome.runtime.onConnect.addListener(listener);
};

addConnectListener((port) => {
  if (port.name !== "probe") return;
  port.postMessage(senderReport(port.sender));
});

// Walks the storage calls under test against whichever area exists, each
// raced, announcing every step as it goes. It always resolves, so its caller
// can always reply.
async function runStorageProbeSteps() {
  const at = Date.now();
  step("storageProbe:start");
  const surface = attempt(captureStorageSurface);
  self.__storageSurface = surface;

  const local = resolveStorageArea("local");
  if (!local) {
    step("storageProbe:noSurface");
    step("storageProbe:replying");
    return {
      ok: false,
      at,
      areaName: null,
      setState: "noSurface",
      setError: null,
      getState: "noSurface",
      storageSurface: surface,
      steps: self.__steps.slice(),
      startupSteps: self.__startupSteps.slice()
    };
  }
  step(`storageProbe:using:${local.name}`);

  const setOutcome = await settle(
    attempt(() => local.area.set({ __storageProbe: at })),
    2000
  );
  if (setOutcome.state === "resolved") {
    step("storageProbe:setResolved");
  } else if (setOutcome.state === "rejected") {
    step(`storageProbe:setRejected:${setOutcome.error}`);
  } else {
    step("storageProbe:setTimedOut");
  }

  const getOutcome = await settle(
    attempt(() => local.area.get("__storageProbe")),
    2000
  );
  if (getOutcome.state === "resolved") {
    step(
      `storageProbe:getResolved:${JSON.stringify(
        getOutcome.value?.__storageProbe ?? null
      )}`
    );
  } else if (getOutcome.state === "rejected") {
    step(`storageProbe:getRejected:${getOutcome.error}`);
  } else {
    step("storageProbe:getTimedOut");
  }

  const session = resolveStorageArea("session");
  if (!session) {
    step("storageProbe:sessionUnavailable");
  } else {
    step(`storageProbe:sessionUsing:${session.name}`);
    const sessionOutcome = await settle(
      attempt(() => session.area.set({ __s: 1 })),
      2000
    );
    if (sessionOutcome.state === "resolved") {
      step("storageProbe:sessionSetResolved");
    } else if (sessionOutcome.state === "rejected") {
      step(`storageProbe:sessionSetRejected:${sessionOutcome.error}`);
    } else {
      step("storageProbe:sessionSetTimedOut");
    }
  }

  step("storageProbe:replying");
  return {
    ok: setOutcome.state === "resolved",
    at,
    areaName: local.name,
    setState: setOutcome.state,
    setError: setOutcome.error ?? null,
    getState: getOutcome.state,
    storageSurface: surface,
    steps: self.__steps.slice(),
    startupSteps: self.__startupSteps.slice()
  };
}

// THE FIRST-REGISTERED MESSAGE LISTENER. Every probe whose own reachability
// must not be in question is answered from inside this one listener, so that a
// dispatcher which invokes only the first listener can still answer them. In
// particular the storage probe and the listener count live here: asking them
// from a later listener would confound the very thing they exist to isolate.
addMessageListener((message, sender, sendResponse) => {
  if (message?.kind === "storageProbe") {
    // Every storage call inside is raced, so this always replies. A reply that
    // says "timed out" is the finding; a reply that never comes is not.
    runStorageProbeSteps().then(sendResponse, (error) =>
      sendResponse({
        ok: false,
        error: describeError(error),
        storageSurface: self.__storageSurface,
        steps: self.__steps.slice(),
        startupSteps: self.__startupSteps.slice()
      })
    );
    return true;
  }

  if (message?.kind === "listenerCount") {
    sendResponse({
      listenerCount: self.__listenerCount,
      messageListenerCount: self.__messageListenerCount,
      connectListenerCount: self.__connectListenerCount,
      storageSurface: self.__storageSurface,
      steps: self.__steps.slice(),
      startupSteps: self.__startupSteps.slice()
    });
    return false;
  }

  if (message?.kind === "requestBroadcast") {
    // The worker-to-popup half of a post-unlock sync: fire-and-forget, with
    // nothing replying to it. The send's own outcome is reported on both
    // channels, and the send itself is raced, so an announcement that never
    // settles cannot swallow the record of it.
    const sent = chrome.runtime.sendMessage({
      kind: "broadcast",
      at: Date.now()
    });
    settle(sent, 2000).then((outcome) => {
      const record =
        outcome.state === "resolved"
          ? { resolved: true, returnedType: typeof sent }
          : outcome.state === "rejected"
            ? { rejected: outcome.error, returnedType: typeof sent }
            : { rejected: "the send never settled", returnedType: typeof sent };
      writeStorage({ __broadcastSend: record });
      announce({ kind: "broadcastOutcome", ...record });
    });
    return false;
  }

  if (message?.kind !== "probe") return false;
  sendResponse(senderReport(sender));
  return false;
});

// How a password manager actually wires its worker: several
// `runtime.onMessage` listeners registered against one message, some of which
// return `true` to reply asynchronously and some of which return nothing at
// all. Chrome delivers the event to every listener regardless of what any
// earlier one returned, and only the reply is arbitrated. A dispatcher that
// stops at the first listener would silently skip the listeners a vault's
// state actually rides on.
//
// Each listener reports that it ran on BOTH channels — an out-of-band message
// straight back to the popup, and a republished storage array — so that a
// missing label means a listener that never ran rather than a channel that
// never landed.
const recordDispatch = (key, order) => (label) => {
  order.push(label);
  writeStorage({ [key]: order.slice() });
  announce({ kind: "dispatchRecord", key, label }).then((rejection) => {
    if (!rejection) return;
    order.push(`${label} announce rejected: ${rejection}`);
    writeStorage({ [key]: order.slice() });
  });
};

const recordMultiDispatch = recordDispatch("__multiDispatch", []);

// Registration order is the contract under test, so these stay in order.
addMessageListener((message, sender, sendResponse) => {
  if (message?.kind !== "multi") return;
  recordMultiDispatch("A");
  setTimeout(() => sendResponse({ from: "A" }), 50);
  return true;
});

addMessageListener((message) => {
  if (message?.kind !== "multi") return;
  recordMultiDispatch("B");
});

addMessageListener((message) => {
  if (message?.kind !== "multi") return;
  recordMultiDispatch("C");
  return Promise.resolve({ from: "C" });
});

addMessageListener((message) => {
  if (message?.kind !== "multi") return;
  recordMultiDispatch("D");
});

// The same question with the promise-returning listener first, which is the
// arrangement that decides whether a listener registered after one can still
// be reached at all.
const recordMultiPromiseFirst = recordDispatch(
  "__multiDispatchPromiseFirst",
  []
);

addMessageListener((message) => {
  if (message?.kind !== "multiPromiseFirst") return;
  recordMultiPromiseFirst("C");
  return Promise.resolve({ from: "C" });
});

addMessageListener((message) => {
  if (message?.kind !== "multiPromiseFirst") return;
  recordMultiPromiseFirst("B");
});
