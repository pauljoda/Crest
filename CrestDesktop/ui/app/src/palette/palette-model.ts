import {
  type AddressCompletion,
  ForgetPaletteChoices,
  type Intent,
  Navigate,
  NavigateTab,
  OpenAddress,
  OpenLinkInSplit,
  OpenTab,
  type PaletteAnswer,
  type PaletteCommand,
  type PaletteEntry,
  type PaletteRow,
  type PaletteScope,
  type PaletteSection,
  PaletteSuggestions,
  RecordPaletteChoice,
  RemoveHistoryAddress,
  RestoreArchivedTab,
  type SearchOffer,
  type SearchProvider,
  ShowTab,
  TabPlacement,
} from "@crest/contracts";
import { CoreRejection, type CrestCore } from "@crest/core-client";

import { settingsPages } from "../settings/catalog";
import { showSpace } from "../spaces/show-space";
import { CompletionEditing, completedText, continued } from "./completion";

/**
 * What the palette opens with: an empty field for a new tab, or the address
 * of the tab the window shows; or, embedded in a Start Page, an empty field
 * whose addresses open in that tab and which offers the window's commands
 * only once something is typed, as the Mac's Start Page palette does.
 */
export type PaletteMode =
  | { readonly kind: "newTab" }
  | { readonly kind: "editLocation"; readonly address: string }
  | { readonly kind: "startPage" };

/** Where Return opens a row that opens an address, as the keys held choose. */
export interface PaletteOpening {
  readonly name: "here" | "backgroundTab" | "newTab" | "splitView";
  /** What the selected row says while the keys are held, or null for here. */
  readonly title: string | null;
  readonly symbol: string;
}

const here: PaletteOpening = { name: "here", title: null, symbol: "arrow.turn.down.left" };
/**
 * The openings Windows offers, as the Mac's keys choose them with Ctrl for ⌘:
 * Ctrl opens in a tab behind, Ctrl+Shift in a new tab in front, and Shift
 * beside the tab in Split View. The Mac's ⌥ (Quick Window) waits for Quick
 * Windows here.
 */
const openings = {
  backgroundTab: { name: "backgroundTab", title: "Open in Background", symbol: "square.on.square" },
  newTab: { name: "newTab", title: "Open in New Tab", symbol: "plus.square.on.square" },
  splitView: { name: "splitView", title: "Open in Split View", symbol: "rectangle.split.2x1" },
} as const satisfies Record<string, PaletteOpening>;

/** The modifier keys that choose where a row opens. */
export interface HeldKeys {
  readonly control: boolean;
  readonly shift: boolean;
  readonly alt: boolean;
}

/** One row the palette shows, at its place in keyboard order. */
export interface PaletteItem {
  readonly index: number;
  readonly row: PaletteRow;
  readonly id: string;
}

/** The rows of one section, in the core's order. */
export interface PaletteGroupView {
  readonly section: PaletteSection;
  readonly items: readonly PaletteItem[];
}

/** What the palette needs of its window. */
export interface PaletteHost {
  readonly core: CrestCore;
  readonly windowId: string;
  readonly workspaceId: string;
  /** The Space the window shows, which the palette speaks for. */
  readonly spaceId: string;
  /** The tab the window shows there, or null. */
  readonly tabId: string | null;
  /** The live page of that tab, or null. */
  readonly pageId: string | null;
  /** The commands the palette may offer: those the window runs, with their titles. */
  readonly commands: readonly PaletteCommand[];
  /** Runs a command the person picked. */
  runCommand(name: string): void;
  /** Copies an answer the palette gives, such as the calculator's. */
  copy(text: string): void;
  /** Fetches search suggestions from the address the core names, or none where this host cannot. */
  fetchSuggestions?(address: string): Promise<readonly string[]>;
  /** Puts the palette away. */
  dismiss(): void;
  /** Opens Settings at the page the core names, where this host has Settings. */
  openSettings?(page: string): void;
}

/** The field the model edits: what it shows, and where the caret goes. */
export interface PaletteField {
  /** Replaces `start`–`end` of the field with `text` and puts the caret at its end. */
  applyCompletion(text: string, start: number, end: number): void;
  /** Replaces the field's whole text, as entering or leaving a scope does. */
  replaceText(text: string): void;
}

