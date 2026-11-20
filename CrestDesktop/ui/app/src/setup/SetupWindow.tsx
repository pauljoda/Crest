import {
  DevicePlatform,
  FinishSetup,
  type SetupFinished,
  SetupStep,
  ShowSetupStep,
  StartSetup,
} from "@crest/contracts";
import { type CSSProperties, useEffect, useRef, useState } from "react";

import { openHeldLaunch, type Session } from "../boot";
import { CrestMark } from "../shell/CrestMark";
import { WindowControls } from "../shell/WindowControls";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { HomePage } from "./pages/HomePage";
import { SpacePage } from "./pages/SpacePage";
import { SpacesPage } from "./pages/SpacesPage";
import { Paper, PaperRoom, SheetEdge } from "./paper";
import { type SetupPage, setupWalk, type SetupStepName, stepAfter, stepBefore, stepOf, stepPage } from "./setup-walk";
import { StepChips } from "./StepChips";
import { explanation } from "./use-setup-space";
import "../settings/settings.css";
import "./setup.css";

/** BrowserSetupWindowMetrics: the narrowest window that keeps the steps beside the preview. */
const sideBySideWidth = 1120;

/**
 * Crest Setup, as the Mac's BrowserSetupWindowContent draws it in the
 * window a first launch holds back: the welcome across the whole window,
 * then the steps on a sheet of paper at the leading third, beside the room
 * the shown Space's look colors. Every page edits Setup's draft in the core,
 * which takes effect only when Start Browsing finishes Setup and opens the
 * window the launch held.
 */
