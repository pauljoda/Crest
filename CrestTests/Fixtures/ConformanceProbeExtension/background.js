"use strict";

// Crest Conformance Probe -- background service worker.
// Runs every check on worker start, and again on runtime.onInstalled (which also
// opens results.html in a tab). No check may throw out of the runner: each one is
// wrapped and records its own error as the observed value. The report lands in
// storage.local["__report"]; results.html re-renders whenever it changes.

const api = globalThis.chrome ?? globalThis.browser;
const PROBE_VERSION = "1.0.0";
const WORKER_START = Date.now();
const REPORT_KEY = "__report";
const CS_KEY = "__cs";

const checks = new Map();
const events = [];
const orderSeq = [];
let alarmFiredAt = null;
let runPromise = null;
let secret = "(pending)";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const show = (e) => (e && e.message ? e.message : String(e));
const has = (o, k) => Object.prototype.hasOwnProperty.call(o || {}, k);

function setCheck(name, status, observed, expected, note) {
  checks.set(name, { name, status, observed, expected, note });
}

// Runs fn and records {status, observed}; any throw becomes the observed value.
async function check(name, expected, fn, note) {
  try {
    const r = await fn();
    setCheck(name, r.status, r.observed, expected, note);
  } catch (error) {
    setCheck(name, "FAIL", { threw: show(error) }, expected, note);
  }
}

api.storage.onChanged.addListener((changes, areaName) => {
  const at = Date.now();
  for (const [key, c] of Object.entries(changes || {})) {
    if (key === REPORT_KEY) continue;
    if (key === "order") orderSeq.push("event");
    events.push({
      at, areaName, key,
      oldValue: c ? c.oldValue : undefined,
      newValue: c ? c.newValue : undefined,
      hasNewValue: has(c, "newValue"),
      hasOldValue: has(c, "oldValue")
    });
  }
  if (has(changes, CS_KEY)) refreshContentScriptCheck().catch(() => {});
});

api.alarms.onAlarm.addListener((alarm) => {
  if (!alarmFiredAt && alarm && alarm.name === "probe") alarmFiredAt = Date.now();
});

api.runtime.onInstalled.addListener(() => {
  ensureRun()
    .then(() => api.tabs.create({ url: api.runtime.getURL("results.html") }))
    .catch(() => {});
});

const eventsFor = (key, from) => events.slice(from).filter((e) => e.key === key);

// Calls a callback-style API, reading runtime.lastError inside the callback.
function callWithCallback(label, invoke, timeoutMs) {
  return new Promise((resolve) => {
    let settled = false;
    const finish = (v) => { if (!settled) { settled = true; resolve(v); } };
    setTimeout(() => finish({ label, timedOut: true }), timeoutMs || 4000);
    try {
      invoke((...args) => {
        const le = api.runtime.lastError;
        finish({ label, arg: args[0], lastError: le ? le.message : undefined });
      });
    } catch (error) { finish({ label, threwSynchronously: true, message: show(error) }); }
  });
}

async function writeReport() {
  const report = {
    probeVersion: PROBE_VERSION, browser: navigator.userAgent,
    ranAt: new Date().toISOString(), context: "worker",
    workerStart: new Date(WORKER_START).toISOString(), checks: Array.from(checks.values())
  };
  try { await api.storage.local.set({ [REPORT_KEY]: report }); }
  catch (error) { console.error("probe: could not store report", error); }
}

function checkIdentity() {
  setCheck("identity", "INFO", {
    "runtime.id": api.runtime.id,
    'runtime.getURL("")': api.runtime.getURL(""),
    "manifest.background": api.runtime.getManifest().background,
    "navigator.userAgent": navigator.userAgent
  }, "informational");
}

async function checkPermissions() {
  await check("permissions.getAll", 'includes storage/alarms/tabs/idle, excludes "nativeMessaging"', async () => {
    const granted = await api.permissions.getAll();
    const list = (granted && granted.permissions) || [];
    const missing = ["storage", "alarms", "tabs", "idle"].filter((p) => !list.includes(p));
    const bogus = list.includes("nativeMessaging");
    const origins = (granted && granted.origins) || [];
    return { status: missing.length === 0 && !bogus ? "PASS" : "FAIL",
      observed: { permissions: list, origins, missing, includesNativeMessaging: bogus } };
  });
}

