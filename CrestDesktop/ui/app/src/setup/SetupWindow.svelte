<script lang="ts" module>
  import type { TransitionConfig } from "svelte/transition";

  import { timed, transitionStyle, type Timing } from "../motion";

  /** BrowserSetupWindowMetrics: the narrowest window that keeps the steps beside the preview, and the preview's inset in the room. */
  const sideBySideWidth = 1120;
  const previewInset = 44;

  /**
   * BrowserSetupPageStack: a page arriving from the side the walk goes, the
   * one leaving to the other, `offset` percent of its width away.
   */
  function slide(_node: Element, { offset, timing }: { offset: number; timing: Timing }): TransitionConfig {
    const { duration, delay, easing } = timed(timing);
    return { duration, delay, easing, css: (_t, u) => `transform: translateX(${offset * u}%)` };
  }

  /** The CSS transitions that move `properties` on `timing`, as Motion animated each toward its target. */
  function transitions(properties: readonly string[], timing: Timing): string {
    return properties.map((property) => transitionStyle(property, timing)).join(", ");
  }
</script>

<script lang="ts">
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
  import { untrack } from "svelte";

  import { openHeldLaunch, type Session } from "../boot";
  import { openGettingStarted } from "../guide/guide";
  import { animatePose, reducesMotion } from "../motion";
  import CrestMark from "../shell/CrestMark.svelte";
  import WindowControls from "../shell/WindowControls.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useCoreVersion } from "../use-core";
  import HomePage from "./pages/HomePage.svelte";
  import SpacePage from "./pages/SpacePage.svelte";
  import SpacesPage from "./pages/SpacesPage.svelte";
  import { Paper, PaperRoom, SheetEdge } from "./paper";
  import { type SetupPage, setupWalk, type SetupStepName, stepAfter, stepBefore, stepOf, stepPage } from "./setup-walk";
  import SetupPreview, { usePreviewSpaces } from "./SetupPreview.svelte";
  import StepChips from "./StepChips.svelte";
  import { explanation } from "./use-setup-space.svelte";
  import "../settings/settings.css";
  import "./setup.css";

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
  let { session, entry, holdsLaunch, onOpened, onHandedOver, onCancel }: {
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
  } = $props();

  const draft = $derived.by(() => (useCoreVersion(session), session.core.state.setupDraft));
  // svelte-ignore state_referenced_locally
  const previewSpaces = usePreviewSpaces(session);
  const walk = setupWalk(DevicePlatform.windows.importsBrowsers, false);
  // Review & Customize Setup opens on the Spaces, as the Mac's manual setup entry does.
  let path = $state.raw<readonly SetupPage[]>(untrack(() => (entry.firstStep.name === "manualSetup" ? [stepPage("spaces")] : [])));
  const direction = { current: 1 };
  let shownSpaceId = $state<string | null>(null);
  let finishing = $state(false);
  let takingOver = $state(false);
  let error = $state<string | null>(null);
  let size = $state.raw({ width: innerWidth, height: innerHeight });

  $effect(() => {
    const resize = () => {
      size = { width: innerWidth, height: innerHeight };
    };
    addEventListener("resize", resize);
    return () => removeEventListener("resize", resize);
  });

  $effect(() => {
    const before = document.title;
    document.title = "Crest Setup";
    return () => {
      document.title = before;
    };
  });

  // Setup opens over the session's own Spaces, which the manual setup draft
  // takes from the first page, as the Mac's live setup begins it at once.
  $effect(() => {
    const [started, starting] = [session, entry];
    untrack(() => {
      void (async () => {
        try {
          await started.core.send(StartSetup({ workspaceId: started.workspaceId, entry: starting }));
          if (!started.core.state.setupDraft) await started.core.send(ShowSetupStep({ step: SetupStep.manualSetup }));
        } catch (failure) {
          error = explanation(failure);
        }
      })();
    });
  });

  // Setup takes the keyboard from the window it covers.
  let root = $state<HTMLDivElement>();
  $effect(() => {
    if (!holdsLaunch) root?.focus();
  });

  const firstSpaceId = $derived(draft?.spaces[0]?.spaceId ?? null);
  const shownId = $derived(shownSpaceId ?? firstSpaceId);
  const shownLook = $derived(draft?.spaces.find((space) => space.spaceId === shownId)?.customization.branding ?? null);
  const page = $derived(path.at(-1) ?? null);
  const current = $derived<SetupStepName | null>(path[0] ? stepOf(path[0]) : null);
  // The welcome keeps the first step's page ready beneath it, so Continue only moves things.
  const shownPage = $derived(page ?? stepPage(walk[0]));
  const shownStep = $derived(current ?? walk[0]);

  /** Opens a step's page in place of whatever is open, as Continue and the chips do, sliding the way the walk goes. */
  const go = (step: SetupStepName) => {
    direction.current = current === null || walk.indexOf(step) >= walk.indexOf(current) ? 1 : -1;
    if (step === "yourSpace") shownSpaceId = firstSpaceId;
    path = [stepPage(step)];
  };
  const openSpace = (spaceId: string) => {
    direction.current = 1;
    shownSpaceId = spaceId;
    path = [...path, { kind: "space", spaceId }];
  };
  const back = () => {
    direction.current = -1;
    if (path.length > 1) {
      path = path.slice(0, -1);
      return;
    }
    const before = current ? stepBefore(walk, current) : null;
    path = before ? [stepPage(before)] : [];
  };
  const finish = async () => {
    finishing = true;
    error = null;
    try {
      const changes = await session.core.send(FinishSetup({ windowId: session.windowId }));
      const finished = changes.find((change): change is SetupFinished => change.$kind === "SetupFinished");
      // The window opens on, or shows, the Space the core names for the Getting Started guide, and shows the guide there.
      const guideSpaceId = finished?.guideSpaceId ?? null;
      if (holdsLaunch) await openHeldLaunch(session, guideSpaceId);
      else if (guideSpaceId) await session.core.send(ShowSpace({ windowId: session.windowId, spaceId: guideSpaceId })).catch(() => undefined);
      if (guideSpaceId) await openGettingStarted(session, guideSpaceId);
      onOpened();
      // The browser window draws beneath first, as the Mac waits for it, then Setup hands over.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        takingOver = true;
      }));
    } catch (failure) {
      error = explanation(failure);
      finishing = false;
    }
  };
  const next = $derived(page?.kind === "step" ? stepAfter(walk, page.step) : null);
  const forward = () => {
    if (!page) go(walk[0]);
    else if (page.kind === "space") back();
    else if (next) go(next);
    else void finish();
  };
  const forwardTitle = $derived(!page || next ? "Continue" : page.kind === "space" ? "Done" : "Start Browsing");
  const forwardId = $derived(!page || next ? "setup-continue" : page.kind === "space" ? "setup-done" : "setup-start-browsing");

  // Return goes forward, as the Mac's default button, unless what has focus takes it.
  $effect(() => {
    const keyDown = (event: KeyboardEvent) => {
      if (event.key !== "Enter" || event.defaultPrevented || event.isComposing) return;
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("button, select, textarea, [role=dialog], [contenteditable]")) return;
      event.preventDefault();
      if (!finishing) forward();
    };
    addEventListener("keydown", keyDown);
    return () => removeEventListener("keydown", keyDown);
  });

  const narrow = $derived(size.width < sideBySideWidth);
  const stepsWidth = $derived(narrow ? size.width : Math.min(440, Math.max(380, size.width / 3)));
  const landing = $derived(path.length === 0 && !takingOver);
  const still = { duration: 0 };
  const sheetMotion = $derived(reducesMotion() ? still : tokens.onboardingSheet);
  const handOver = $derived(reducesMotion() ? still : tokens.onboardingHandOver);
  const pageKey = (shown: SetupPage) => (shown.kind === "space" ? `space-${shown.spaceId}` : shown.step);
  const preview = $derived(takingOver
    ? { x: -(stepsWidth + previewInset), y: -previewInset, opacity: 1 }
    : landing ? { x: size.width - stepsWidth, y: 0, opacity: 0 } : { x: 0, y: 0, opacity: 1 });

  // Setup fades into the browser window, which then takes over from it.
  $effect(() => {
    if (!takingOver || !root) return;
    const element = root;
    untrack(() => {
      void animatePose(element, { opacity: 1 }, { opacity: 0 }, handOver).finished.then(() => onHandedOver(), () => undefined);
    });
  });