/** How long Return, Tab or Down wait for the answer to what was typed before they act on the rows shown. */
const keyWait = 300;
/** How long the palette waits on a keystroke before it fetches search suggestions. */
const suggestionDebounce = 250;

/**
 * The palette's rows, keyboard selection and the search provider or scope a
 * person narrowed it to, as the Mac's BrowserCommandPaletteModel keeps them.
 * The core ranks what the palette offers for each query; an answer that
 * arrives after a newer keystroke is dropped, so the latest query always
 * wins, and a key pressed before the answer for its text waits for it.
 */
export class PaletteModel {
  query: string;
  groups: readonly PaletteGroupView[] = [];
  items: readonly PaletteItem[] = [];
  selectedIndex = 0;
  /** Advances each time the keyboard moves the selection, so the list scrolls to it. */
  keyboardRevision = 0;
  activeProvider: SearchProvider | null = null;
  activeScope: PaletteScope | null = null;
  held: HeldKeys = { control: false, shift: false, alt: false };
  field: PaletteField | null = null;

  readonly editing = new CompletionEditing();
  #completionProposal: AddressCompletion | null = null;
  #offeredSearch: SearchOffer | null = null;
  #matchingProviders: readonly SearchProvider[] = [];
  #offeredScope: PaletteScope | null = null;
  #sequence = 0;
  #shownSequence = -1;
  #waitingKey: (() => void) | null = null;
  #keyTimer: ReturnType<typeof setTimeout> | undefined;
  #suggestionTimer: ReturnType<typeof setTimeout> | undefined;
  #listeners = new Set<() => void>();
  version = 0;

  constructor(readonly host: PaletteHost, readonly mode: PaletteMode) {
    this.query = mode.kind === "editLocation" ? mode.address : "";
    this.#requestAnswer();
  }

  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  #changed() {
    this.version++;
    for (const listener of this.#listeners) listener();
  }

