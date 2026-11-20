import { type CoreReply, CoreStatus, type CoreTransport } from "./transport";

/** What Crest's shell calls into the interface (crest_desktop_ui.h). */
interface ShellCallbacks {
  crestCoreReply?: (id: number, status: number, bytes: string) => void;
  crestCoreChanges?: (status: number, bytes: string) => void;
  crestEnginePresentation?: (bytes: string) => void;
  crestUnavailable?: (feature: number) => void;
  crestWindowState?: (state: ShellFrame) => void;
  crestShortcut?: (command: string) => void;
  crestPageKept?: (command: string) => void;
  crestCloseRequested?: (last: boolean, stack: readonly string[], pages: readonly string[]) => void;
  crestEngineNotice?: (message: string, kind: ShellNoticeKind) => void;
  crestWheel?: (phase: number, momentumPhase: number, deltaX: number, deltaY: number, x: number, y: number, time: number) => void;
}

/**
 * A precision touchpad's scroll over the interface with the phases the system
 * gave it, which the page's wheel events leave out: blink's
 * WebMouseWheelEvent phase flags, the DOM wheel event's deltas, the place in
 * the interface, all in CSS pixels, and when, in seconds on the engine's clock.
 */
export interface ShellWheel {
  readonly phase: number;
  readonly momentumPhase: number;
  readonly deltaX: number;
  readonly deltaY: number;
  readonly x: number;
  readonly y: number;
  readonly time: number;
}

/** What an engine notice says it is, as the Mac's EngineNoticeKind does. */
export type ShellNoticeKind = "link" | "confirmation";

type ShellWindow = Window & ShellCallbacks & { chrome?: { send?: (message: string, args: unknown[]) => void } };

/** The window around the interface, which the interface draws the buttons of. */
export interface ShellFrame {
  readonly maximized: boolean;
  readonly fullscreen: boolean;
  /** Whether this is the window in use. */
  readonly active: boolean;
}

/** Who the shell says this interface is. */
export interface ShellHello {
  readonly window: string;
  readonly userData: string;
  readonly frame?: ShellFrame;
  /** Whether this is the window a launch opens before the core names the saved window it is. */
  readonly launch?: boolean;
  /** Whether a precision touchpad's phases arrive (`onWheel`), as an engine that predates them never says. */
  readonly wheelPhases?: boolean;
}

/** What the interface asks of its window. */
export type ShellWindowAction =
  | "minimize"
  | "maximize"
  | "new"
  /** Asks the window to close, as Alt+F4 does; the interface hears `onCloseRequested`. */
  | "requestClose"
  /** Closes the window once the interface has told the core. */
  | "close";

/**
 * A key the window binds to one of its commands, and who answers it while a
 * focused page or field uses it too, as the core's shortcut preference says.
 */
export interface ShellShortcut {
  /** The command's name, which `onShortcut` hears. */
  readonly command: string;
  /** The key's Windows virtual-key code, as Chromium's accelerators match keys. */
  readonly key: number;
  readonly control: boolean;
  readonly shift: boolean;
  readonly alt: boolean;
  /** The command runs before a focused page sees the key. */
  readonly beforePage: boolean;
  /** A quick second press of keys a page kept runs the command. */
  readonly secondPress: boolean;
  /** The keys edit text, so a focused page or field sees them first. */
  readonly yieldsToText: boolean;
}

/**
 * What a fetch brought: the response's status, 0 when none arrived; its text,
 * null unless a 2xx response brought UTF-8; its validators; and whether it
 * grew past the longest list the core keeps.
 */
/** What a fetch is for: a filter list the core asked for, or the search engine's suggestions for what was typed. */
export type ShellFetchPurpose = "filterList" | "searchSuggestions";

export interface ShellFetched {
  readonly status: number;
  readonly text: string | null;
  readonly entityTag: string | null;
  readonly lastModified: string | null;
  readonly tooLarge: boolean;
}

/**
 * One item of a menu the shell runs as Windows' own context menus: a
 * separator, or an item the person may choose by its `id`, with the keys
 * its command answers to shown beside it, or a submenu.
 */
export type ShellMenuItem =
  | { readonly separator: true }
  | {
    readonly id?: string;
    readonly title: string;
    readonly enabled?: boolean;
    readonly checked?: boolean;
    readonly shortcut?: { readonly key: number; readonly control: boolean; readonly shift: boolean; readonly alt: boolean };
    readonly submenu?: readonly ShellMenuItem[];
  };

const shellWindow = window as ShellWindow;

/**
 * The bridge Crest's Chromium gives the interface it draws: the core lives
 * in the browser process, the engine is Chromium's own binding, and each
 * window's pages are surface embeds the interface places itself. Calls are
 * WebUI messages carrying the contract's bytes, base64 encoded.
 */
