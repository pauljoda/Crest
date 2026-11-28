import { type KeyCombination, type ShortcutBinding, type ShortcutCommand, ShortcutModifiers } from "@crest/contracts";
import type { ShellShortcut, ShellTransport } from "@crest/core-client";

import { notices } from "./notices";

/**
 * What runs each command in a window, by the command's name. A command with
 * no handler is not built here yet, so its keys stay the page's.
 */
export type CommandHandlers = Readonly<Partial<Record<string, () => void>>>;

/** The Windows virtual-key code of each special key, by the name the core keeps it under. */
const specialKeys: Readonly<Record<string, readonly [code: number, title: string]>> = {
  tab: [0x09, "Tab"],
  leftArrow: [0x25, "Left Arrow"],
  rightArrow: [0x27, "Right Arrow"],
  upArrow: [0x26, "Up Arrow"],
  downArrow: [0x28, "Down Arrow"],
  escape: [0x1b, "Esc"],
  returnKey: [0x0d, "Enter"],
  delete: [0x08, "Backspace"],
  forwardDelete: [0x2e, "Delete"],
  home: [0x24, "Home"],
  end: [0x23, "End"],
  pageUp: [0x21, "Page Up"],
  pageDown: [0x22, "Page Down"],
  space: [0x20, "Space"],
  ...Object.fromEntries(Array.from({ length: 20 }, (_, index) => [`f${index + 1}`, [0x70 + index, `F${index + 1}`] as const])),
};

/**
 * The virtual-key code of the punctuation keys, as Windows names them on the
 * US layout; letters and digits are their own code. Chromium's accelerators
 * match the same codes, so a key reads as it does in other browsers.
 */
const punctuationKeys: Readonly<Record<string, number>> = {
  "=": 0xbb, "+": 0xbb, "-": 0xbd, ",": 0xbc, ".": 0xbe, "/": 0xbf, ";": 0xba, "'": 0xde, "`": 0xc0, "[": 0xdb,
  "]": 0xdd, "\\": 0xdc,
};

/** The virtual-key code `keys` press, or null for a key Windows has no code for. */
export function keyCode(keys: KeyCombination): number | null {
  if (keys.isSpecialKey) return specialKeys[keys.key]?.[0] ?? null;
  const character = keys.key.toUpperCase();
  if (/^[A-Z0-9]$/.test(character)) return character.charCodeAt(0);
  return punctuationKeys[keys.key] ?? null;
}

/**
 * How Windows writes `keys`, such as Ctrl+Shift+T: Command is Ctrl, the
 * platform's shortcut key, and Option is Alt.
 */
export function shortcutText(keys: KeyCombination): string {
  const parts: string[] = [];
  if (keys.modifiers & ShortcutModifiers.Command) parts.push("Ctrl");
  if (keys.modifiers & ShortcutModifiers.Option) parts.push("Alt");
  if (keys.modifiers & ShortcutModifiers.Shift) parts.push("Shift");
  parts.push(keys.isSpecialKey ? specialKeys[keys.key]?.[1] ?? keys.key : keys.key.toUpperCase());
  return parts.join("+");
}

/** What the core calls `command`, its number in place for a numbered one. */
export function commandTitle(command: ShortcutCommand): string {
  return command.number === null ? command.title : command.title.replace("%lld", String(command.number));
}

/**
 * The keys a window binds now: each command the core offers that has keys,
 * that the window can run now, and that this interface runs, with who answers
 * the keys while a page or a field uses them too. Keys holding Control, the
 * Windows key, are the system's and never bound.
 */
export function windowShortcuts(bindings: readonly ShortcutBinding[], unavailable: ReadonlySet<string>,
  handlers: CommandHandlers, interfaceTakes: ReadonlySet<string> = new Set()): ShellShortcut[] {
  return bindings.flatMap((binding) => {
    const keys = binding.keys;
    const key = keys && keyCode(keys);
    if (!keys || key === null || keys.modifiers & ShortcutModifiers.Control) return [];
    if (!handlers[binding.command.name] || unavailable.has(binding.command.name)) return [];
    return [{
      command: binding.command.name,
      key,
      control: !!(keys.modifiers & ShortcutModifiers.Command),
      shift: !!(keys.modifiers & ShortcutModifiers.Shift),
      alt: !!(keys.modifiers & ShortcutModifiers.Option),
      beforePage: binding.preference.runsBeforePage,
      secondPress: binding.preference.takesSecondPress,
      yieldsToText: binding.yieldsToTextEditing || interfaceTakes.has(binding.command.name),
    }];
  });
}