function checkAbsent(name, ns) {
  const t = typeof api[ns];
  const observed = { typeof: t };
  if (t !== "undefined" && api[ns] !== null) {
    try { observed.keys = Object.keys(api[ns]); } catch (error) { observed.keys = show(error); }
  }
  setCheck(name, t === "undefined" ? "PASS" : "FAIL", observed, '"undefined" (permission not requested)');
}

async function checkStorageChangeCount() {
  await check("storage.onChanged.count", "3 events for `probe` (Chrome fires on every set, even identical)", async () => {
    await api.storage.local.remove("probe");
    await sleep(150);
    const from = events.length;
    await api.storage.local.set({ probe: 1 });
    await api.storage.local.set({ probe: 1 });
    await api.storage.local.set({ probe: 2 });
    await sleep(1000);
    const seen = eventsFor("probe", from);
    const sequence = seen.map((e) => ({ oldValue: e.oldValue, newValue: e.newValue }));
    return { status: seen.length === 3 ? "PASS" : "FAIL", observed: { count: seen.length, sequence } };
  });
}

async function checkStorageChangeShape() {
  const expected = 'set: {oldValue:"a", newValue:"b"}; remove: {oldValue:"b"} with no newValue key';
  await check("storage.onChanged.shape", expected, async () => {
    await api.storage.local.remove("shape");
    await sleep(150);
    const from = events.length;
    await api.storage.local.set({ shape: "a" });
    await sleep(150);
    await api.storage.local.set({ shape: "b" });
    await sleep(150);
    await api.storage.local.remove("shape");
    await sleep(400);
    const seen = eventsFor("shape", from);
    const second = seen[1], removal = seen[2];
    const setOk = !!second && second.oldValue === "a" && second.newValue === "b";
    const removeOk = !!removal && removal.oldValue === "b" && removal.hasNewValue === false;
    return { status: setOk && removeOk ? "PASS" : "FAIL", observed: {
      eventCount: seen.length, setOk, removeOk,
      secondSet: second ? { oldValue: second.oldValue, newValue: second.newValue } : null,
      afterRemove: removal ? { oldValue: removal.oldValue, hasNewValueKey: removal.hasNewValue } : null
    } };
  });
}

async function checkStorageChangeOrder() {
  const expected = "informational -- whether the set() callback or the onChanged listener runs first";
  await check("storage.onChanged.order", expected, async () => {
    orderSeq.length = 0;
    await new Promise((resolve) => {
      try { api.storage.local.set({ order: Date.now() }, () => { orderSeq.push("callback"); resolve(); }); }
      catch (error) { orderSeq.push("threw:" + show(error)); resolve(); }
    });
    await sleep(500);
    const first = orderSeq[0];
    const ordering = first === "event" ? "event-first" : first === "callback" ? "callback-first" : "unknown";
    return { status: "INFO", observed: { ordering, sequence: orderSeq.slice() } };
  });
}

async function checkLastErrorCallback() {
  await check("lastError.callback", 'arg undefined and lastError "No window with id: 2147483000."', async () => {
    const r = await callWithCallback("windows.update", (cb) => api.windows.update(2147483000, { left: 10 }, cb));
    return { status: typeof r.lastError === "string" && r.lastError.length > 0 ? "PASS" : "FAIL", observed: r };
  });
  // Chrome throws synchronously here: idle's detectionIntervalInSeconds minimum is 15.
  await check("lastError.idle", "throws synchronously (detectionIntervalInSeconds minimum is 15)", async () => {
    return { status: "INFO", observed: await callWithCallback("idle.queryState", (cb) => api.idle.queryState(5, cb)) };
  });
}

async function checkTabs() {
  await check("tabs.pinned", "informational -- saved/unloaded sidebar tabs must NOT report pinned:true", async () => {
    const tabs = await api.tabs.query({});
    const rows = tabs.map((t) => ({ id: t.id, index: t.index, pinned: t.pinned, active: t.active, url: t.url }));
    return { status: "INFO", observed: { count: tabs.length, tabs: rows } };
  }, "Compare against the sidebar: saved tabs must NOT be pinned.");
}

async function checkLastErrorPromise() {
  await check("runtime.lastError.promise", "the promise rejects with a non-empty message", async () => {
    let rejected = false, message = null, resolvedWith;
    try { resolvedWith = await api.windows.update(2147483000, { left: 10 }); }
    catch (error) { rejected = true; message = show(error); }
    const ok = rejected && typeof message === "string" && message.length > 0;
    return { status: ok ? "PASS" : "FAIL", observed: { rejected, message, resolvedWith } };
  });
}

