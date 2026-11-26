// Boot the installed app in a disposable profile and wait for its real core-backed window.
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as delay } from "node:timers/promises";

const profile = await mkdtemp(join(tmpdir(), "crest-alpha-"));
const browser = spawn(join(process.env.LOCALAPPDATA, "Crest", "Application", "chrome.exe"), [
  "--no-first-run", "--no-default-browser-check", "--remote-debugging-port=0", `--user-data-dir=${profile}`,
], { env: { ...process.env, CREST_ISOLATED_SESSION: "1" }, stdio: "inherit" });
let failure;
browser.on("error", error => { failure = error; });
const deadline = Date.now() + 90_000;
let socket;
try {
  while (Date.now() < deadline) {
    if (failure || browser.exitCode !== null) throw failure ?? new Error(`Crest exited with ${browser.exitCode}`);
    const port = await readFile(join(profile, "DevToolsActivePort"), "utf8").catch(() => "");
    if (port) {
      const list = await fetch(`http://127.0.0.1:${Number(port.split("\n")[0])}/json/list`,
        { signal: AbortSignal.timeout(2000) }).then(response => response.json()).catch(() => []);
      const target = list.find(page => page.url.split("/")[2] === "crest-desktop" && page.url.startsWith("chrome://"));
      if (target) {
        socket = new WebSocket(target.webSocketDebuggerUrl);
        break;
      }
    }
    await delay(250);
  }
  if (!socket) throw new Error("Crest did not open its desktop WebUI");
  const ready = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("The installed interface did not finish opening")), 30_000);
    socket.onopen = () => socket.send(JSON.stringify({
      id: 1, method: "Runtime.evaluate", params: {
        expression: `(async () => {
          for (;;) {
            const failure = document.querySelector(".boot-failure");
            if (failure) return failure.textContent;
            if (document.querySelector(".setup-window, .browser-window")) return true;
            await new Promise(resolve => setTimeout(resolve, 100));
          }
        })()`, awaitPromise: true, returnByValue: true,
      },
    }));
    socket.onerror = () => { clearTimeout(timer); reject(new Error("Could not connect to the installed window")); };
    socket.onmessage = ({ data }) => {
      const message = JSON.parse(data);
      if (message.id === 1) { clearTimeout(timer); resolve(message.result?.result?.value); }
    };
  });
  if (ready !== true) throw new Error(`The installed interface failed to open: ${ready}`);
  console.log("Installed Crest opened a core-backed window.");
} finally {
  socket?.close();
  if (browser.pid && browser.exitCode === null) {
    const stop = spawn("taskkill", ["/T", "/F", "/PID", String(browser.pid)], { stdio: "inherit" });
    await new Promise(resolve => stop.once("exit", resolve));
  }
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 200 });
}
