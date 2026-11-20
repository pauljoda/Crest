import {
  DevicePlatform,
  FinishSetup,
  type SetupEntry,
  type SetupFinished,
  SetupStep,
  ShowSetupStep,
  ShowSpace,
  StartSetup,
} from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useReducedMotion, type Variants } from "motion/react";
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
import { SetupPreview, usePreviewSpaces } from "./SetupPreview";
import { StepChips } from "./StepChips";
import { explanation } from "./use-setup-space";
import "../settings/settings.css";
import "./setup.css";

/** BrowserSetupWindowMetrics: the narrowest window that keeps the steps beside the preview, and the preview's inset in the room. */
const sideBySideWidth = 1120;
const previewInset = 44;

/** BrowserSetupPageStack: a page arriving from the side the walk goes, the one leaving to the other. */
const slide: Variants = {
  enter: (direction: number) => ({ x: direction >= 0 ? "100%" : "-100%" }),
  center: { x: 0 },
  exit: (direction: number) => ({ x: direction >= 0 ? "-100%" : "100%" }),
};

/**
 * Crest Setup, as the Mac's BrowserSetupWindowContent draws it: in the
 * window a first launch holds back, or over a window Settings opens it on.
 * The welcome across the whole window, then the steps on a sheet of paper
 * at the leading third, beside a preview of Crest in the room the shown
 * Space's look colors. Every page edits Setup's draft in the core, which
 * takes effect only when Start Browsing finishes Setup: the window opens or
 * shows beneath, the preview moves to where its window stands, and Setup
 * fades into it. Over a window that is already open, the welcome offers
 * Cancel, since Setup covers it here where the Mac's has a window of its own.
 */
