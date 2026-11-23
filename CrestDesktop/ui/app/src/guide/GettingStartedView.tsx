import { type BrandColor, PracticeTab, TabPlacement, type TabState } from "@crest/contracts";
import { brand, motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { type MouseEvent, type ReactNode, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";

import type { Session } from "../boot";
import { Browsing } from "../browsing";
import { CrestMark } from "../shell/CrestMark";
import { PageColumns } from "../shell/PageColumns";
import { Sidebar, TabIcon } from "../shell/Sidebar";
import { SpaceIdentityIcon } from "../spaces/SpaceIdentity";
import { shortcutText } from "../shortcuts";
import { Symbol } from "../symbols";
import { useCoreVersion } from "../use-core";
import { type Chapter, chapters, type Guide, guideFor, lessons } from "./guide";
import type { Practice } from "./practice";
import "../setup/setup.css";
import "./guide.css";

/** The Mac's CrestBrandPalette coral, the practice's split ring. */
const coral: BrandColor = { red: brand.coral[0] / 255, green: brand.coral[1] / 255, blue: brand.coral[2] / 255, alpha: 1 };

/**
 * BrowserGettingStartedView: the guide a first Setup opens, in a saved tab
 * that wears Crest's icon. A masthead, the chapter picker, and a practice
 * window running the real sidebar over a practice Space that keeps nothing,
 * with the tabs chapter's lessons beside it; one window keeps its identity
 * as its place and width change between chapters.
 */
export function GettingStartedView({ session, tabId }: { session: Session; tabId: string }) {
  const guide = guideFor(session, tabId);
  useSyncExternalStore((listener) => guide.subscribe(listener), () => guide.version);
  useCoreVersion(session);
  const reducesMotion = useReducedMotion() ?? false;
  const { chapter, practice } = guide;

  const root = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState({ width: 0, height: 0 });
  useLayoutEffect(() => {
    const element = root.current;
    if (!element) return;
    const measure = () => setSize({ width: element.clientWidth, height: element.clientHeight });
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  const wide = size.width >= 820;
  const padding = size.width < 600 ? 20 : 30;
  // The column is at most 1240 wide with its padding, as the Mac's frame.
  const stageWidth = Math.max(0, Math.min(size.width, 1240) - padding * 2);
  const height = Math.max(560, Math.min(680, size.height - 175));

  const instructionsWidth = wide ? 280 : 220;
  const windowX = chapter.showsLessons && wide ? instructionsWidth + 28 : 0;
  const windowY = chapter.showsLessons && !wide ? 310 : 0;
  // The sidebar can overhang in the tabs lesson; Split View brings the whole window back.
  const windowWidth = chapter.showsLessons && wide ? Math.max(760, stageWidth - windowX) : stageWidth;
  const stage = reducesMotion ? { duration: 0 } : tokens.guideStage;
  const fade = reducesMotion ? { duration: 0 } : tokens.guideChapter;

  return (
    <div ref={root} className="getting-started" data-testid="getting-started">
      <div className="guide-column" style={{ padding, maxWidth: 1240 }}>
        <header className="guide-masthead">
          <CrestMark size={24} />
          <span className="guide-masthead-title">Getting Started</span>
          <button type="button" className="guide-plain-button" data-testid="guide-reset" onClick={() => {
            guide.reset();
            guide.chooseLesson(lessons[0]);
          }}>
            <Symbol name="arrow.counterclockwise" size={13} />
            Reset practice
          </button>
        </header>

        <div className="guide-chapters" role="tablist" aria-label="Chapters">
          {chapters.map((option) => (
            <button key={option.name} type="button" role="tab" aria-selected={option.name === chapter.name}
              aria-label={option.pickerTitle} data-testid={`guide-chapter-${option.name}`}
              className={`forge-card guide-chapter${option.name === chapter.name ? " selected" : ""}`}
              onClick={() => guide.chooseChapter(option)}>
              <span className="guide-chapter-number">{String(option.number).padStart(2, "0")}</span>
              <span className="guide-chapter-title">{option.pickerTitle}</span>
            </button>
          ))}
        </div>

        <div className="guide-stage" style={{ height: height + windowY }}>
          <AnimatePresence initial={false}>
            {chapter.showsLessons && (
              <motion.div key="lessons" className="guide-instructions"
                style={{ width: wide ? instructionsWidth : stageWidth, height: wide ? height : 290 }}
                initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={fade}>
                <div className="guide-heading">
                  <h1>{chapter.title}</h1>
                  <p>{chapter.introduction}</p>
                </div>
                <TabLesson guide={guide} />
              </motion.div>
            )}
          </AnimatePresence>
          {/* The window moves by its place, not a transform, so what its sidebar lifts and pops over stays under the pointer. */}
          <motion.div className="guide-window-place" initial={false}
            animate={{ left: windowX, top: windowY, width: windowWidth }} style={{ height }} transition={stage}>
            {practice && <PracticeWindow practice={practice} chapter={chapter} width={windowWidth} transition={stage} />}
          </motion.div>
        </div>

        <footer className="guide-footer">
          <span>Practice changes affect only this example Space.</span>
          {chapter.number < chapters.length ? (
            <button type="button" className="guide-plain-button" data-testid="guide-next-chapter"
              onClick={() => guide.chooseChapter(chapters[chapter.number])}>
              Next chapter
              <Symbol name="arrow.right" size={13} />
            </button>
          ) : (
            <strong>This guide stays in your Saved tabs.</strong>
          )}
        </footer>
      </div>
    </div>
  );
}

/** The tabs chapter's lesson: its caps label and count, its title, what it teaches, and what it offers to do. */
function TabLesson({ guide }: { guide: Guide }) {
  const { lesson, practice } = guide;
  const next = lessons[lesson.number] ?? null;
  const actions = (() => {
    switch (lesson.kind) {
      case "pin":
        return (
          <button type="button" className="setup-button primary" data-testid="guide-pin"
            onClick={() => practice?.place(PracticeTab.mail, TabPlacement.pinned)}>
            <Symbol name="pin.fill" size={13} />
            Pin Gmail
          </button>
        );
      case "save":
        return (
          <button type="button" className="setup-button primary" data-testid="guide-save"
            onClick={() => practice?.place(PracticeTab.trail, TabPlacement.saved)}>
            <Symbol name="bookmark.fill" size={13} />
            Save this tab
          </button>
        );
      case "folders":
        return (
          <span className="guide-actions-group">
            <button type="button" className="setup-button secondary" data-testid="guide-add-folder"
              onClick={() => void practice?.addFolder(false)}>
              <Symbol name="folder.badge.plus" size={13} />
              Add folder
            </button>
            <button type="button" className="setup-button secondary" data-testid="guide-nest-folder"
              onClick={() => void practice?.addFolder(true)}>
              <Symbol name="folder" size={13} />
              Nest a folder
            </button>
          </span>
        );
      case "clear":
        return <span className="guide-hint">Use Clear on the line in the practice sidebar.</span>;
    }
  })();
  const nextButton = (
    <button type="button" className="setup-button secondary" data-testid="guide-next-lesson"
      onClick={() => (next ? guide.chooseLesson(next) : guide.chooseChapter(chapters[1]))}>
      {next ? "Next" : "Try Split View"}
      <Symbol name="arrow.right" size={13} />
    </button>
  );
  return (
    <div className="guide-lesson">
      <div className="guide-lesson-label">
        <span className="guide-caps">Try it</span>
        <span className="guide-count">{lesson.number} / {lessons.length}</span>
      </div>
      <h2>{lesson.title}</h2>
      <p>{lesson.detail}</p>
      <Fits key={lesson.kind} wide={<>{actions}<span className="guide-spacer" />{nextButton}</>}
        narrow={<>{actions}{nextButton}</>} />
    </div>
  );
}

/**
 * SwiftUI's ViewThatFits over a row and a stack: the row where it fits on
 * one line, the stack where it doesn't, decided again as the room changes.
 * An unseen copy of the row, at its own width, says how much it needs.
 */
function Fits({ wide, narrow }: { wide: ReactNode; narrow: ReactNode }) {
  const box = useRef<HTMLDivElement>(null);
  const probe = useRef<HTMLDivElement>(null);
  const [fits, setFits] = useState(true);
  useLayoutEffect(() => {
    const room = box.current;
    const needs = probe.current;
    if (!room || !needs) return;
    const check = () => setFits(needs.scrollWidth <= room.clientWidth + 0.5);
    check();
    // The room changes with the guide's width; what the row needs, as its faces load.
    const observer = new ResizeObserver(check);
    observer.observe(room);
    observer.observe(needs);
    return () => observer.disconnect();
  }, []);
  return (
    <div ref={box} className="guide-fits">
      {fits ? <div className="guide-actions row">{wide}</div> : <div className="guide-actions stack">{narrow}</div>}
      <div ref={probe} className="guide-actions row guide-fits-probe" aria-hidden inert>{wide}</div>
    </div>
  );
}

/**
 * BrowserGettingStartedPracticeWindow: a small window, three dots and a
 * title over the practice's sidebar and its document area, where the shown
 * tab's card stands, or a split's cards side by side.
 */
function PracticeWindow({ practice, chapter, width, transition }: {
  practice: Practice;
  chapter: Chapter;
  width: number;
  transition: object;
}) {
  const session = practice.session;
  const browsing = useMemo(() => new Browsing(session), [session]);
  const space = practice.space;
  const window = practice.window;
  const roomy = width >= 620;
  const sidebarWidth = roomy ? (chapter.showsSplit ? 220 : 285) : null;
  if (!space || !window) return null;
  const shownTabId = practice.shownTabId;
  const shownTabs = new Map(window.shownTabs.flatMap((shown) => (shown.tabId ? [[shown.spaceId, shown.tabId] as const] : [])));
  const cards = practice.cards;
  return (
    <div className="practice-window" data-practice-window data-testid="practice-window">
      <div className="practice-window-chrome">
        <span className="practice-window-dots" aria-hidden>
          <span style={{ background: rgb(brand.coral) }} />
          <span style={{ background: rgb(brand.butter) }} />
          <span style={{ background: rgb(brand.sage) }} />
        </span>
        <span className="practice-window-title"><Symbol name="leaf" size={12} />Practice window</span>
        <span className="practice-window-brand">Crest</span>
      </div>
      <div className="practice-window-body">
        <motion.div className="practice-sidebar-column" initial={false}
          animate={sidebarWidth === null ? { flexGrow: 1 } : { width: sidebarWidth, flexGrow: 0 }} transition={transition}>
          <div className="practice-sidebar-header">
            <SpaceIdentityIcon symbol={space.settings.symbol} branding={space.settings.look} size={30} />
            <span>
              <strong>Practice</strong>
              <small>Your example Space</small>
            </span>
          </div>
          <Sidebar session={session} browsing={browsing} space={space} spaces={[space]} shownTabId={shownTabId}
            shownTabs={shownTabs} page={null} pagesByTab={new Map()} showsNavigation={false} permission={null}
            downloads={null} onDialog={() => {}} docked onToggleDock={() => {}}
            practice={{ openExampleTab: () => practice.openExampleTab() }} />
        </motion.div>
        {(roomy || chapter.showsSplit) && (
          <div className="practice-document-area">
            {cards.tabIds.length === 0 ? (
              <div className="practice-unavailable" data-testid="practice-cleared">
                <Symbol name="sun.max" size={34} />
                <strong>Open tabs cleared</strong>
                <span>Your pinned and saved tabs are still in the sidebar.</span>
              </div>
            ) : (
              <PageColumns windowId={session.windowId} cards={cards} focusedTabId={shownTabId} accent={coral} interactive
                onFocus={(tabId, byPointer) => !byPointer && practice.focus(tabId)} onResize={() => Promise.resolve()}
                renderCard={(tabId) => {
                  const tab = space.tabs.find((candidate) => candidate.id === tabId);
                  return tab ? <PracticeDocument practice={practice} tab={tab} showsSplit={chapter.showsSplit} /> : null;
                }} />
            )}
          </div>
        )}
      </div>
    </div>
  );
}

/** A practice tab's example page: its icon and title over what it holds, or the split lesson it teaches. */
function PracticeDocument({ practice, tab, showsSplit }: { practice: Practice; tab: TabState; showsSplit: boolean }) {
  const isPacking = tab.id === practice.tabId(PracticeTab.packing) || tab.title === PracticeTab.packing.title;
  return (
    <div className="practice-document" data-testid={`practice-document-${tab.id}`}
      onClick={() => practice.focus(tab.id)}>
      <div className="practice-document-title">
        <TabIcon session={practice.session} tab={tab} pageId={null} size={18} />
        <span>{tab.displayTitle}</span>
      </div>
      <hr />
      <div className="practice-document-body">
        {showsSplit ? <SplitInstructions practice={practice} tab={tab} isPacking={isPacking} /> : isPacking ? (
          <>
            <h3 className="practice-display packing">Packing list</h3>
            {["Walking shoes", "Water bottle", "Trail map"].map((item) => (
              <span key={item} className="practice-check"><Symbol name="checkmark.circle" size={13} />{item}</span>
            ))}
          </>
        ) : (
          <>
            <span className="practice-art sage"><Symbol name="mountain.2" size={54} strokeWidth={0.75} /></span>
            <h3 className="practice-display trail">Weekend trail guide</h3>
            <p className="practice-secondary">Distance: 4.2 miles<br />Duration: 2 hours<br />Route: lakeside loop</p>
          </>
        )}
      </div>
      <span className="practice-document-label">{showsSplit ? "Split View practice" : "Example page"}</span>
    </div>
  );
}

/** What the Split View chapter teaches on each card: to make a split, to rearrange its cards, and to focus one. */
function SplitInstructions({ practice, tab, isPacking }: { practice: Practice; tab: TabState; isPacking: boolean }) {
  const bindings = practice.session.core.state.shortcuts?.bindings ?? [];
  const keys = (name: string) => {
    const bound = bindings.find((binding) => binding.command.name === name)?.keys;
    return bound ? shortcutText(bound) : null;
  };
  const pair = (left: string, right: string, does: string) => {
    const [first, second] = [keys(left), keys(right)];
    return first && second ? <p className="practice-shortcut">{first} / {second} {does}</p> : null;
  };
  if (practice.cards.tabIds.length < 2) {
    return (
      <>
        <span className="practice-art sky"><Symbol name="rectangle.split.2x1" size={44} strokeWidth={0.75} /></span>
        <h3 className="practice-display">Drag another tab here</h3>
        <p className="practice-lead">Drag Packing list from the sidebar onto this page. Or right-click it and choose Split with Current Tab.</p>
        <span>
          <button type="button" className="setup-button primary" data-testid="guide-make-split"
            onClick={(event) => {
              event.stopPropagation();
              void practice.makeSplit();
            }}>
            <Symbol name="plus.rectangle.on.rectangle" size={13} />
            Add Packing list
          </button>
        </span>
      </>
    );
  }
  const stop = (run: () => void) => (event: MouseEvent) => {
    event.stopPropagation();
    run();
  };
  if (isPacking) {
    return (
      <>
        <span className="practice-art sage"><Symbol name="arrow.left.arrow.right" size={32} strokeWidth={1.25} /></span>
        <h3 className="practice-display small">Rearrange cards</h3>
        <p className="practice-secondary">Move this card to either side.</p>
        <Fits key={tab.id} wide={<MoveButtons practice={practice} tab={tab} stop={stop} />}
          narrow={<MoveButtons practice={practice} tab={tab} stop={stop} />} />
        {pair("moveSplitCardLeft", "moveSplitCardRight", "moves the focused card.")}
      </>
    );
  }
  return (
    <>
      <span className="practice-art sky"><Symbol name="cursorarrow" size={32} strokeWidth={1.25} /></span>
      <h3 className="practice-display small">Choose the focused card</h3>
      <p className="practice-secondary">Click either card. Its border shows which page receives your keyboard commands.</p>
      <span>
        <button type="button" className="setup-button secondary" data-testid={`guide-focus-${tab.id}`}
          onClick={stop(() => practice.focus(tab.id))}>
          <Symbol name="cursorarrow.click" size={13} />
          Focus this card
        </button>
      </span>
      {pair("focusPreviousSplitCard", "focusNextSplitCard", "focuses the previous or next card.")}
      <hr />
      <p className="practice-secondary small">
        To focus by hovering, turn on Focus follows pointer under Split View in Settings → Tabs. Shortcuts can also be changed in Settings.
      </p>
    </>
  );
}

function MoveButtons({ practice, tab, stop }: {
  practice: Practice;
  tab: TabState;
  stop: (run: () => void) => (event: MouseEvent) => void;
}) {
  return (
    <>
      <button type="button" className="setup-button secondary" disabled={!practice.canMove(tab.id, -1)}
        data-testid="guide-move-left" onClick={stop(() => void practice.move(tab.id, -1))}>
        <Symbol name="arrow.left" size={13} />
        Move left
      </button>
      <button type="button" className="setup-button secondary" disabled={!practice.canMove(tab.id, 1)}
        data-testid="guide-move-right" onClick={stop(() => void practice.move(tab.id, 1))}>
        <Symbol name="arrow.right" size={13} />
        Move right
      </button>
    </>
  );
}

function rgb(color: readonly number[]): string {
  return `rgb(${color.join(" ")})`;
}
