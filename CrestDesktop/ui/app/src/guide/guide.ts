import { NativeView, OpenTab, ShowTab, TabPlacement, TabSurface } from "@crest/contracts";

import type { Session } from "../boot";
import { residentNativeTabs } from "../native-tabs";
import { Practice } from "./practice";

/** A chapter of the guide, as the Mac's BrowserGettingStartedChapter, in the order its picker shows them. */
export interface Chapter {
  readonly number: number;
  readonly name: "tabs" | "splitView";
  /** The chapter's name in the picker, where it is short. */
  readonly pickerTitle: string;
  readonly title: string;
  readonly introduction: string;
  /** Whether the chapter teaches lessons in a column beside the practice window. */
  readonly showsLessons: boolean;
  /** Whether the practice window shows a Split View; arriving at such a chapter starts the practice over. */
  readonly showsSplit: boolean;
}

export const chapters: readonly Chapter[] = [
  {
    number: 1, name: "tabs", pickerTitle: "Tabs & folders", title: "Tabs and folders",
    introduction: "Pinned apps stay at the top, saved tabs above the line, and open tabs below it.",
    showsLessons: true, showsSplit: false,
  },
  {
    number: 2, name: "splitView", pickerTitle: "Split View", title: "Split View",
    introduction: "View pages side by side, change focus, and rearrange cards.",
    showsLessons: false, showsSplit: true,
  },
];

/**
 * A lesson of the tabs chapter, as the Mac's BrowserGettingStartedLesson
 * teaches it with a pointer. Clear's lesson names Alt, which holds Clear All
 * here as Option does on the Mac.
 */
export interface Lesson {
  readonly number: number;
  readonly kind: "pin" | "save" | "folders" | "clear";
  readonly title: string;
  readonly detail: string;
}

export const lessons: readonly Lesson[] = [
  {
    number: 1, kind: "pin", title: "Pin everyday apps",
    detail: "Pinned tabs live at the top and are for your everyday apps. Right-click Gmail and choose Pin Tab, or use the button below.",
  },
  {
    number: 2, kind: "save", title: "Save a tab",
    detail: "Saved tabs stay below your pins until you delete them. Save A weekend away and watch it move above the line.",
  },
  {
    number: 3, kind: "folders", title: "Create folders and nested folders",
    detail: "Folders can hold tabs and other folders. Add Weekends, then put Ideas inside it. You can also use folders below the line for open tabs.",
  },
  {
    number: 4, kind: "clear", title: "Clear open tabs",
    detail: "Below the line are open tabs. They close automatically on your Space's cleanup schedule. Clear sends all but the tab you're on to Archive; hold Alt to clear them all. Your pinned and saved tabs stay put.",
  },
];

/**
 * One guide tab's state, as the Mac's BrowserGettingStartedState lives for
 * its native tab: the practice, and the chapter and lesson open. It outlives
 * the view, so the guide comes back as it was left when its tab shows again,
 * and goes, practice and all, once the tab is gone.
 */
export class Guide {
  practice: Practice | null = null;
  chapter: Chapter = chapters[0];
  lesson: Lesson = lessons[0];
  /** Counts each change, for the view to follow. */
  version = 0;
  readonly #listeners = new Set<() => void>();
  #opening = 0;
  #closed = false;

  constructor(private readonly base: Session) {
    void this.#open();
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  }

  /** Starts the practice over. The practice on show stays until its successor opens, so the window never empties. */
  reset() {
    void this.#open();
  }

  chooseLesson(lesson: Lesson) {
    this.lesson = lesson;
    this.#changed();
  }

  /** Opens a chapter; arriving at Split View starts the practice over, so its split begins from the example tabs. */
  chooseChapter(chapter: Chapter) {
    if (chapter.showsSplit && chapter.name !== this.chapter.name) this.reset();
    this.chapter = chapter;
    this.#changed();
  }

  close() {
    this.#closed = true;
    void this.practice?.close();
    this.practice = null;
  }

  async #open() {
    const attempt = ++this.#opening;
    const opened = await Practice.open(this.base).catch(() => null);
    if (!opened) return;
    if (this.#closed || attempt !== this.#opening) {
      void opened.close();
      return;
    }
    const previous = this.practice;
    this.practice = opened;
    this.#changed();
    void previous?.close();
  }

  #changed() {
    this.version++;
    for (const listener of this.#listeners) listener();
  }
}

/** The guide each guide tab shows, by tab, while the tab is still in the workspace. */
const guides = new Map<string, Guide>();

/** The guide `tabId` shows, made the first time it shows. */
export function guideFor(session: Session, tabId: string): Guide {
  const known = guides.get(tabId);
  if (known) return known;
  const guide = new Guide(session);
  guides.set(tabId, guide);
  residentNativeTabs.add(tabId);
  // The guide goes with its tab: closed, archived or deleted.
  const stop = session.core.state.subscribe(() => {
    const workspace = session.core.state.workspaces.get(session.workspaceId);
    const holds = workspace && [...workspace.spaces.values()].some((space) => space.tabs.some((tab) => tab.id === tabId));
    if (holds) return;
    stop();
    guides.delete(tabId);
    residentNativeTabs.delete(tabId);
    guide.close();
  });
  return guide;
}

/**
 * Opens the Getting Started guide in `spaceId`, as the Mac's finished Setup
 * does: the guide tab the Space already keeps, or a new one among its saved
 * tabs, shown in the window. A private window opens none.
 */
export async function openGettingStarted(session: Session, spaceId: string) {
  const workspace = session.core.state.workspaces.get(session.workspaceId);
  const space = workspace?.spaces.get(spaceId);
  if (!space || workspace?.kind.isPrivate) return;
  const existing = space.tabs.find((tab) => tab.surface === TabSurface.nativeView && tab.nativeView === NativeView.gettingStarted);
  await session.core.send(existing
    ? ShowTab({ windowId: session.windowId, spaceId, tabId: existing.id })
    : OpenTab({
      workspaceId: session.workspaceId, windowId: session.windowId, spaceId, tabId: crypto.randomUUID(),
      content: { address: null, view: NativeView.gettingStarted, title: null }, placement: TabPlacement.saved,
      afterTabId: null, shows: true, placesAsNewTab: false, savesInSavedFolder: false,
    })).catch(() => undefined);
}