function checkGetViews() {
  setCheck("getViews.inWorker", "INFO", {
    "typeof chrome.extension": typeof api.extension,
    "typeof chrome.extension.getViews": typeof (api.extension && api.extension.getViews)
  }, 'Chrome MV3: chrome.extension is an object, getViews is "undefined" inside a worker');
}

const CS_EXPECTED = "saw the background `bgToCs` write, and never saw a `forged` change";
const CS_NOTE = "Needs http://127.0.0.1:8765/ open. A page-injected `forged` change proves a storage bridge leak.";

async function refreshContentScriptCheck() {
  try {
    const stored = await api.storage.local.get(CS_KEY);
    const cs = stored ? stored[CS_KEY] : undefined;
    if (!cs) {
      setCheck("storage.contentScript.echo", "INFO",
        "no content-script report yet -- open http://127.0.0.1:8765/ and wait ~5 s", CS_EXPECTED, CS_NOTE);
    } else {
      const stale = typeof cs.at === "number" && cs.at < WORKER_START;
      const ok = cs.sawBgToCs === true && cs.sawForged === false;
      setCheck("storage.contentScript.echo", stale ? "INFO" : ok ? "PASS" : "FAIL",
        Object.assign({ stale }, cs), CS_EXPECTED,
        stale ? CS_NOTE + " This report predates the current worker -- reload the fixture page." : CS_NOTE);
    }
  } catch (error) { setCheck("storage.contentScript.echo", "FAIL", { threw: show(error) }, CS_EXPECTED, CS_NOTE); }
  await writeReport();
}

function setLeakCheck() {
  setCheck("storage.leak", "INFO",
    { secretWritten: secret, readTheLeakPaneAt: "http://127.0.0.1:8765/" },
    "the fixture page's leak pane stays empty",
    "Cannot be observed from inside the extension: read the fixture page's leak pane. If it shows the secret above, extension storage is leaking into web content.");
}

async function waitForAlarm() {
  const deadline = Date.now() + 30000;
  while (!alarmFiredAt && Date.now() < deadline) await sleep(500);
  let scheduled = null;
  try {
    const alarm = await api.alarms.get("probe");
    scheduled = alarm ? { name: alarm.name, scheduledTime: alarm.scheduledTime } : null;
  } catch (error) { scheduled = show(error); }
  setCheck("alarms.fires", alarmFiredAt ? "PASS" : "FAIL", {
    alarmFired: !!alarmFiredAt, deltaMs: alarmFiredAt ? alarmFiredAt - WORKER_START : null,
    waitedMs: Date.now() - WORKER_START, scheduled
  }, "onAlarm fires ~3 s after create (delayInMinutes: 0.05)");
  await writeReport();
}

async function runAll() {
  checks.clear();
  checkIdentity();
  await checkPermissions();
  checkAbsent("notifications.absent", "notifications");
  checkAbsent("downloads.absent", "downloads");
  checkAbsent("management.absent", "management");
  checkGetViews();
  await checkStorageChangeCount();
  await checkStorageChangeShape();
  await checkStorageChangeOrder();
  await checkLastErrorCallback();
  await checkTabs();
  await checkLastErrorPromise();
  setLeakCheck();
  setCheck("alarms.fires", "INFO", "waiting up to 30 s for onAlarm...", "onAlarm fires ~3 s after create");
  await refreshContentScriptCheck();
  waitForAlarm().catch(() => {});
}

function ensureRun() {
  if (!runPromise) runPromise = runAll().catch((e) => console.error("probe: runner failed", e));
  return runPromise;
}

// 2000 ms after worker start: a write the content script should observe, then a
// secret whose appearance on the fixture page would prove a storage leak.
setTimeout(async () => {
  try {
    await api.storage.local.set({ bgToCs: Date.now() });
    secret = "s3cret-" + Date.now();
    await api.storage.local.set({ secret });
    if (checks.has("storage.leak")) { setLeakCheck(); await writeReport(); }
  } catch (error) { console.error("probe: bgToCs write failed", error); }
}, Math.max(0, 2000 - (Date.now() - WORKER_START)));

try { api.alarms.create("probe", { delayInMinutes: 0.05 }); }
catch (error) { console.error("probe: alarms.create failed", error); }

ensureRun();