  close() {
    clearTimeout(this.#keyTimer);
    clearTimeout(this.#suggestionTimer);
    this.#sequence++;
  }

  // MARK: - Offers

  get isUnscoped(): boolean {
    return this.activeProvider === null && this.activeScope === null;
  }

  /** The search provider Tab enters: one the text names by its shortcut even while a completion shows, else one it names once none does. */
  get providerOffer(): SearchProvider | null {
    const offer = this.#offeredSearch;
    if (!this.isUnscoped || !this.editing.isAtEnd || !offer) return null;
    return this.urlCompletion === null || offer.beatsCompletion ? offer.provider : null;
  }

  /** The providers the palette offers as chips while what is typed is one word, closest first. */
  get providerChips(): readonly SearchProvider[] {
    return this.isUnscoped ? this.#matchingProviders : [];
  }

  /** The scope Tab enters for what is typed, or null. */
  get scopeOffer(): PaletteScope | null {
    return this.isUnscoped && this.editing.isAtEnd && this.urlCompletion === null ? this.#offeredScope : null;
  }

  /** The completion the field shows: the core's for what is typed, or the last one while keystrokes still type into it. */
  get urlCompletion(): AddressCompletion | null {
    if (!this.isUnscoped || !this.editing.canPropose(this.query) || !this.#completionProposal) return null;
    return continued(this.#completionProposal, this.query);
  }

  /** Where Return opens the selected row while the person holds the keys they hold. */
  get selectedOpening(): PaletteOpening {
    const item = this.items[this.selectedIndex];
    return item ? this.openingFor(item.row) : here;
  }

  openingFor(row: PaletteRow): PaletteOpening {
    // The Start Page's palette opens only in its own tab.
    if (!row.kind.activation.opensWhereKeysChoose || this.mode.kind === "startPage") return here;
    const { control, shift, alt } = this.held;
    if (control && !shift && !alt) return openings.backgroundTab;
    if (control && shift && !alt) return openings.newTab;
    if (!control && shift && !alt && this.host.tabId) return openings.splitView;
    return here;
  }

  // MARK: - Editing

  /** Notes what the field holds and where its caret is. */
  updateEditing(text: string, selectionStart: number, selectionEnd: number, composing: boolean) {
    const couldPropose = this.editing.canPropose(this.query);
    this.editing.update(text, selectionStart, selectionEnd, composing);
    if (!composing && text !== this.query) {
      this.query = text;
      this.selectedIndex = 0;
      this.#requestAnswer();
    } else if (!composing && couldPropose !== this.editing.canPropose(this.query)) {
      // The core leads with the completion only while the field may show it,
      // so a caret that moves away asks again.
      this.#requestAnswer();
    }
    this.#changed();
  }

  rejectCompletion() {
    this.editing.reject();
    this.#changed();
  }

  /** Accepts the completion the field shows; false when none shows. */
  acceptCompletion(): boolean {
    const proposal = this.urlCompletion;
    if (!proposal || !this.field) return false;
    this.editing.reject();
    const adds = proposal.accepted === completedText(proposal);
    if (adds) this.field.applyCompletion(proposal.suffix, proposal.typed.length, proposal.typed.length);
    else this.field.applyCompletion(proposal.accepted, 0, proposal.typed.length);
    this.editing.reject();
    this.#changed();
    return true;
  }

  // MARK: - Keys

  /** Tab: enters the offered provider, else accepts the completion, else enters the offered scope, else moves down. */
  pressTab() {
    this.#waitForAnswer(() => {
      const provider = this.providerOffer;
      if (provider) return this.enterProvider(provider);
      if (this.acceptCompletion()) return;
      const scope = this.scopeOffer;
      if (scope) this.enterScope(scope);
      else this.moveSelection(1);
    });
  }

  pressReturn() {
    this.#waitForAnswer(() => this.activateSelected());
  }

  pressDown() {
    this.#waitForAnswer(() => this.moveSelection(1));
  }

  setHeld(held: HeldKeys) {
    if (held.control === this.held.control && held.shift === this.held.shift && held.alt === this.held.alt) return;
    this.held = held;
    this.#changed();
  }

  #waitForAnswer(key: () => void) {
    if (this.#shownSequence === this.#sequence) return key();
    this.#waitingKey = key;
    clearTimeout(this.#keyTimer);
    this.#keyTimer = setTimeout(() => this.#runWaitingKey(), keyWait);
  }

  #runWaitingKey() {
    clearTimeout(this.#keyTimer);
    const key = this.#waitingKey;
    if (!key) return;
    this.#waitingKey = null;
    // A key that waited too long acts on what is shown, whatever it answers.
    this.#shownSequence = this.#sequence;
    key();
  }

  // MARK: - Scopes

  enterProvider(provider: SearchProvider) {
    this.activeProvider = provider;
    this.activeScope = null;
    this.#narrowed("");
  }

  enterScope(scope: PaletteScope) {
    this.activeScope = scope;
    this.activeProvider = null;
    this.#narrowed("");
  }

  /** Leaves the search provider or scope, keeping what was typed. */
  leaveScope(): boolean {
    if (this.isUnscoped) return false;
    this.activeProvider = null;
    this.activeScope = null;
    this.#requestAnswer();
    this.field?.replaceText(this.query);
    this.#changed();
    return true;
  }

  #enterEntry(entry: PaletteEntry) {
    this.activeProvider = entry.provider;
    this.activeScope = entry.scope;
    this.#narrowed(entry.text);
  }

  #narrowed(text: string) {
    this.#completionProposal = null;
    this.editing.reject();
    this.query = text;
    this.selectedIndex = 0;
    this.field?.replaceText(text);
    this.#requestAnswer();
    this.#changed();
  }

  // MARK: - Selection

  moveSelection(offset: number) {
    this.editing.reject();
    if (this.#shownSequence === this.#sequence && this.items.length > 0) {
      this.selectedIndex = (this.selectedIndex + offset + this.items.length) % this.items.length;
      this.keyboardRevision++;
    }
    this.#changed();
  }

  /** Moves to the first row of the next or previous section. */
  moveSection(offset: number) {
    this.editing.reject();
    const current = this.groups.findIndex((group) => group.items.some((item) => item.index === this.selectedIndex));
    if (this.#shownSequence === this.#sequence && current >= 0) {
      const first = this.groups[(current + offset + this.groups.length) % this.groups.length].items[0];
      if (first) {
        this.selectedIndex = first.index;
        this.keyboardRevision++;
      }
    }
    this.#changed();
  }

  /** Hover selects a row, and puts a completion away; it never scrolls. */
  selectResult(index: number) {
    this.editing.reject();
    if (this.#shownSequence === this.#sequence && index >= 0 && index < this.items.length && index !== this.selectedIndex) {
      this.selectedIndex = index;
    }
    this.#changed();
  }

  /**
   * Forgets the selected row: a history row takes its page out of the
   * Space's history, and what the palette learned about the row goes. The
   * row the palette leads with is never forgotten this way.
   */
  forgetSelectedRow(): boolean {
    const row = this.items[this.selectedIndex]?.row;
    if (this.selectedIndex === 0 || !row || !(row.kind.forgetsFromHistory || row.reason?.name === "learned")) return false;
    const { core, workspaceId, spaceId, windowId } = this.host;
    if (row.kind.forgetsFromHistory && row.address) send(core, RemoveHistoryAddress({ workspaceId, spaceId, address: row.address }));
    send(core, ForgetPaletteChoices({ windowId, row, spaceId: null }));
    this.#requestAnswer();
    return true;
  }

  activateSelected() {
    const item = this.items[this.selectedIndex];
    if (item) this.activate(item.row);
  }

  /**
   * Runs `row` as its kind's activation does. One that closes the palette
   * has it remember the pick for what was typed and close; one that narrows
   * it to a scope leaves it open.
   */
  activate(row: PaletteRow) {
    if (this.#shownSequence !== this.#sequence) return;
    const typed = this.query;
    if (!this.#run(row) || !row.kind.activation.closesPalette) return;
    send(this.host.core, RecordPaletteChoice({ windowId: this.host.windowId, text: typed, row, spaceId: null }));
    this.host.dismiss();
  }

  #run(row: PaletteRow): boolean {
    const { core, windowId, workspaceId, spaceId } = this.host;
    switch (row.kind.activation.name) {
      case "switchesToTab":
        if (!row.tabId) return false;
        send(core, ShowTab({ windowId, spaceId, tabId: row.tabId }));
        return true;
      case "opensAddress":
      case "searches":
        return row.address ? this.#open(row.address, this.openingFor(row)) : false;
      case "runsCommand": {
        const command = row.command;
        if (!command) return false;
        // A command that opens or closes the palette itself keeps it; any other runs once it is away.
        if (command.name !== "newTab" && command.name !== "openLocation") this.host.dismiss();
        this.host.runCommand(command.name);
        return true;
      }
      case "showsSpace":
        if (!row.subjectId) return false;
        void showSpace(core, windowId, row.subjectId).catch((error: unknown) => {
          if (!(error instanceof CoreRejection)) throw error;
        });
        return true;
      case "reopensArchivedTab":
        if (!row.subjectId) return false;
        send(core, RestoreArchivedTab({ workspaceId, windowId, spaceId, tabId: row.subjectId }));
        return true;
      case "copiesAnswer":
        this.host.copy(row.title);
        return true;
      case "entersScope":
        if (row.scope) this.enterScope(row.scope);
        return false;
      case "opensSettingsPage":
        if (!row.settingsPage || !this.host.openSettings) return false;
        this.host.openSettings(row.settingsPage);
        return true;
      default:
        return false;
    }
  }

  /** Opens `address` where `opening` says, from the tab the palette opened over. */
  #open(address: string, opening: PaletteOpening): boolean {
    const { core, windowId, workspaceId, spaceId, tabId, pageId } = this.host;
    // The Start Page becomes the page it opens, as the Mac's navigates its tab.
    if (this.mode.kind === "startPage" && tabId) {
      send(core, NavigateTab({ workspaceId, spaceId, tabId, input: address }));
      return true;
    }
    if (opening.name === "backgroundTab") {
      send(core, OpenTab({
        workspaceId, windowId, spaceId, tabId: crypto.randomUUID(),
        content: { address, view: null, title: null }, placement: TabPlacement.current, afterTabId: tabId,
        shows: false, placesAsNewTab: true, savesInSavedFolder: true,
      }));
      return true;
    }
    // Beside the tab, in a split with it, as the core arranges it.
    if (opening.name === "splitView" && tabId) {
      send(core, OpenLinkInSplit({
        workspaceId, windowId, spaceId, tabId: crypto.randomUUID(), targetTabId: tabId, address, title: hostOf(address),
      }));
      return true;
    }
    if (opening.name === "newTab" || this.mode.kind === "newTab" || !tabId) {
      // The Start Page on show takes the address, or a new tab opens it, as the core decides.
      send(core, OpenAddress({ workspaceId, windowId, spaceId, tabId: crypto.randomUUID(), address, placesAsNewTab: true }));
      return true;
    }
    // Editing the location loads the address in the page the window shows,
    // or gives the tab it when it shows none yet.
    if (pageId) send(core, Navigate({ pageId, input: address }));
    else send(core, NavigateTab({ workspaceId, spaceId, tabId, input: address }));
    return true;
  }

  // MARK: - Answers

  #question(text: string, remote: readonly string[] = []) {
    // The Start Page's palette suggests no command until something is typed.
    const commands = this.mode.kind !== "startPage" || text.trim() !== "" ? this.host.commands : [];
    return PaletteSuggestions({
      windowId: this.host.windowId, text, commands, settingsPages: this.host.openSettings ? settingsPages : [], remote,
      provider: this.activeProvider, scope: this.activeScope, allowsCompletion: this.editing.canPropose(text),
      pasteboard: null, spaceId: null,
    });
  }

