<script lang="ts" module>
  import { reader } from "../reactive";
  import type { Guide } from "./guide";

  const versions = new WeakMap<Guide, () => number>();

  /** The guide's version, followed by the expression that reads it, as the view rendered again with each change. */
  function useGuideVersion(guide: Guide): number {
    let read = versions.get(guide);
    if (!read) {
      read = reader((listener) => guide.subscribe(listener), () => guide.version);
      versions.set(guide, read);
    }
    return read();
  }
</script>

<script lang="ts">
  import { PracticeTab, TabPlacement } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import type { Session } from "../boot";
  import { presence, reducesMotion, transitionStyle } from "../motion";
  import CrestMark from "../shell/CrestMark.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import Fits from "./Fits.svelte";
  import { chapters, guideFor, lessons } from "./guide";
  import PracticeWindow from "./PracticeWindow.svelte";
  import "../setup/setup.css";
  import "./guide.css";

  /**
   * BrowserGettingStartedView: the guide a first Setup opens, in a saved tab
   * that wears Crest's icon. A masthead, the chapter picker, and a practice
   * window running the real sidebar over a practice Space that keeps nothing,
   * with the tabs chapter's lessons beside it; one window keeps its identity
   * as its place and width change between chapters.
   */
  let { session, tabId }: { session: Session; tabId: string } = $props();

  const guide = $derived(guideFor(session, tabId));
  const chapter = $derived.by(() => (useGuideVersion(guide), guide.chapter));
  const practice = $derived.by(() => (useGuideVersion(guide), guide.practice));
  const lesson = $derived.by(() => (useGuideVersion(guide), guide.lesson));

  let root = $state<HTMLDivElement>();
  let size = $state.raw({ width: 0, height: 0 });
  $effect(() => {
    const element = root;
    if (!element) return;
    const measure = () => {
      size = { width: element.clientWidth, height: element.clientHeight };
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  });
  const wide = $derived(size.width >= 820);
  const padding = $derived(size.width < 600 ? 20 : 30);
  // The column is at most 1240 wide with its padding, as the Mac's frame.
  const stageWidth = $derived(Math.max(0, Math.min(size.width, 1240) - padding * 2));
  const height = $derived(Math.max(560, Math.min(680, size.height - 175)));

  const instructionsWidth = $derived(wide ? 280 : 220);
  const windowX = $derived(chapter.showsLessons && wide ? instructionsWidth + 28 : 0);
  const windowY = $derived(chapter.showsLessons && !wide ? 310 : 0);
  // The sidebar can overhang in the tabs lesson; Split View brings the whole window back.
  const windowWidth = $derived(chapter.showsLessons && wide ? Math.max(760, stageWidth - windowX) : stageWidth);
  const stage = $derived(reducesMotion() ? { duration: 0 } : tokens.guideStage);
  const fade = $derived(reducesMotion() ? { duration: 0 } : tokens.guideChapter);

  const next = $derived(lessons[lesson.number] ?? null);
</script>

{#snippet actions()}
  {#if lesson.kind === "pin"}
    <button type="button" class="setup-button primary" data-testid="guide-pin"
      onclick={() => practice?.place(PracticeTab.mail, TabPlacement.pinned)}>
      <SymbolIcon name="pin.fill" size={13} />Pin Gmail
    </button>
  {:else if lesson.kind === "save"}
    <button type="button" class="setup-button primary" data-testid="guide-save"
      onclick={() => practice?.place(PracticeTab.trail, TabPlacement.saved)}>
      <SymbolIcon name="bookmark.fill" size={13} />Save this tab
    </button>
  {:else if lesson.kind === "folders"}
    <span class="guide-actions-group">
      <button type="button" class="setup-button secondary" data-testid="guide-add-folder"
        onclick={() => void practice?.addFolder(false)}>
        <SymbolIcon name="folder.badge.plus" size={13} />Add folder
      </button>
      <button type="button" class="setup-button secondary" data-testid="guide-nest-folder"
        onclick={() => void practice?.addFolder(true)}>
        <SymbolIcon name="folder" size={13} />Nest a folder
      </button>
    </span>
  {:else if lesson.kind === "clear"}
    <span class="guide-hint">Use Clear on the line in the practice sidebar.</span>
  {/if}
{/snippet}

{#snippet nextButton()}
  <button type="button" class="setup-button secondary" data-testid="guide-next-lesson"
    onclick={() => (next ? guide.chooseLesson(next) : guide.chooseChapter(chapters[1]))}>
    {next ? "Next" : "Try Split View"}<SymbolIcon name="arrow.right" size={13} />
  </button>
{/snippet}

{#snippet lessonRow()}{@render actions()}<span class="guide-spacer"></span>{@render nextButton()}{/snippet}

{#snippet lessonStack()}{@render actions()}{@render nextButton()}{/snippet}

<div bind:this={root} class="getting-started" data-testid="getting-started">
  <div class="guide-column" style:padding="{padding}px" style:max-width="1240px">
    <header class="guide-masthead">
      <CrestMark size={24} />
      <span class="guide-masthead-title">Getting Started</span>
      <button type="button" class="guide-plain-button" data-testid="guide-reset" onclick={() => {
        guide.reset();
        guide.chooseLesson(lessons[0]);
      }}>
        <SymbolIcon name="arrow.counterclockwise" size={13} />Reset practice
      </button>
    </header>

    <div class="guide-chapters" role="tablist" aria-label="Chapters">
      {#each chapters as option (option.name)}
        <button type="button" role="tab" aria-selected={option.name === chapter.name}
          aria-label={option.pickerTitle} data-testid="guide-chapter-{option.name}"
          class={["forge-card guide-chapter", option.name === chapter.name && "selected"]}
          onclick={() => guide.chooseChapter(option)}>
          <span class="guide-chapter-number">{String(option.number).padStart(2, "0")}</span>
          <span class="guide-chapter-title">{option.pickerTitle}</span>
        </button>
      {/each}
    </div>

    <div class="guide-stage" style:height="{height + windowY}px">
      {#if chapter.showsLessons}
        <div class="guide-instructions"
          style:width="{wide ? instructionsWidth : stageWidth}px" style:height="{wide ? height : 290}px"
          in:presence={{ pose: { opacity: 0 }, timing: fade }} out:presence={{ pose: { opacity: 0 }, timing: fade }}>
          <div class="guide-heading">
            <h1>{chapter.title}</h1>
            <p>{chapter.introduction}</p>
          </div>
          <!-- The tabs chapter's lesson: its caps label and count, its title, what it teaches, and what it offers to do. -->
          <div class="guide-lesson">
            <div class="guide-lesson-label">
              <span class="guide-caps">Try it</span>
              <span class="guide-count">{lesson.number} / {lessons.length}</span>
            </div>
            <h2>{lesson.title}</h2>
            <p>{lesson.detail}</p>
            {#key lesson.kind}
              <Fits wide={lessonRow} narrow={lessonStack} />
            {/key}
          </div>
        </div>
      {/if}
      <!-- The window moves by its place, not a transform, so what its sidebar lifts and pops over stays under the pointer. -->
      <div class="guide-window-place"
        style:left="{windowX}px" style:top="{windowY}px" style:width="{windowWidth}px" style:height="{height}px"
        style:transition="{transitionStyle('left', stage)}, {transitionStyle('top', stage)}, {transitionStyle('width', stage)}">
        {#if practice}
          <PracticeWindow {practice} {chapter} width={windowWidth} transition={stage} />
        {/if}
      </div>
    </div>

    <footer class="guide-footer">
      <span>Practice changes affect only this example Space.</span>
      {#if chapter.number < chapters.length}
        <button type="button" class="guide-plain-button" data-testid="guide-next-chapter"
          onclick={() => guide.chooseChapter(chapters[chapter.number])}>
          Next chapter<SymbolIcon name="arrow.right" size={13} />
        </button>
      {:else}
        <strong>This guide stays in your Saved tabs.</strong>
      {/if}
    </footer>
  </div>
</div>