/**
 * The command a key press runs among `names`, by the keys the core binds
 * them to on this device, for a window that hears those keys itself. Keys
 * holding Control, the Windows key, are the system's, as `windowShortcuts` leaves them.
 */
export function commandForKey(event: KeyboardEvent, bindings: readonly ShortcutBinding[], names: readonly string[]): string | null {
  for (const binding of bindings) {
    const keys = binding.keys;
    if (!keys || keys.modifiers & ShortcutModifiers.Control) continue;
    if (!names.includes(binding.command.name) || keyCode(keys) !== event.keyCode) continue;
    if (!!(keys.modifiers & ShortcutModifiers.Command) !== event.ctrlKey) continue;
    if (!!(keys.modifiers & ShortcutModifiers.Shift) !== event.shiftKey) continue;
    if (!!(keys.modifiers & ShortcutModifiers.Option) !== event.altKey || event.metaKey) continue;
    return binding.command.name;
  }
  return null;
}

/**
 * Runs a window's commands from their keys. Inside Crest the shell offers
 * every key to the window's bindings before a page or the interface's own
 * fields see it, and again when they let it go, and says which command to run.
 * In a development browser no shell is there, so the interface listens itself.
 */
export class WindowShortcuts {
  #table: readonly ShellShortcut[] = [];
  #sent = "";
  #handlers: CommandHandlers = {};
  #bindings: readonly ShortcutBinding[] = [];

  constructor(private readonly shell: ShellTransport | null) {}