export class ShellTransport implements CoreTransport {
  onChanges?: (reply: CoreReply) => void;
  onCommand?: (engine: bigint, command: Uint8Array) => void;
  onPresentation?: (presentation: Uint8Array) => void;
  onUnavailable?: (feature: number) => void;
  /** Chromium showed a toast, such as "Link copied", which the window shows as a notice. */
  onNotice?: (message: string, kind: ShellNoticeKind) => void;
  /** A key the shell claimed, by the command it runs. */
  onShortcut?: (command: string) => void;
  /**
   * A focused page kept the keys of `command`, which runs on a second press;
   * null once that is over, by a second press or a key the page let go.
   */
  onPageKept?: (command: string | null) => void;
  /**
   * The window was asked to close. `last` says no other window stays open;
   * `stack` is every window's identity, front first; `pages` are the pages
   * the window shows. The interface answers with `window("close")`, or the
   * window closes on its own after a moment.
   */
  onCloseRequested?: (last: boolean, stack: readonly string[], pages: readonly string[]) => void;
  /** A precision touchpad's scroll over the interface, with its phases. */
  onWheel?: (wheel: ShellWheel) => void;

  #nextId = 1;
  #pending = new Map<number, (reply: CoreReply) => void>();
  #frame: ShellFrame = { maximized: false, fullscreen: false, active: true };
  #frameListeners = new Set<() => void>();

  /** Whether the interface runs inside Crest's Chromium. */
  static available(): boolean {
    return location.protocol === "chrome:" && typeof shellWindow.chrome?.send === "function";
  }

  constructor() {
    shellWindow.crestCoreReply = (id, status, bytes) => {
      const resolve = this.#pending.get(id);
      this.#pending.delete(id);
      resolve?.({ status, bytes: decode(bytes) });
    };
    shellWindow.crestCoreChanges = (status, bytes) => this.onChanges?.({ status, bytes: decode(bytes) });
    shellWindow.crestEnginePresentation = (bytes) => this.onPresentation?.(decode(bytes));
    shellWindow.crestUnavailable = (feature) => this.onUnavailable?.(feature);
    shellWindow.crestWindowState = (state) => this.#setFrame(state);
    shellWindow.crestShortcut = (command) => this.onShortcut?.(command);
    shellWindow.crestPageKept = (command) => this.onPageKept?.(command || null);
    shellWindow.crestCloseRequested = (last, stack, pages) => this.onCloseRequested?.(last, stack, pages);
    shellWindow.crestEngineNotice = (message, kind) => this.onNotice?.(message, kind);
    shellWindow.crestWheel = (phase, momentumPhase, deltaX, deltaY, x, y, time) =>
      this.onWheel?.({ phase, momentumPhase, deltaX, deltaY, x, y, time });
  }

  async hello(): Promise<ShellHello> {
    const reply = await this.#call("hello");
    const hello = JSON.parse(new TextDecoder().decode(reply.bytes)) as ShellHello;
    if (hello.frame) this.#setFrame(hello.frame);
    return hello;
  }

  /** The window's state now, for drawing its buttons. */
  get frame(): ShellFrame {
    return this.#frame;
  }

  /** Hears every change to `frame`; answers the call that stops it. */
  subscribeFrame(listener: () => void): () => void {
    this.#frameListeners.add(listener);
    return () => this.#frameListeners.delete(listener);
  }

  /** Hands the shell the keys this window binds now, replacing earlier ones. */
  shortcuts(shortcuts: readonly ShellShortcut[]) {
    return this.#call("shortcuts", JSON.stringify(shortcuts));
  }

  create(fingerprint: Uint8Array, configuration: Uint8Array) {
    return this.#call("create", encode(fingerprint), encode(configuration));
  }

  dispatch(intent: Uint8Array) {
    return this.#call("dispatch", encode(intent));
  }

  query(query: Uint8Array) {
    return this.#call("query", encode(query));
  }

  /** The shell drains the core itself on every wake and sends the batch. */
  drain(): Promise<CoreReply> {
    return Promise.resolve({ status: CoreStatus.ok, bytes: Uint8Array.of(0) });
  }

  endTurn(): Promise<CoreReply> {
    return Promise.resolve({ status: CoreStatus.ok, bytes: new Uint8Array() });
  }

  registerEngine(fingerprint: Uint8Array, registration: Uint8Array) {
    return this.#call("registerEngine", encode(fingerprint), encode(registration));
  }

  report(): Promise<CoreReply> {
    throw new Error("Chromium's binding reports to the core itself.");
  }

  ask(): Promise<CoreReply> {
    throw new Error("Chromium's binding asks the core itself.");
  }

