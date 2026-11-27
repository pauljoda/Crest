import type { ShellTransport, ShellUpdateSettings } from "@crest/core-client";

import { notices } from "./notices";
import { reader } from "./reactive";

/**
 * BrowserSoftwareUpdateChannel, as Windows follows it: the release lines an
 * installed build can update on, each read from its Windows feed. Stable's
 * and Nightly's builds share `appcast-windows.xml`, Nightly's naming their
 * channel; Development's have their own feed.
 */
export interface UpdateChannel {
  readonly name: "stable" | "nightly" | "development";
  readonly title: string;
  readonly guidance: string;
  readonly feed: string;
  /** The feed channels this channel accepts beyond the default one every item without a channel belongs to. */
  readonly accepts: readonly string[];
}

export const updateChannels: readonly UpdateChannel[] = [
  { name: "stable", title: "Stable", guidance: "Recommended for everyday use.", feed: "appcast-windows.xml", accepts: [] },
  { name: "nightly", title: "Nightly", guidance: "Daily builds. May be less reliable.", feed: "appcast-windows.xml",
    accepts: ["nightly"] },
  { name: "development", title: "Development", guidance: "Updates several times a day.",
    feed: "appcast-development-windows.xml", accepts: ["development"] },
];

/** An update the feed offers: its version, build, installer and the installer's length and signature. */
export interface AvailableUpdate {
  readonly version: string;
  readonly build: number;
  readonly url: string;
  readonly length: number;
  readonly signature: string;
  readonly releaseNotes: string | null;
}

/** BrowserSoftwareUpdatePhase: where an update stands, as Settings says it. */
export type UpdatePhase =
  | { readonly name: "idle" }
  | { readonly name: "checking" }
  | { readonly name: "upToDate" }
  | { readonly name: "available"; readonly update: AvailableUpdate }
  | { readonly name: "downloading"; readonly update: AvailableUpdate; readonly received: number; readonly total: number }
  | { readonly name: "installing"; readonly update: AvailableUpdate }
  | { readonly name: "failed"; readonly message: string };

/** What each phase is called, as the Mac's titles them. */
export const phaseTitles: Readonly<Record<UpdatePhase["name"], string>> = {
  idle: "Software Update",
  checking: "Checking for Updates",
  upToDate: "Crest Is Up to Date",
  available: "Update Available",
  downloading: "Downloading Update",
  installing: "Installing Update",
  failed: "Update Check Failed",
};

/** The line under a phase's title: the update's version, or why it failed. */
export function phaseDetail(phase: UpdatePhase): string | null {
  switch (phase.name) {
    case "available":
    case "downloading":
    case "installing":
      return `Version ${phase.update.version}`;
    case "failed":
      return phase.message;
    default:
      return null;
  }
}

/** How much of the update has arrived, from 0 to 1, while it downloads and its length is known. */
export function phaseProgress(phase: UpdatePhase): number | null {
  return phase.name === "downloading" && phase.total > 0 ? Math.min(phase.received / phase.total, 1) : null;
}

const SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle";
// Sparkle's scheduled check, as the Mac's SUScheduledCheckInterval sets it.
const CHECK_INTERVAL = 60 * 60 * 1000;
// A launch checks once it has settled, unless a check ran within the interval.
const LAUNCH_DELAY = 30 * 1000;
const keys = {
  automatic: "crest.softwareUpdates.checksAutomatically",
  channel: "crest.softwareUpdates.channel",
  lastCheck: "crest.softwareUpdates.lastCheck",
} as const;

function stored(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function store(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // A window that can't keep it checks as it ships.
  }
}

/**
 * The updates of an installed Crest for Windows, as BrowserSoftwareUpdateService
 * keeps the Mac's: whether it checks by itself, the channel it follows, and
 * where an update stands. The feed is the one the installed build's
 * update.json names, read through the engine; the engine downloads an
 * update, checks it carries the signature of the key Crest's releases are
 * signed with, and runs its installer, which opens Crest again.
 */
export class SoftwareUpdates {
  #shell: ShellTransport | null = null;
  #settings: ShellUpdateSettings | null = null;
  #phase: UpdatePhase = { name: "idle" };
  #listeners = new Set<() => void>();
  #timer: ReturnType<typeof setTimeout> | null = null;
  #announced = new Set<number>();
  #version = 0;

  /** Whether this Crest is installed, so it can update. */
  get isEnabled(): boolean {
    return this.#settings !== null;
  }

  get phase(): UpdatePhase {
    return this.#phase;
  }

  get checksAutomatically(): boolean {
    return stored(keys.automatic) !== "0";
  }

  get channel(): UpdateChannel {
    const name = stored(keys.channel) ?? this.#settings?.channel;
    return updateChannels.find((channel) => channel.name === name) ?? updateChannels[2];
  }

  /** The state's version, which grows whenever any of it changes. */
  get version(): number {
    return this.#version;
  }