  /** Starts running commands; answers the call that stops. */
  install(): () => void {
    const shell = this.shell;
    if (shell) {
      shell.onShortcut = (command) => this.#run(command);
      shell.onPageKept = (command) => this.#pageKept(command);
      return () => {
        shell.onShortcut = undefined;
        shell.onPageKept = undefined;
        notices.dismiss(pressAgainKey);
      };
    }
    const onKey = (event: KeyboardEvent) => {
      const bound = this.#table.find((shortcut) => shortcut.key === event.keyCode && shortcut.control === event.ctrlKey &&
        shortcut.shift === event.shiftKey && shortcut.alt === event.altKey && !event.metaKey);
      // As the shell does, keys that yield to text editing are the field's while one has the keyboard.
      if (!bound || (bound.yieldsToText && editsText(document.activeElement))) return;
      event.preventDefault();
      this.#run(bound.command);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }

  /**
   * Binds the keys of `bindings` the window can run now, through `handlers`,
   * and the keys of `held`, which the window holds for itself for a while,
   * such as Esc while a Peek is open.
   */
  update(bindings: readonly ShortcutBinding[], unavailable: ReadonlySet<string>, handlers: CommandHandlers,
    held: readonly ShellShortcut[] = [], interfaceTakes: ReadonlySet<string> = new Set()) {
    this.#handlers = handlers;
    this.#bindings = bindings;
    this.#table = [...held, ...windowShortcuts(bindings, unavailable, handlers, interfaceTakes)];
    const table = JSON.stringify(this.#table);
    if (!this.shell || table === this.#sent) return;
    this.#sent = table;
    void this.shell.shortcuts(this.#table);
  }

  #run(command: string) {
    this.#handlers[command]?.();
  }

  /** A page kept the keys, so the window says how to run the command instead, as the Mac's does. */
  #pageKept(command: string | null) {
    const binding = command ? this.#bindings.find((candidate) => candidate.command.name === command) : undefined;
    if (!binding?.keys) {
      notices.dismiss(pressAgainKey);
      return;
    }
    notices.post({
      message: `Press ${shortcutText(binding.keys)} Again to ${commandTitle(binding.command)}`,
      symbol: "keyboard",
      key: pressAgainKey,
    });
  }
}

const pressAgainKey = "press-again";

/** The input types that take no typing. */
const untypedInputs = new Set(["button", "checkbox", "color", "file", "image", "radio", "range", "reset", "submit"]);

/** Whether `element` takes typing: a text field, a text area or editable content. */
function editsText(element: Element | null): boolean {
  if (element instanceof HTMLInputElement) return !untypedInputs.has(element.type);
  return element instanceof HTMLTextAreaElement || (element instanceof HTMLElement && element.isContentEditable);
}

/**
 * Whether one of the interface's own fields is recording keys, such as a
 * shortcut being set in Settings, which then hears every key: the window
 * binds none while it does.
 */
let capturing = 0;
const capturingListeners = new Set<() => void>();

export const keyCapture = {
  begin(): () => void {
    capturing++;
    for (const listener of capturingListeners) listener();
    let ended = false;
    return () => {
      if (ended) return;
      ended = true;
      capturing--;
      for (const listener of capturingListeners) listener();
    };
  },
  subscribe(listener: () => void): () => void {
    capturingListeners.add(listener);
    return () => capturingListeners.delete(listener);
  },
  get active(): boolean {
    return capturing > 0;
  },
};

/** The special keys' names, by the KeyboardEvent key that presses them. */
const specialKeyNames: Readonly<Record<string, string>> = {
  Tab: "tab", ArrowLeft: "leftArrow", ArrowRight: "rightArrow", ArrowUp: "upArrow", ArrowDown: "downArrow",
  Escape: "escape", Enter: "returnKey", Backspace: "delete", Delete: "forwardDelete", Home: "home", End: "end",
  PageUp: "pageUp", PageDown: "pageDown", " ": "space",
};

/** The punctuation keys, by the physical key, as the core keeps them. */
const punctuationCodes: Readonly<Record<string, string>> = {
  Equal: "=", Minus: "-", Comma: ",", Period: ".", Slash: "/", Semicolon: ";", Quote: "'", Backquote: "`",
  BracketLeft: "[", BracketRight: "]", Backslash: "\\",
};

/** The same keys by their Windows key codes, for a press that names no physical key. */
const punctuationKeyCodes: Readonly<Record<number, string>> = {
  0xbb: "=", 0xbd: "-", 0xbc: ",", 0xbe: ".", 0xbf: "/", 0xba: ";", 0xde: "'", 0xc0: "`", 0xdb: "[", 0xdd: "]", 0xdc: "\\",
};

/**
 * The keys a key press makes, as the core keeps a shortcut: Ctrl is Command,
 * Alt is Option, the Windows key is Control; or null for a key alone, such
 * as a modifier going down.
 */
export function pressedKeys(event: KeyboardEvent): KeyCombination | null {
  if (["Control", "Shift", "Alt", "Meta", "OS"].includes(event.key)) return null;
  let key: string | null = null;
  let isSpecialKey = false;
  if (/^F([1-9]|1\d|20)$/.test(event.key)) {
    key = event.key.toLowerCase();
    isSpecialKey = true;
  } else if (specialKeyNames[event.key]) {
    key = specialKeyNames[event.key];
    isSpecialKey = true;
  } else if (/^Key[A-Z]$/.test(event.code)) key = event.code.slice(3).toLowerCase();
  else if (/^Digit\d$/.test(event.code)) key = event.code.slice(5);
  else if (punctuationCodes[event.code]) key = punctuationCodes[event.code];
  // A press some keyboards and remote sessions send without its physical
  // key, which its key code still names.
  else if (!event.code && event.keyCode >= 0x41 && event.keyCode <= 0x5a) key = String.fromCharCode(event.keyCode).toLowerCase();
  else if (!event.code && event.keyCode >= 0x30 && event.keyCode <= 0x39) key = String.fromCharCode(event.keyCode);
  else if (!event.code && punctuationKeyCodes[event.keyCode]) key = punctuationKeyCodes[event.keyCode];
  if (key === null) return null;
  let modifiers = 0;
  if (event.ctrlKey) modifiers |= ShortcutModifiers.Command;
  if (event.altKey) modifiers |= ShortcutModifiers.Option;
  if (event.shiftKey) modifiers |= ShortcutModifiers.Shift;
  if (event.metaKey) modifiers |= ShortcutModifiers.Control;
  return { key, isSpecialKey, modifiers };
}
