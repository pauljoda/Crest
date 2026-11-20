import { cssVariables } from "@crest/design";
import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";

import { boot, type Session } from "./boot";
import { BrowserWindow } from "./shell/BrowserWindow";
import "./styles.css";

for (const [name, value] of Object.entries(cssVariables())) document.documentElement.style.setProperty(name, value);

const bridge = new URLSearchParams(location.search).get("bridge") ?? "ws://127.0.0.1:8787/core";

function App() {
  const [session, setSession] = useState<Session | null>(null);
  const [failure, setFailure] = useState<string | null>(null);
  useEffect(() => {
    boot(bridge).then((started) => {
      // Development builds expose the session for inspection from the console.
      if (import.meta.env.DEV) Object.assign(window, { crest: started });
      setSession(started);
    }, (error: unknown) => setFailure(String(error)));
  }, []);
  if (failure) return <div className="boot-failure">{failure}</div>;
  if (!session) return <div className="window-loading" />;
  return <BrowserWindow session={session} />;
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