  /** Asks the core for the query's answer, then for the search suggestions it allows, each shown only while no later keystroke asked again. */
  #requestAnswer() {
    const asked = ++this.#sequence;
    const question = this.#question(this.query);
    clearTimeout(this.#suggestionTimer);
    void this.host.core.query(question).then((answer) => {
      if (asked !== this.#sequence) return;
      this.#show(answer, asked);
      const fetch = this.host.fetchSuggestions;
      if (!answer.suggestionAddress || !fetch) return;
      const address = answer.suggestionAddress;
      this.#suggestionTimer = setTimeout(async () => {
        try {
          const fetched = await fetch(address);
          if (asked !== this.#sequence || fetched.length === 0) return;
          const merged = await this.host.core.query({ ...question, remote: fetched });
          if (asked !== this.#sequence) return;
          const selected = this.items[this.selectedIndex]?.id;
          this.#show(merged, asked);
          const index = this.items.findIndex((item) => item.id === selected);
          if (index >= 0) this.selectedIndex = index;
          this.#changed();
        } catch {
          // The local rows are already shown; a failed fetch leaves them as they are.
        }
      }, suggestionDebounce);
    }).catch((error: unknown) => {
      // A refused question leaves the rows already shown; it is a bug worth seeing.
      console.error("The palette's question failed", error);
    });
  }

  #show(answer: PaletteAnswer, asked: number) {
    this.#shownSequence = asked;
    let index = 0;
    this.groups = answer.groups.map((group) => ({
      section: group.section,
      items: group.rows.map((row) => ({ index: index++, row, id: rowId(row) })),
    }));
    this.items = this.groups.flatMap((group) => group.items);
    this.#completionProposal = answer.completion;
    this.#offeredSearch = answer.offeredSearch;
    this.#matchingProviders = answer.matchingProviders;
    this.#offeredScope = answer.offeredScope;
    if (this.selectedIndex >= this.items.length) this.selectedIndex = 0;
    if (asked === this.#sequence && this.isUnscoped && answer.entry) this.#enterEntry(answer.entry);
    if (asked === this.#sequence && this.#waitingKey) this.#runWaitingKey();
    this.#changed();
  }
}

/** What a row stands for, so it keeps its identity while the results around it change. */
function rowId(row: PaletteRow): string {
  return [row.kind.name, row.subjectId, row.tabId, row.address, row.command?.name, row.title].join("\u0000");
}

/** Sends `intent`; a refusal changes nothing, as the Mac's palette ignores one. */
function send(core: CrestCore, intent: Intent) {
  void core.send(intent).catch((error: unknown) => {
    if (!(error instanceof CoreRejection)) throw error;
  });
}

/** The action title of a search provider: Ask for an assistant, else Search. */
export function providerActionTitle(provider: SearchProvider): string {
  return provider.kind.name === "assistant" ? `Ask ${provider.title}` : `Search ${provider.title}`;
}

/** The host an address names, which a tab opened beside another wears as its title until its page says. */
function hostOf(address: string): string {
  try {
    return new URL(address).host || address;
  } catch {
    return address;
  }
}