export function SetupWindow({ session, onFinished }: { session: Session; onFinished: () => void }) {
  useCoreVersion(session);
  const held = useRef(session.setup.current);
  const draft = session.core.state.setupDraft;
  const walk = setupWalk(DevicePlatform.windows.importsBrowsers, false);
  const [path, setPath] = useState<readonly SetupPage[]>([]);
  const [shownSpaceId, setShownSpaceId] = useState<string | null>(null);
  const [finishing, setFinishing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [width, setWidth] = useState(() => innerWidth);

  useEffect(() => {
    const resize = () => setWidth(innerWidth);
    addEventListener("resize", resize);
    return () => removeEventListener("resize", resize);
  }, []);

  useEffect(() => {
    const before = document.title;
    document.title = "Crest Setup";
    return () => {
      document.title = before;
    };
  }, []);

  // Setup opens over the session's own Spaces, which the manual setup draft
  // takes from the first page, as the Mac's live setup begins it at once.
  useEffect(() => {
    const entry = held.current?.entry;
    if (!entry) return;
    void (async () => {
      try {
        await session.core.send(StartSetup({ workspaceId: session.workspaceId, entry }));
        if (!session.core.state.setupDraft) await session.core.send(ShowSetupStep({ step: SetupStep.manualSetup }));
      } catch (failure) {
        setError(explanation(failure));
      }
    })();
  }, [session]);

  const firstSpaceId = draft?.spaces[0]?.spaceId ?? null;
  const shown = draft?.spaces.find((space) => space.spaceId === (shownSpaceId ?? firstSpaceId)) ?? null;
  const page = path.at(-1) ?? null;
  const current: SetupStepName | null = path[0] ? stepOf(path[0]) : null;

  /** Opens a step's page in place of whatever is open, as Continue and the chips do. */
  const go = (step: SetupStepName) => {
    if (step === "yourSpace") setShownSpaceId(firstSpaceId);
    setPath([stepPage(step)]);
  };
  const openSpace = (spaceId: string) => {
    setShownSpaceId(spaceId);
    setPath((pages) => [...pages, { kind: "space", spaceId }]);
  };
  const back = () => {
    if (path.length > 1) {
      setPath((pages) => pages.slice(0, -1));
      return;
    }
    const before = current ? stepBefore(walk, current) : null;
    setPath(before ? [stepPage(before)] : []);
  };
  const finish = async () => {
    setFinishing(true);
    setError(null);
    try {
      const changes = await session.core.send(FinishSetup({ windowId: session.windowId }));
      const finished = changes.find((change): change is SetupFinished => change.$kind === "SetupFinished");
      // Windows draws no Getting Started view yet, so the window opens on the Space it would have shown.
      await openHeldLaunch(session, finished?.guideSpaceId ?? null);
      onFinished();
    } catch (failure) {
      setError(explanation(failure));
      setFinishing(false);
    }
  };
  const next = page?.kind === "step" ? stepAfter(walk, page.step) : null;
  const forward = () => {
    if (!page) go(walk[0]);
    else if (page.kind === "space") back();
    else if (next) go(next);
    else void finish();
  };
  const forwardTitle = !page || next ? "Continue" : page.kind === "space" ? "Done" : "Start Browsing";
  const forwardId = !page || next ? "setup-continue" : page.kind === "space" ? "setup-done" : "setup-start-browsing";

  // Return goes forward, as the Mac's default button, unless what has focus takes it.
  const forwardRef = useRef(forward);
  forwardRef.current = finishing ? () => {} : forward;
  useEffect(() => {
    const keyDown = (event: globalThis.KeyboardEvent) => {
      if (event.key !== "Enter" || event.defaultPrevented) return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("button, select, textarea, [role=dialog], [contenteditable]")) return;
      event.preventDefault();
      forwardRef.current();
    };
    addEventListener("keydown", keyDown);
    return () => removeEventListener("keydown", keyDown);
  }, []);

  const narrow = width < sideBySideWidth;
  const stepsWidth = narrow ? width : Math.min(440, Math.max(380, width / 3));
  const landing = path.length === 0;
  let content = null;
  if (page?.kind === "space") content = <SpacePage key={page.spaceId} session={session} spaceId={page.spaceId} title={null} />;
  else if (page?.step === "yourSpace") content = <SpacePage key="your-space" session={session} spaceId={firstSpaceId} title="Your Space" />;
  else if (page?.step === "spaces") content = <SpacesPage session={session} onOpenSpace={openSpace} />;
  else if (page?.step === "home") content = <HomePage session={session} />;

  return (
    <div className={`setup-window${narrow ? " narrow" : ""}`} style={{ "--steps-width": `${stepsWidth}px` } as CSSProperties}>
      <PaperRoom look={shown?.customization.branding ?? null} />
      <div className={`setup-sheet${landing ? " landing" : ""}`}>
        <Paper />
        {landing ? (
          <div className="setup-landing">
            <CrestMark size={76} />
            <StepChips walk={walk} current={null} size="welcome" onOpen={go} />
            <h1 className="setup-welcome-title">Welcome to Crest</h1>
            <p className="setup-welcome-body">
              {walk.includes("bring") ? "Bring your tabs over, then set up your Spaces." : "Set up your Spaces, then make Crest home."}
            </p>
            {error && <p className="setup-error" role="alert">{error}</p>}
            <div className="setup-welcome-actions">
              <button type="button" className="setup-button primary large" data-testid="setup-continue" onClick={forward}>
                Continue
              </button>
            </div>
          </div>
        ) : (
          <div className="setup-steps">
            <header className="setup-header">
              <StepChips walk={walk} current={current} size="compact"
                onOpen={(step) => {
                  if (!(path.length === 1 && current === step)) go(step);
                }} />
            </header>
            <div className="setup-page" inert={finishing || undefined}>{content}</div>
            {error && <p className="setup-error setup-footer-error" role="alert">{error}</p>}
            <footer className="setup-footer">
              <button type="button" className="setup-button secondary" data-testid="setup-back" disabled={finishing} onClick={back}>
                <Symbol name="chevron.left" size={13} strokeWidth={2.5} />
                <span>Back</span>
              </button>
              {finishing && <span className="setup-progress" role="progressbar" aria-label="Starting Crest" />}
              <span className="setup-footer-space" />
              <button type="button" className="setup-button primary" data-testid={forwardId} disabled={finishing} onClick={forward}>
                {forwardTitle}
              </button>
            </footer>
          </div>
        )}
        {!landing && !narrow && <SheetEdge />}
      </div>
      <div className="setup-titlebar" aria-hidden />
      {session.shell && <div className="setup-window-controls"><WindowControls shell={session.shell} /></div>}
    </div>
  );
}