export function SetupWindow({ session, entry, holdsLaunch, onOpened, onHandedOver, onCancel }: {
  session: Session;
  entry: SetupEntry;
  /** Whether this window is a launch's held back for Setup, which opens once it finishes. */
  holdsLaunch: boolean;
  /** The window is open and shows what Setup made, for the browser window to draw beneath Setup. */
  onOpened: () => void;
  /** Setup has faded into the browser window. */
  onHandedOver: () => void;
  /** Leaves Setup without finishing, or null where it can't be left. */
  onCancel: (() => void) | null;
}) {
  useCoreVersion(session);
  const reducesMotion = useReducedMotion() ?? false;
  const draft = session.core.state.setupDraft;
  const previewSpaces = usePreviewSpaces(session);
  const walk = setupWalk(DevicePlatform.windows.importsBrowsers, false);
  // Review & Customize Setup opens on the Spaces, as the Mac's manual setup entry does.
  const [path, setPath] = useState<readonly SetupPage[]>(() => (entry.firstStep.name === "manualSetup" ? [stepPage("spaces")] : []));
  const direction = useRef(1);
  const [shownSpaceId, setShownSpaceId] = useState<string | null>(null);
  const [finishing, setFinishing] = useState(false);
  const [takingOver, setTakingOver] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [size, setSize] = useState(() => ({ width: innerWidth, height: innerHeight }));

  useEffect(() => {
    const resize = () => setSize({ width: innerWidth, height: innerHeight });
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
    void (async () => {
      try {
        await session.core.send(StartSetup({ workspaceId: session.workspaceId, entry }));
        if (!session.core.state.setupDraft) await session.core.send(ShowSetupStep({ step: SetupStep.manualSetup }));
      } catch (failure) {
        setError(explanation(failure));
      }
    })();
  }, [session, entry]);

  // Setup takes the keyboard from the window it covers.
  const root = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!holdsLaunch) root.current?.focus();
  }, [holdsLaunch]);

  const firstSpaceId = draft?.spaces[0]?.spaceId ?? null;
  const shownId = shownSpaceId ?? firstSpaceId;
  const shownLook = draft?.spaces.find((space) => space.spaceId === shownId)?.customization.branding ?? null;
  const page = path.at(-1) ?? null;
  const current: SetupStepName | null = path[0] ? stepOf(path[0]) : null;
  // The welcome keeps the first step's page ready beneath it, so Continue only moves things.
  const shownPage = page ?? stepPage(walk[0]);
  const shownStep = current ?? walk[0];

  /** Opens a step's page in place of whatever is open, as Continue and the chips do, sliding the way the walk goes. */
  const go = (step: SetupStepName) => {
    direction.current = current === null || walk.indexOf(step) >= walk.indexOf(current) ? 1 : -1;
    if (step === "yourSpace") setShownSpaceId(firstSpaceId);
    setPath([stepPage(step)]);
  };
  const openSpace = (spaceId: string) => {
    direction.current = 1;
    setShownSpaceId(spaceId);
    setPath((pages) => [...pages, { kind: "space", spaceId }]);
  };
  const back = () => {
    direction.current = -1;
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
      // Windows draws no Getting Started view yet, so the window opens on, or shows, the Space it would have shown.
      const guideSpaceId = finished?.guideSpaceId ?? null;
      if (holdsLaunch) await openHeldLaunch(session, guideSpaceId);
      else if (guideSpaceId) await session.core.send(ShowSpace({ windowId: session.windowId, spaceId: guideSpaceId })).catch(() => undefined);
      onOpened();
      // The browser window draws beneath first, as the Mac waits for it, then Setup hands over.
      requestAnimationFrame(() => requestAnimationFrame(() => setTakingOver(true)));
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

  const narrow = size.width < sideBySideWidth;
  const stepsWidth = narrow ? size.width : Math.min(440, Math.max(380, size.width / 3));
  const landing = path.length === 0 && !takingOver;
  const still = { duration: 0 };
  const sheetMotion = reducesMotion ? still : tokens.onboardingSheet;
  const handOver = reducesMotion ? still : tokens.onboardingHandOver;
  let content = null;
  let pageKey: string;
  if (shownPage.kind === "space") {
    pageKey = `space-${shownPage.spaceId}`;
    content = <SpacePage session={session} spaceId={shownPage.spaceId} title={null} />;
  } else {
    pageKey = shownPage.step;
    if (shownPage.step === "yourSpace") content = <SpacePage session={session} spaceId={firstSpaceId} title="Your Space" />;
    else if (shownPage.step === "spaces") content = <SpacesPage session={session} onOpenSpace={openSpace} />;
    else if (shownPage.step === "home") content = <HomePage session={session} />;
  }

  return (
    <motion.div ref={root} tabIndex={-1} className={`setup-window${narrow ? " narrow" : ""}${takingOver ? " taking-over" : ""}`}
      style={{ "--steps-width": `${stepsWidth}px` } as CSSProperties}
      initial={false} animate={{ opacity: takingOver ? 0 : 1 }} transition={handOver}
      onAnimationComplete={() => {
        if (takingOver) onHandedOver();
      }}>
      <PaperRoom look={shownLook} reducesMotion={reducesMotion} />
      {!narrow && (
        <motion.div className="setup-preview" inert
          style={{ left: stepsWidth + previewInset, top: previewInset, right: previewInset, bottom: previewInset }}
          initial={false}
          animate={takingOver
            ? { x: -(stepsWidth + previewInset), y: -previewInset, opacity: 1 }
            : landing ? { x: size.width - stepsWidth, y: 0, opacity: 0 } : { x: 0, y: 0, opacity: 1 }}
          transition={takingOver ? handOver : sheetMotion}>
          <div className="setup-preview-frame">
            <SetupPreview spaces={previewSpaces} shownSpaceId={shownId} />
          </div>
        </motion.div>
      )}
      <motion.div className="setup-sheet" initial={false}
        animate={{ width: takingOver ? 0 : landing ? size.width : stepsWidth, opacity: takingOver ? 0 : 1 }}
        transition={takingOver ? handOver : sheetMotion}>
        <div className="setup-sheet-paper">
          <Paper />
          <motion.div className="setup-landing" style={{ width: size.width }} inert={!landing || undefined}
            initial={false} animate={{ opacity: landing ? 1 : 0 }} transition={sheetMotion}>
                <CrestMark size={76} />
                <StepChips walk={walk} current={null} size="welcome" onOpen={go} />
                <h1 className="setup-welcome-title">Welcome to Crest</h1>
                <p className="setup-welcome-body">
                  {walk.includes("bring") ? "Bring your tabs over, then set up your Spaces." : "Set up your Spaces, then make Crest home."}
                </p>
                {error && <p className="setup-error" role="alert">{error}</p>}
                <div className="setup-welcome-actions">
                  {onCancel && (
                    <button type="button" className="setup-button secondary large" data-testid="setup-cancel" onClick={onCancel}>
                      Cancel
                    </button>
                  )}
                  <button type="button" className="setup-button primary large" data-testid={landing ? "setup-continue" : undefined} onClick={forward}>
                    Continue
                  </button>
                </div>
          </motion.div>
          <motion.div className="setup-steps" style={{ width: stepsWidth }} inert={landing || undefined}
            initial={false} animate={{ opacity: landing ? 0 : 1 }} transition={sheetMotion}>
                <header className="setup-header">
                  <StepChips walk={walk} current={shownStep} size="compact"
                    onOpen={(step) => {
                      if (!(path.length === 1 && current === step)) go(step);
                    }} />
                </header>
                <div className="setup-page-stack" inert={finishing || undefined}>
                  <AnimatePresence initial={false} custom={direction.current}>
                    <motion.div key={pageKey} className="setup-page" custom={direction.current} variants={slide}
                      initial="enter" animate="center" exit="exit" transition={reducesMotion ? still : tokens.onboardingStep}>
                      {content}
                    </motion.div>
                  </AnimatePresence>
                </div>
                {error && <p className="setup-error setup-footer-error" role="alert">{error}</p>}
                <footer className="setup-footer">
                  <button type="button" className="setup-button secondary" data-testid="setup-back" disabled={finishing} onClick={back}>
                    <Symbol name="chevron.left" size={13} strokeWidth={2.5} />
                    <span>Back</span>
                  </button>
                  {finishing && !takingOver && <span className="setup-progress" role="progressbar" aria-label="Starting Crest" />}
                  <span className="setup-footer-space" />
                  <button type="button" className="setup-button primary" data-testid={landing ? undefined : forwardId} disabled={finishing}
                    onClick={forward}>
                    {forwardTitle}
                  </button>
                </footer>
          </motion.div>
        </div>
        {!narrow && (
          <motion.span className="setup-sheet-edge-place" initial={false} animate={{ opacity: landing ? 0 : 1 }} transition={sheetMotion}>
            <SheetEdge />
          </motion.span>
        )}
      </motion.div>
      <div className="setup-titlebar" aria-hidden />
      {session.shell && <div className="setup-window-controls"><WindowControls shell={session.shell} /></div>}
    </motion.div>
  );
}