</script>

<div bind:this={root} tabindex="-1" class={["setup-window", narrow && "narrow", takingOver && "taking-over"]}
  style:--steps-width="{stepsWidth}px">
  <PaperRoom look={shownLook} reducesMotion={reducesMotion()} />
  {#if !narrow}
    <div class="setup-preview" inert
      style:left="{stepsWidth + previewInset}px" style:top="{previewInset}px" style:right="{previewInset}px" style:bottom="{previewInset}px"
      style:transform="translate({preview.x}px, {preview.y}px)" style:opacity={preview.opacity}
      style:transition={transitions(["transform", "opacity"], takingOver ? handOver : sheetMotion)}>
      <div class="setup-preview-frame">
        <SetupPreview spaces={previewSpaces.current} shownSpaceId={shownId} />
      </div>
    </div>
  {/if}
  <div class="setup-sheet"
    style:width="{takingOver ? 0 : landing ? size.width : stepsWidth}px" style:opacity={takingOver ? 0 : 1}
    style:transition={transitions(["width", "opacity"], takingOver ? handOver : sheetMotion)}>
    <div class="setup-sheet-paper">
      <Paper />
      <div class="setup-landing" style:width="{size.width}px" inert={!landing}
        style:opacity={landing ? 1 : 0} style:transition={transitionStyle("opacity", sheetMotion)}>
        <CrestMark size={76} />
        <StepChips {walk} current={null} size="welcome" onOpen={go} />
        <h1 class="setup-welcome-title">Welcome to Crest</h1>
        <p class="setup-welcome-body">
          {walk.includes("bring") ? "Bring your tabs over, then set up your Spaces." : "Set up your Spaces, then make Crest home."}
        </p>
        {#if error}
          <p class="setup-error" role="alert">{error}</p>
        {/if}
        <div class="setup-welcome-actions">
          {#if onCancel}
            <button type="button" class="setup-button secondary large" data-testid="setup-cancel" onclick={onCancel}>
              Cancel
            </button>
          {/if}
          <button type="button" class="setup-button primary large" data-testid={landing ? "setup-continue" : undefined} onclick={forward}>
            Continue
          </button>
        </div>
      </div>
      <div class="setup-steps" style:width="{stepsWidth}px" inert={landing}
        style:opacity={landing ? 0 : 1} style:transition={transitionStyle("opacity", sheetMotion)}>
        <header class="setup-header">
          <StepChips {walk} current={shownStep} size="compact"
            onOpen={(step) => {
              if (!(path.length === 1 && current === step)) go(step);
            }} />
        </header>
        <div class="setup-page-stack" inert={finishing}>
          {#each [shownPage] as shown (pageKey(shown))}
            <div class="setup-page"
              in:slide={{ offset: direction.current >= 0 ? 100 : -100, timing: reducesMotion() ? still : tokens.onboardingStep }}
              out:slide={{ offset: direction.current >= 0 ? -100 : 100, timing: reducesMotion() ? still : tokens.onboardingStep }}>
              {#if shown.kind === "space"}
                <SpacePage {session} spaceId={shown.spaceId} title={null} />
              {:else if shown.step === "yourSpace"}
                <SpacePage {session} spaceId={firstSpaceId} title="Your Space" />
              {:else if shown.step === "spaces"}
                <SpacesPage {session} onOpenSpace={openSpace} />
              {:else if shown.step === "home"}
                <HomePage {session} />
              {/if}
            </div>
          {/each}
        </div>
        {#if error}
          <p class="setup-error setup-footer-error" role="alert">{error}</p>
        {/if}
        <footer class="setup-footer">
          <button type="button" class="setup-button secondary" data-testid="setup-back" disabled={finishing} onclick={back}>
            <SymbolIcon name="chevron.left" size={13} strokeWidth={2.5} />
            <span>Back</span>
          </button>
          {#if finishing && !takingOver}
            <span class="setup-progress" role="progressbar" aria-label="Starting Crest"></span>
          {/if}
          <span class="setup-footer-space"></span>
          <button type="button" class="setup-button primary" data-testid={landing ? undefined : forwardId} disabled={finishing}
            onclick={forward}>
            {forwardTitle}
          </button>
        </footer>
      </div>
    </div>
    {#if !narrow}
      <span class="setup-sheet-edge-place" style:opacity={landing ? 0 : 1} style:transition={transitionStyle("opacity", sheetMotion)}>
        <SheetEdge />
      </span>
    {/if}
  </div>
  <div class="setup-titlebar" aria-hidden="true"></div>
  {#if session.shell}
    <div class="setup-window-controls"><WindowControls shell={session.shell} /></div>
  {/if}
</div>