  /** Calls `listener` whenever any of this state changes, until the returned function is called. */
  subscribe(listener: () => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /** Reads this build's update settings from the engine; `automatic` starts the scheduled checks. */
  async start(shell: ShellTransport, automatic: boolean) {
    this.#shell = shell;
    this.#settings = await shell.updateSettings().catch(() => null);
    shell.onUpdateProgress = (received, total) => {
      const phase = this.#phase;
      if (phase.name === "downloading") this.#set({ ...phase, received, total });
    };
    this.#changed();
    if (automatic) this.#schedule(true);
  }

  setChecksAutomatically(checks: boolean) {
    store(keys.automatic, checks ? "1" : "0");
    this.#changed();
    this.#schedule(false);
  }

  /** Follows the channel named `name`, as the Update channel picker chooses it. */
  setChannel(name: string) {
    const channel = updateChannels.find((candidate) => candidate.name === name);
    if (!channel) return;
    store(keys.channel, channel.name);
    // An update found on another channel is no longer this one's.
    if (this.#phase.name !== "downloading" && this.#phase.name !== "installing") this.#phase = { name: "idle" };
    this.#changed();
  }

  /** Puts a settled outcome away, as the Mac's Dismiss does. */
  dismiss() {
    if (this.#phase.name === "upToDate" || this.#phase.name === "failed") this.#set({ name: "idle" });
  }

  /** Asks the feed for an update, as the person's Check for Updates… does. */
  async check(automatic = false) {
    const shell = this.#shell;
    const settings = this.#settings;
    if (!shell || !settings) return;
    const name = this.#phase.name;
    if (name === "checking" || name === "downloading" || name === "installing") return;
    if (!automatic) this.#set({ name: "checking" });
    store(keys.lastCheck, String(Date.now()));
    const channel = this.channel;
    const feed = await shell.updateFeed(channel.feed).catch(() => null);
    const update = feed === null ? undefined : newestUpdate(feed, channel, settings.build);
    if (update === undefined) {
      if (!automatic) this.#set({ name: "failed", message: "Crest couldn't reach its updates. Check your connection, then try again." });
      return;
    }
    if (update === null) {
      if (!automatic) this.#set({ name: "upToDate" });
      return;
    }
    this.#set({ name: "available", update });
    if (automatic && !this.#announced.has(update.build)) {
      this.#announced.add(update.build);
      notices.post({ message: `Crest ${update.version} is available in Settings › About`, symbol: "arrow.down.circle.fill" });
    }
  }

  /**
   * Downloads the update, which the engine checks against the key Crest's
   * releases are signed with, then installs it: Crest quits for the
   * installer, which opens it again.
   */
  async install() {
    const shell = this.#shell;
    const phase = this.#phase;
    if (!shell || phase.name !== "available") return;
    const { update } = phase;
    this.#set({ name: "downloading", update, received: 0, total: update.length });
    const outcome = await shell.installUpdate(update.url, update.length, update.signature)
      .catch(() => ({ result: "failed", reason: "unavailable" }) as const);
    if (outcome.result === "installing") {
      this.#set({ name: "installing", update });
      return;
    }
    this.#set({ name: "failed", message: failureMessages[outcome.reason] });
  }

  #schedule(launching: boolean) {
    if (this.#timer) clearTimeout(this.#timer);
    this.#timer = null;
    if (!this.checksAutomatically || !this.#settings) return;
    const last = Number(stored(keys.lastCheck) ?? 0);
    const due = Math.max(last + CHECK_INTERVAL - Date.now(), launching ? LAUNCH_DELAY : 0);
    this.#timer = setTimeout(() => {
      void this.check(true).finally(() => this.#schedule(false));
    }, Math.min(due, CHECK_INTERVAL));
  }

  #set(phase: UpdatePhase) {
    this.#phase = phase;
    this.#changed();
  }

  #changed() {
    this.#version += 1;
    for (const listener of this.#listeners) listener();
  }
}

const failureMessages = {
  download: "The update couldn't be downloaded. Try again later.",
  length: "The update didn't arrive whole, so Crest didn't install it.",
  signature: "The update isn't signed by Crest's releases, so Crest didn't install it.",
  launch: "The update's installer couldn't start.",
  unavailable: "This copy of Crest can't install updates.",
} as const;

/**
 * The newest Windows update in `feed` that `channel` accepts and that is
 * newer than `build`, null when there is none, or undefined when the feed
 * isn't one.
 */
export function newestUpdate(feed: string, channel: UpdateChannel, build: number): AvailableUpdate | null | undefined {
  const document = new DOMParser().parseFromString(feed, "application/xml");
  if (document.getElementsByTagName("parsererror").length || !document.getElementsByTagName("rss").length) return undefined;
  let newest: AvailableUpdate | null = null;
  for (const item of Array.from(document.getElementsByTagName("item"))) {
    const text = (name: string) => item.getElementsByTagNameNS(SPARKLE, name)[0]?.textContent?.trim() || null;
    const itemChannel = text("channel");
    if (itemChannel !== null && !channel.accepts.includes(itemChannel)) continue;
    const itemBuild = Number(text("version"));
    const enclosure = item.getElementsByTagName("enclosure")[0];
    if (!Number.isSafeInteger(itemBuild) || itemBuild <= build || !enclosure) continue;
    if (enclosure.getAttributeNS(SPARKLE, "os") !== "windows") continue;
    const url = enclosure.getAttribute("url");
    const length = Number(enclosure.getAttribute("length"));
    const signature = enclosure.getAttributeNS(SPARKLE, "edSignature");
    if (!url || !signature || !Number.isSafeInteger(length) || length <= 0) continue;
    if (newest && newest.build >= itemBuild) continue;
    newest = {
      version: text("shortVersionString") ?? item.getElementsByTagName("title")[0]?.textContent?.trim() ?? String(itemBuild),
      build: itemBuild, url, length, signature, releaseNotes: text("releaseNotesLink"),
    };
  }
  return newest;
}

/** This window's updates. */
export const softwareUpdates = new SoftwareUpdates();

/** Redraws with this window's updates. */
const readSoftwareUpdates = reader((listener) => softwareUpdates.subscribe(listener), () => softwareUpdates.version);

/**
 * This window's updates, followed by the expression that reads them: call it
 * inside the `$derived` or template expression that reads from it.
 */
export function useSoftwareUpdates(): SoftwareUpdates {
  readSoftwareUpdates();
  return softwareUpdates;
}
