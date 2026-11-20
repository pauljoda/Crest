import { cssVariables } from "@crest/design";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import type { SetupEntry } from "@crest/contracts";

import { boot, type Session } from "./boot";
import { setupLauncher } from "./commands";
import { SetupWindow } from "./setup/SetupWindow";
import { BrowserWindow } from "./shell/BrowserWindow";
import "./styles.css";

for (const [name, value] of Object.entries(cssVariables())) document.documentElement.style.setProperty(name, value);

const bridge = new URLSearchParams(location.search).get("bridge") ?? "ws://127.0.0.1:8787/core";

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  // Setup over the window: a launch held for first-run Setup shows it until it finishes, then the window opens beneath it
  // and Setup fades into it; Settings opens it over the window that is already open.
  const [setup, setSetup] = useState<{ entry: SetupEntry; held: boolean; handingOver: boolean } | null>(null);
  useEffect(() => {
    setupLauncher.open = (entry) => setSetup((current) => current ?? { entry, held: false, handingOver: false });
  }, []);
  useEffect(() => {
    boot(bridge).then((started) => {
      // Development builds expose the session for inspection from the console.
      if (import.meta.env.DEV) Object.assign(window, { crest: started });
      const held = started.setup.current;
      setSetup(held ? { entry: held.entry, held: true, handingOver: false } : null);
      setSession(started);
    }, (error: unknown) => setFailure(String(error)));
  }, []);
  if (failure) return <div className="boot-failure">{failure}</div>;
  if (!session) return <div className="window-loading" />;
  return (
    <>
      {!(setup?.held && !setup.handingOver) && <BrowserWindow session={session} />}
      {setup && (
        <SetupWindow session={session} entry={setup.entry} holdsLaunch={setup.held}
          onOpened={() => setSetup((current) => current && { ...current, handingOver: true })}
          onHandedOver={() => setSetup(null)}
          onCancel={setup.held ? null : () => setSetup(null)} />
      )}
    </>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
