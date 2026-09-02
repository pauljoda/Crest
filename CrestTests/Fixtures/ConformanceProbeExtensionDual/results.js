"use strict";

// Crest Conformance Probe -- results page. Renders the report the background
// worker stores under storage.local["__report"], and re-renders whenever that
// key changes so alarm/content-script results appear without a reload.

const api = globalThis.chrome ?? globalThis.browser;
const REPORT_KEY = "__report";

const el = {
  meta: document.getElementById("meta"),
  tally: document.getElementById("tally"),
  rows: document.getElementById("rows"),
  raw: document.getElementById("raw"),
  copy: document.getElementById("copy"),
  copied: document.getElementById("copied")
};

let current = null;

function pretty(value) {
  if (typeof value === "string") return value;
  if (value === undefined) return "undefined";
  try {
    return JSON.stringify(value, null, 2);
  } catch (error) {
    return String(value);
  }
}

function cell(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function render(report) {
  current = report;
  if (!report) {
    el.meta.textContent = "No report in storage.local yet. Reload the extension, then reopen this page.";
    el.raw.textContent = "";
    return;
  }

  el.meta.textContent = "";
  const lines = [
    ["Probe version", report.probeVersion],
    ["Report context", report.context],
    ["Page context", "page (results.html)"],
    ["Ran at", report.ranAt],
    ["Worker start", report.workerStart],
    ["User agent", report.browser]
  ];
  for (const [label, value] of lines) {
    const row = document.createElement("div");
    const strong = document.createElement("b");
    strong.textContent = label + ": ";
    row.appendChild(strong);
    row.appendChild(document.createTextNode(String(value === undefined ? "-" : value)));
    el.meta.appendChild(row);
  }

  const checks = Array.isArray(report.checks) ? report.checks : [];
  const count = (status) => checks.filter((c) => c.status === status).length;
  el.tally.textContent = "";
  for (const status of ["PASS", "FAIL", "INFO"]) {
    const span = document.createElement("span");
    span.className = status;
    span.textContent = `${status}: ${count(status)}`;
    el.tally.appendChild(span);
  }

  el.rows.textContent = "";
  for (const item of checks) {
    const tr = document.createElement("tr");
    tr.appendChild(cell("td", "name", item.name));
    tr.appendChild(cell("td", "status " + (item.status || "INFO"), item.status || "INFO"));

    const observed = cell("td", "observed");
    const pre = document.createElement("pre");
    pre.textContent = pretty(item.observed);
    observed.appendChild(pre);
    tr.appendChild(observed);

    const expected = cell("td", "expected", item.expected === undefined ? "-" : String(item.expected));
    if (item.note) {
      const note = cell("span", "note", item.note);
      expected.appendChild(note);
    }
    tr.appendChild(expected);
    el.rows.appendChild(tr);
  }

  el.raw.textContent = pretty(report);
}

async function load() {
  try {
    const stored = await api.storage.local.get(REPORT_KEY);
    render(stored ? stored[REPORT_KEY] : null);
  } catch (error) {
    el.meta.textContent = "storage.local.get failed: " + (error && error.message ? error.message : String(error));
  }
}

try {
  api.storage.onChanged.addListener((changes) => {
    if (Object.prototype.hasOwnProperty.call(changes || {}, REPORT_KEY)) {
      const change = changes[REPORT_KEY];
      if (change && change.newValue) render(change.newValue);
      else load();
    }
  });
} catch (error) {
  console.error("probe results: onChanged listener failed", error);
}

el.copy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(pretty(current));
    el.copied.textContent = "Copied.";
  } catch (error) {
    el.copied.textContent = "Clipboard blocked -- select the JSON below instead.";
  }
  setTimeout(() => {
    el.copied.textContent = "";
  }, 4000);
});

load();
// Safety net for hosts that drop storage.onChanged on extension pages.
setInterval(load, 5000);