  /** A page request, answered by the page's binding at once. */
  request(request: Uint8Array) {
    return this.#call("request", encode(request));
  }

  /** The surface embed identity of a page's contents, or empty without one. */
  async embed(page: string): Promise<string> {
    const reply = await this.#call("embed", page);
    return new TextDecoder().decode(reply.bytes);
  }

  /** Acts on this window, or opens a new one. */
  window(action: ShellWindowAction): Promise<CoreReply> {
    return this.#call("window", action);
  }

  /**
   * Where the file of the download `prompt` asks about goes: the Downloads
   * folder under a name no file has, or the person's choice in the system's
   * Save dialog when `asks`. Null when they cancel or no folder takes it;
   * `taken` when another window already answers the question.
   */
  async downloadDestination(prompt: string, suggestedFilename: string, asks: boolean):
    Promise<{ readonly path: string | null } | { readonly taken: true }> {
    const reply = await this.#call("downloadDestination", prompt, suggestedFilename, asks ? "1" : "0");
    return JSON.parse(new TextDecoder().decode(reply.bytes));
  }

  /**
   * Fetches `address`, an https address, as text, the way the Mac app
   * downloads filter lists and search suggestions: without cookies or stored
   * credentials, through no cache, following redirects only to https
   * addresses, and sending the validators of a copy already held. `purpose`
   * says which it is, which the engine's request policy tells apart: only
   * suggestions, which the person directs, may reach Google.
   */
  async fetchText(address: string, purpose: ShellFetchPurpose, entityTag: string | null = null,
    lastModified: string | null = null): Promise<ShellFetched> {
    const reply = await this.#call("fetchText", address, entityTag ?? "", lastModified ?? "", purpose);
    return JSON.parse(new TextDecoder().decode(reply.bytes)) as ShellFetched;
  }

  /**
   * Runs the action of the extension `extensionId` for the page `pageId`, as
   * a click on its button in Chrome's toolbar does, opening its popup beside
   * `anchor`, the button's place in the interface.
   */
  async runExtension(extensionId: string, pageId: string, anchor: { x: number; y: number; width: number; height: number }):
    Promise<{ readonly ran: boolean; readonly popup: boolean; readonly panel: boolean }> {
    const reply = await this.#call("runExtension", extensionId, pageId, String(anchor.x), String(anchor.y), String(anchor.width), String(anchor.height));
    return JSON.parse(new TextDecoder().decode(reply.bytes));
  }

  /**
   * Runs `items` as Windows' own context menu with its corner at `x`, `y` in
   * the interface, and answers the id of the item chosen, or null.
   */
  async menu(items: readonly ShellMenuItem[], x: number, y: number): Promise<string | null> {
    const reply = await this.#call("menu", JSON.stringify(items), String(x), String(y));
    return JSON.parse(new TextDecoder().decode(reply.bytes)) as string | null;
  }

  /**
   * Puts `text` on the clipboard. An address goes only as the core's
   * `LinkToCopy` answered it, so it leaves Crest through Super Copy.
   */
  copy(text: string) {
    return this.#call("copy", text);
  }

  /**
   * Shows a page's certificate chain, leaf first, as its engine answered it
   * (`PageCertificates`), in the system's own certificate dialog.
   */
  certificate(chain: readonly Uint8Array[]) {
    return this.#call("certificate", ...chain.map(encode));
  }

  /** Opens a finished download's file in its app. */
  openDownload(destination: string) {
    return this.#call("openDownload", destination);
  }

  /** Shows a finished download's file in its folder. */
  showDownload(destination: string) {
    return this.#call("showDownload", destination);
  }

  /** Makes this launch's first window the saved window `window`. */
  adoptWindow(window: string): Promise<CoreReply> {
    return this.#call("window", "adopt", window);
  }

  /** Reopens the saved window `window` behind this one. */
  reopenWindow(window: string): Promise<CoreReply> {
    return this.#call("window", "open", window);
  }

  #setFrame(frame: ShellFrame) {
    this.#frame = frame;
    for (const listener of this.#frameListeners) listener();
  }

  #call(op: string, ...args: string[]): Promise<CoreReply> {
    const id = this.#nextId++;
    return new Promise((resolve) => {
      this.#pending.set(id, resolve);
      shellWindow.chrome!.send!("crestCore", [id, op, ...args]);
    });
  }
}

function encode(bytes: Uint8Array): string {
  let text = "";
  for (let start = 0; start < bytes.length; start += 0x8000) {
    text += String.fromCharCode(...bytes.subarray(start, start + 0x8000));
  }
  return btoa(text);
}

function decode(text: string): Uint8Array {
  const binary = atob(text);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}
