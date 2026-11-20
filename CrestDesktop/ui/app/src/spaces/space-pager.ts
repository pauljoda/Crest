import type { ShellWheel } from "@crest/core-client";
import { useSyncExternalStore } from "react";

/**
 * The window's Space pager, as the Mac's SpacePagerViewport: the strip of
 * Space pages the sidebar slides along, its fractional position, and one
 * clock every leaf follows — the pages, the switcher's selection and the
 * banners behind them — without the read model hearing of any frame.
 *
 * A selection from the core slides one page: between neighbours, around the
 * ends for a Next or Previous step, or, for a Space further away, along a
 * strip that puts it next door until the slide ends. A swipe tracks the
 * pointer and, released past halfway or thrown, settles on the neighbour and
 * only then asks the core to show it.
 */

export type PagerPhase = "idle" | "tracking" | "settling";

/** What the pager shows, read by the leaves that follow it. */
export interface PagerFrame {
  /** The order the position runs along: the Spaces, or a jump's order. */
  readonly order: readonly string[];
  /** The fractional index in `order`; around the ends it reaches one past either end. */
  readonly position: number;
  readonly phase: PagerPhase;
  /** The Space a slide began from, or the one shown at rest. */
  readonly originId: string | null;
  /** The Space a slide heads for, or the one shown at rest. */
  readonly destinationId: string | null;
  /** The Spaces whose pages are on screen: the one at rest, or both a slide moves between. */
  readonly pages: readonly string[];
  /** The last change of Space the pager showed at once, without a slide, as under Reduce Motion. */
  readonly dissolve: { readonly from: string; readonly generation: number } | null;
}

/** A settle's course, from its start, for leaves that run it on the compositor. */
export interface SettleTimeline {
  /** Names this settle; another one gets another. */
  readonly id: number;
  /**
   * When its clock started, on the document's timeline (performance.now):
   * the first frame every page it brings on screen could draw. Null while
   * the pager holds it at its start.
   */
  readonly began: number | null;
  /** How long it lasts, in seconds. */
  readonly duration: number;
  /** The pager's frame `elapsed` seconds in. */
  frameAt(elapsed: number): PagerFrame;
}

/** The style a leaf takes at a frame: what it animates on the compositor, and what it holds through a settle. */
export interface LeafStyle {
  readonly transform?: string;
  readonly opacity?: string;
  readonly visibility?: string;
  readonly zIndex?: string;
  readonly willChange?: string;
}

const settleAnimations = new WeakMap<HTMLElement, { readonly id: number; readonly animation: Animation }>();

/** Each held settle's animations, paused at its start until its clock starts. */
const heldSettles = new Map<number, Set<Animation>>();

/** Starts the held animations of settle `id` on its clock, which started at `began`, and lets go of any older settle's. */
function startHeldSettle(id: number, began: number) {
  for (const animation of heldSettles.get(id) ?? []) {
    if (animation.playState !== "idle") animation.startTime = began;
  }
  heldSettles.clear();
}

/** Writes `style` to `element`, touching only what changed, since even an unchanged write costs a style recalculation. */
export function applyLeafStyle(element: HTMLElement, style: LeafStyle) {
  const target = element.style;
  const set = (property: "transform" | "opacity" | "visibility" | "zIndex" | "willChange", value: string | undefined) => {
    const next = value ?? "";
    if (target[property] !== next) target[property] = next;
  };
  set("transform", style.transform);
  set("opacity", style.opacity);
  set("visibility", style.visibility);
  set("zIndex", style.zIndex);
  set("willChange", style.willChange);
}

/**
 * Runs `element`'s part in a settle as a compositor animation: its transform
 * and opacity sampled along the settle at the display's rate, from where the
 * settle is now. Moving a page from script each frame repaints what it holds,
 * its shadows and filters among them, which an integrated GPU can't keep up
 * with on a large window; an animation the compositor runs repaints nothing.
 * What doesn't animate (visibility, stacking) holds its value from the start.
 * Until the settle's clock starts, the animation holds at its first step.
 */
export function animateSettle(element: HTMLElement, settle: SettleTimeline, style: (frame: PagerFrame) => LeafStyle) {
  const running = settleAnimations.get(element);
  if (running?.id === settle.id) return;
  running?.animation.cancel();
  const steps = Math.max(2, Math.ceil(settle.duration * 60) + 1);
  const samples = Array.from({ length: steps }, (_, step) => style(settle.frameAt((step / (steps - 1)) * settle.duration)));
  const began = settle.began;
  const now = style(settle.frameAt(began === null ? 0 : Math.max(0, (performance.now() - began) / 1000)));
  // Only what changes along the settle animates: an opacity held at 1 would
  // still have Chromium draw the element offscreen first.
  const moves = samples.some((sample) => sample.transform && sample.transform !== samples[0].transform);
  const fades = samples.some((sample) => (sample.opacity ?? "") !== (samples[0].opacity ?? ""));
  // Visibility and stacking hold through the settle: the pages it moves show, the area's clip hides what passes its edge.
  applyLeafStyle(element, {
    ...now,
    visibility: samples.some((sample) => sample.visibility !== "hidden") ? "" : "hidden",
    transform: moves ? element.style.transform : now.transform,
    opacity: fades ? element.style.opacity : now.opacity,
    willChange: [...new Set([...(now.willChange ?? "").split(",").map((part) => part.trim()), moves && "transform", fades && "opacity"])]
      .filter(Boolean).join(", "),
  });
  if (!moves && !fades) {
    settleAnimations.set(element, { id: settle.id, animation: new Animation() });
    return;
  }
  // A page that wraps around the strip's ends jumps there, rather than sweeping across the area between two samples.
  const shift = (sample: LeafStyle) => Number(/translateX\((-?[\d.e+-]+)%\)/.exec(sample.transform ?? "")?.[1] ?? 0);
  const wraps = (index: number) => moves && index + 1 < samples.length && Math.abs(shift(samples[index + 1]) - shift(samples[index])) > 100;
  const keyframes = samples.map((sample, index) => ({
    ...(moves ? { transform: sample.transform || "translateX(0%)" } : {}),
    ...(fades ? { opacity: sample.opacity === undefined || sample.opacity === "" ? "1" : sample.opacity } : {}),
    ...(wraps(index) ? { easing: "step-end" } : {}),
  }));
  const animation = element.animate(keyframes, { duration: settle.duration * 1000, easing: "linear", fill: "forwards" });
  if (began === null) {
    // Held at the start with every other leaf until the settle's clock starts.
    animation.pause();
    animation.currentTime = 0;
    const held = heldSettles.get(settle.id) ?? new Set<Animation>();
    held.add(animation);
    heldSettles.set(settle.id, held);
  } else {
    // On the settle's own clock, so every leaf, whenever it came, stands at the same moment of it.
    animation.startTime = began;
  }
  settleAnimations.set(element, { id: settle.id, animation });
}

/** Ends `element`'s settle animation, if it runs one, leaving its own style to show. */
export function stopSettle(element: HTMLElement) {
  const running = settleAnimations.get(element);
  if (!running) return;
  running.animation.cancel();
  settleAnimations.delete(element);
}

/** Where a settling strip is at each moment, and when it arrives. */
interface Settlement {
  readonly duration: number;
  /** Where the strip is `elapsed` seconds in. */
  position(elapsed: number): number;
}

/** A slide nothing threw, as SpacePagerSettlement: the Mac's measured curve over 0.28 s a page (spaceSwipeTransition). */
class CurveSettlement implements Settlement {
  static readonly pageDuration = 0.28;
  readonly start: number;
  readonly end: number;
  readonly duration: number;

  constructor(start: number, end: number) {
    this.start = start;
    this.end = end;
    this.duration = CurveSettlement.pageDuration * Math.max(1, Math.abs(end - start));
  }

  position(elapsed: number): number {
    const progress = Math.min(1, Math.max(0, elapsed / this.duration));
    return this.start + (this.end - this.start) * curve(progress);
  }
}

/**
 * A swipe's release: the strip carries on at the fingers' speed and comes to
 * rest on a critically damped spring, as a touchpad's own inertia does,
 * rather than starting over on a fixed curve. Its stiffness settles a page
 * from rest in about the Mac's 0.28 s. A throw toward the destination faster
 * than the spring could stop from is eased to that speed, so the strip never
 * passes the page it lands on.
 */
class SpringSettlement implements Settlement {
  /** The spring's natural frequency, in radians a second: within 1% of the way in 0.28 s from rest. */
  static readonly stiffness = 23.71;
  /** The fastest throw the spring takes on, in pages a second. */
  static readonly fastest = 8;
  readonly end: number;
  readonly duration: number;
  readonly #displacement: number;
  readonly #rate: number;

  constructor(start: number, end: number, velocity: number) {
    const omega = SpringSettlement.stiffness;
    const displacement = start - end;
    let speed = Math.max(-SpringSettlement.fastest, Math.min(SpringSettlement.fastest, velocity));
    // Toward the destination no faster than ω × distance, which never overshoots.
    if (speed * displacement < 0 && Math.abs(speed) > omega * Math.abs(displacement)) {
      speed = -Math.sign(displacement) * omega * Math.abs(displacement);
    }
    this.end = end;
    this.#displacement = displacement;
    this.#rate = speed + omega * displacement;
    // At rest once within a thousandth of a page.
    let duration = 0;
    while (duration < 2 && Math.abs(this.#offset(duration)) > 0.001) duration += 1 / 240;
    this.duration = Math.max(1 / 60, duration);
  }

  #offset(elapsed: number): number {
    return (this.#displacement + this.#rate * elapsed) * Math.exp(-SpringSettlement.stiffness * elapsed);
  }

  position(elapsed: number): number {
    return elapsed >= this.duration ? this.end : this.end + this.#offset(elapsed);
  }
}

/** cubic-bezier(0.27, 1, 0.18, 1), the Mac's measured curve, by bisecting its parameter. */
function curve(x: number): number {
  const bezier = (t: number, first: number, second: number) => {
    const u = 1 - t;
    return 3 * u * u * t * first + 3 * u * t * t * second + t * t * t;
  };
  let low = 0;
  let high = 1;
  for (let index = 0; index < 32; index++) {
    const t = (low + high) / 2;
    if (bezier(t, 0.27, 0.18) < x) low = t;
    else high = t;
  }
  return bezier((low + high) / 2, 1, 1);
}

/** The CSS curve of every Space slide's settling. */
export const spaceSlideEasing = "cubic-bezier(0.27, 1, 0.18, 1)";

/**
 * SpacePagerInterpolation: the two Spaces either side of `position` among
 * `count`, and how far along it is; past the last it runs on to the first.
 */
export function interpolate(position: number, count: number): { lower: number; upper: number; fraction: number } | null {
  if (count <= 0 || !Number.isFinite(position)) return null;
  if (count > 2 && position > count - 1 && position <= count) return { lower: count - 1, upper: 0, fraction: position - (count - 1) };
  if (count > 2 && position < 0 && position >= -1) return { lower: count - 1, upper: 0, fraction: position + 1 };
  const clamped = Math.min(count - 1, Math.max(0, position));
  const lower = Math.floor(clamped);
  return { lower, upper: Math.min(count - 1, lower + 1), fraction: clamped - lower };
}

/** Where the page at `index` stands near `position`: its own index, or one strip length away where a step joins the ends. */
export function placedIndex(index: number, position: number, count: number): number {
  if (count <= 2 || !Number.isFinite(position)) return index;
  return index + count * Math.round((position - index) / count);
}

/**
 * SpacePagerPresentation.jumpOrder: `ids` with `target` moved beside
 * `origin`, on the side it lies, when they are further apart than next door.
 */
function jumpOrder(ids: readonly string[], origin: string, target: string): string[] | null {
  const originIndex = ids.indexOf(origin);
  const targetIndex = ids.indexOf(target);
  if (originIndex < 0 || targetIndex < 0 || Math.abs(targetIndex - originIndex) <= 1) return null;
  const order = [...ids];
  const [moved] = order.splice(targetIndex, 1);
  const shifted = targetIndex < originIndex ? originIndex - 1 : originIndex;
  order.splice(targetIndex < originIndex ? shifted : shifted + 1, 0, moved);
  return order;
}

interface Settling {
  readonly settlement: Settlement;
  readonly destinationId: string;
  /** When the settle was asked for, which bounds how long a page can hold it. */
  readonly requested: number;
  /**
   * Whether pages it brings on screen can hold its start: only a slide from
   * rest, as one a swipe throws carries on from the fingers at once.
   */
  readonly holdable: boolean;
  /** When its clock started, on its first frame free of holds; null until then. */
  began: number | null;
}

interface Motion {
  readonly originId: string;
  targetId: string | null;
  /** Pages from the origin's place, positive toward the next Space. */
  offset: number;
  initialOffset: number;
  translation: number;
  /** +1 toward the next Space, -1 toward the previous, 0 until chosen. */
  direction: number;
  settling: Settling | null;
  commitsSelection: boolean;
  /** Pages an interrupted slide still shows part of, kept on the strip until this one ends. */
  carried?: readonly string[];
}

class SpacePager {
  #ids: readonly string[] = [];
  #order: readonly string[] = [];
  #jump: { origin: string; target: string } | null = null;
  #selectedId: string | null = null;
  #presentedId: string | null = null;
  #expectedId: string | null = null;
  #step: { origin: string; destination: string; direction: 1 | -1 } | null = null;
  #motion: Motion | null = null;
  /** How many settles have begun, which names each one's timeline. */
  #settles = 0;
  #timeline: SettleTimeline | null = null;
  #locked = false;
  /** Pages drawing in place before a slide moves them, which hold its start. */
  #holds = new Set<symbol>();
  #width = 0;
  #frame: PagerFrame = { order: [], position: 0, phase: "idle", originId: null, destinationId: null, pages: [], dissolve: null };
  #dissolve: PagerFrame["dissolve"] = null;
  #listeners = new Set<() => void>();
  #frameListeners = new Set<(frame: PagerFrame) => void>();
  #animation = 0;
  #select: (spaceId: string) => void = () => {};

  get frame(): PagerFrame { return this.#frame; }
  get isMoving(): boolean { return this.#motion !== null; }

  /** The Spaces in their order and the one the core shows; called as the window draws. */
  update(ids: readonly string[], selectedId: string, select: (spaceId: string) => void) {
    this.#select = select;
    const idsChanged = ids.length !== this.#ids.length || ids.some((id, index) => id !== this.#ids[index]);
    const selectionChanged = selectedId !== this.#selectedId;
    if (!idsChanged && !selectionChanged) return;
    this.#ids = ids;
    this.#arrange();
    this.#selectedId = selectedId;
    if (idsChanged) {
      this.#cancel();
      this.#presentedId = selectedId;
      this.#expectedId = null;
    } else if (this.#expectedId === selectedId) {
      // The core showed the Space a swipe settled on.
      this.#expectedId = null;
      if (!this.#motion) this.#presentedId = selectedId;
    } else if (selectionChanged) {
      this.#expectedId = null;
      const heading = this.#motion?.settling?.destinationId;
      const continues = heading && !this.#jump && !reducesMotion() ? this.#stepBetween(heading, selectedId) : null;
      if (heading && continues) {
        // A selection made while a slide settles continues from where the strip is.
        this.#continue(heading, selectedId, continues);
      } else {
        const wasMoving = this.#motion !== null;
        this.#cancel();
        const origin = this.#presentedId;
        const step = origin && !reducesMotion() && !this.#locked
          ? this.#stepBetween(origin, selectedId) ?? (wasMoving ? null : this.#beginJump(origin, selectedId))
          : null;
        if (origin && step) this.#animate(origin, selectedId, step, false);
        else {
          if (origin && origin !== selectedId) this.#dissolve = { from: origin, generation: (this.#dissolve?.generation ?? 0) + 1 };
          this.#presentedId = selectedId;
        }
      }
    }
    this.#publish();
  }

  /** Holds the strip still while a drag owns the pointer: paging under it would move the rows it aims at. */
  setLocked(locked: boolean) {
    if (locked === this.#locked) return;
    this.#locked = locked;
    if (locked && this.#motion) {
      this.#cancel();
      this.#presentedId = this.#selectedId;
      this.#expectedId = null;
      this.#publish();
    }
  }

  /** Notes a Next or Previous Space command, whose step slides around the ends. */
  noteStep(direction: 1 | -1) {
    const origin = this.#selectedId;
    const index = origin ? this.#ids.indexOf(origin) : -1;
    if (index < 0 || this.#ids.length < 2) return;
    const destination = this.#ids[(index + direction + this.#ids.length) % this.#ids.length];
    this.#step = { origin: origin!, destination, direction };
  }

  /**
   * Holds a settle at its start until the returned release, for a page it
   * brings on screen that draws in place first, so its first frames don't
   * come late; a settle waits no longer than `longestHold`.
   */
  holdStart(): () => void {
    const hold = Symbol("hold");
    this.#holds.add(hold);
    return () => {
      if (!this.#holds.delete(hold) || this.#holds.size > 0) return;
      // The last page to draw starts the clock on this frame, rather than the next.
      const time = document.timeline.currentTime;
      this.#startSettleClock(typeof time === "number" ? time : performance.now());
    };
  }

  /** How long a page can hold a settle at its start, in milliseconds. */
  static readonly longestHold = 300;

  /** Measures the page the strip moves, before a slide reads it. */
  setWidth(width: number) {
    if (width > 0) this.#width = width;
  }

  subscribe = (listener: () => void) => {
    this.#listeners.add(listener);
    return () => void this.#listeners.delete(listener);
  };

  /** Follows every frame, for leaves that move without drawing again. */
  subscribeFrames(listener: (frame: PagerFrame) => void): () => void {
    this.#frameListeners.add(listener);
    listener(this.#frame);
    return () => void this.#frameListeners.delete(listener);
  }

  // MARK: - Swiping

  /** Begins a swipe, from the page nearest what is on screen; false where none can begin. */
  beginTracking(): boolean {
    if (this.#locked || this.#ids.length < 2 || this.#width <= 0) return false;
    const previous = this.#motion;
    let origin = previous?.originId ?? this.#presentedId;
    if (!origin) return false;
    let inherited = 0;
    if (previous) {
      // Restart from the nearest visible page, keeping what of the slide is on screen.
      const position = this.#frame.position;
      const count = this.#order.length;
      const reached = Math.round(position);
      const nearestIndex = count > 2 ? ((reached % count) + count) % count : Math.min(count - 1, Math.max(0, reached));
      origin = this.#order[nearestIndex];
      // A jump's strip isn't the Spaces' own order, so a swipe over one starts at rest.
      inherited = this.#jump ? 0 : position - placedIndex(nearestIndex, position, count);
    }
    this.#stopClock();
    this.#jump = null;
    this.#arrange();
    this.#presentedId = origin;
    this.#motion = {
      originId: origin, targetId: null, offset: inherited, initialOffset: inherited, translation: 0, direction: 0,
      settling: null, commitsSelection: true, carried: previous ? this.#frame.pages : undefined,
    };
    this.#publish();
    return true;
  }

  /** Moves a swipe by `pixels` toward the next Space (negative toward the previous). */
  track(pixels: number) {
    const motion = this.#motion;
    if (!motion || motion.settling || this.#locked || this.#width <= 0) return;
    const delta = pixels / this.#width;
    if (motion.direction === 0 && delta !== 0) {
      motion.direction = delta > 0 ? 1 : -1;
      motion.targetId = this.#neighbor(motion.originId, motion.direction);
    }
    const reach = (direction: number) => (this.#neighbor(motion.originId, direction) ? 1 : 0);
    const available = motion.direction > 0 ? reach(1) - motion.initialOffset : motion.initialOffset + reach(-1);
    const pending = motion.initialOffset + motion.translation - motion.offset;
    // Reverse from what is on screen rather than unwinding travel not yet shown.
    if (delta * pending < 0) motion.translation = motion.offset - motion.initialOffset;
    const travel = Math.min(Math.max(0, available), Math.max(0, (motion.translation + delta) * motion.direction));
    motion.translation = travel * motion.direction;
    this.#startClock();
    if (motion.direction !== 0 && this.#frame.pages.length < 2) this.#publish();
  }

  /**
   * Ends a swipe moving `pixelsPerSecond` toward the next Space, as the Mac's
   * endInteractiveMotion: it settles on the neighbour when it is past halfway
   * or thrown there (what it had moved plus 0.15 s more at its speed), else
   * back where it began, carrying on from the fingers' speed either way.
   */
  release(pixelsPerSecond: number, cancelled = false) {
    const motion = this.#motion;
    if (!motion || motion.settling) return;
    const travel = Math.max(0, motion.translation * motion.direction);
    const velocity = cancelled || travel === 0 ? 0 : pixelsPerSecond / this.#width;
    const progress = Math.max(travel, motion.offset * motion.direction);
    const projected = progress + velocity * motion.direction * 0.15;
    const completes = !cancelled && travel > 0 && projected >= 0.5 && motion.targetId !== null;
    this.#settle(completes ? motion.targetId! : motion.originId, velocity);
  }

  // MARK: - Motion

  #neighbor(origin: string, direction: number): string | null {
    const index = this.#ids.indexOf(origin);
    const count = this.#ids.length;
    if (index < 0 || count < 2) return null;
    const next = index + direction;
    if (next >= 0 && next < count) return this.#ids[next];
    // Two Spaces are already neighbours both ways; more wrap around the ends.
    return count > 2 ? this.#ids[(next + count) % count] : null;
  }

  /** One page forward or back between neighbours, or around the ends for a Next or Previous step. */
  #stepBetween(origin: string, target: string): 1 | -1 | null {
    const originIndex = this.#ids.indexOf(origin);
    const targetIndex = this.#ids.indexOf(target);
    if (originIndex < 0 || targetIndex < 0) return null;
    if (Math.abs(targetIndex - originIndex) === 1) return targetIndex > originIndex ? 1 : -1;
    const step = this.#step;
    this.#step = null;
    if (this.#ids.length > 2 && step && step.origin === origin && step.destination === target) return step.direction;
    return null;
  }

  #beginJump(origin: string, target: string): 1 | -1 | null {
    if (!jumpOrder(this.#ids, origin, target)) return null;
    this.#jump = { origin, target };
    this.#arrange();
    return this.#ids.indexOf(target) > this.#ids.indexOf(origin) ? 1 : -1;
  }

  #arrange() {
    this.#order = (this.#jump && jumpOrder(this.#ids, this.#jump.origin, this.#jump.target)) || this.#ids;
  }

  #animate(origin: string, destination: string, step: 1 | -1, commitsSelection: boolean) {
    this.#presentedId = origin;
    this.#motion = {
      originId: origin, targetId: destination, offset: 0, initialOffset: 0, translation: 0, direction: step,
      settling: null, commitsSelection,
    };
    this.#settle(destination);
  }

  #continue(heading: string, destination: string, step: 1 | -1) {
    const position = this.#frame.position;
    this.#stopClock();
    this.#jump = null;
    this.#arrange();
    const index = this.#order.indexOf(heading);
    const offset = position - placedIndex(index, position, this.#order.length);
    this.#presentedId = heading;
    this.#motion = {
      originId: heading, targetId: destination, offset, initialOffset: offset, translation: 0, direction: step,
      settling: null, commitsSelection: false, carried: this.#frame.pages,
    };
    this.#settle(destination);
  }

  /** Slides to `destination`: from a swipe's release at `velocity` pages a second on the spring, else on the Mac's curve. */
  #settle(destination: string, velocity: number | null = null) {
    const motion = this.#motion;
    if (!motion) return;
    const originIndex = this.#order.indexOf(motion.originId);
    const start = originIndex + motion.offset;
    const end = destination === motion.originId ? originIndex : originIndex + motion.direction;
    if (reducesMotion() || Math.abs(end - start) < 0.0001) {
      this.#finish(destination);
      return;
    }
    const settlement = velocity === null ? new CurveSettlement(start, end) : new SpringSettlement(start, end, velocity);
    const holdable = velocity === null && Math.abs(start - Math.round(start)) < 0.0001;
    motion.settling = { settlement, destinationId: destination, requested: performance.now(), holdable, began: null };
    this.#timeline = null;
    this.#settles++;
    this.#startClock();
    this.#publish();
  }

  /**
   * The settle under way, as a timeline the leaves hand to the compositor:
   * each samples where it stands along it and runs that as an animation, so
   * a slide moves without the page repainting each frame. Null outside one.
   */
  get settle(): SettleTimeline | null {
    const settling = this.#motion?.settling;
    if (!settling) return null;
    if (this.#timeline?.id !== this.#settles) {
      const frame = this.#frame;
      const { settlement } = settling;
      this.#timeline = {
        id: this.#settles,
        get began() { return settling.began; },
        duration: settlement.duration,
        frameAt: (elapsed) => ({ ...frame, phase: "settling", position: settlement.position(elapsed) }),
      };
    }
    return this.#timeline;
  }

  #finish(destination: string) {
    const motion = this.#motion;
    this.#stopClock();
    this.#motion = null;
    this.#jump = null;
    this.#arrange();
    this.#presentedId = destination;
    const committed = this.#expectedId ?? this.#selectedId;
    if (motion?.commitsSelection && destination !== committed) {
      this.#expectedId = destination;
      this.#select(destination);
    }
    this.#publish();
  }

  #cancel() {
    this.#stopClock();
    this.#motion = null;
    this.#jump = null;
    this.#arrange();
  }

  #startClock() {
    if (this.#animation) return;
    const tick = (now: number) => {
      this.#animation = 0;
      const motion = this.#motion;
      if (!motion) return;
      const settling = motion.settling;
      if (settling) {
        if (settling.began === null) {
          // The clock starts on the first frame no page holds, at most a
          // moment after the settle was asked for, so a slide opens on its
          // first step rather than past the frames the window spent drawing.
          if (settling.holdable && this.#holds.size > 0 && now - settling.requested < SpacePager.longestHold) {
            this.#animation = requestAnimationFrame(tick);
            return;
          }
          this.#startSettleClock(now);
        }
        if ((now - settling.began!) / 1000 >= settling.settlement.duration) {
          this.#finish(settling.destinationId);
          return;
        }
      } else {
        // The strip stays under the fingers, point for point, as Windows'
        // browsers track a touchpad's swipe; the Mac bounds it at four pages
        // a second, which a Windows touchpad's swipes outrun, leaving the
        // strip trailing behind them.
        motion.offset = motion.initialOffset + motion.translation;
      }
      this.#publishFrame(now);
      if (motion.settling || motion.initialOffset + motion.translation !== motion.offset) {
        this.#animation = requestAnimationFrame(tick);
      }
    };
    this.#animation = requestAnimationFrame(tick);
  }

  /** Starts the settle's clock at `time`, if it hasn't started, and with it every leaf held at its start. */
  #startSettleClock(time: number) {
    const settling = this.#motion?.settling;
    if (!settling || settling.began !== null) return;
    settling.began = time;
    startHeldSettle(this.#settles, time);
  }

  #stopClock() {
    if (this.#animation) cancelAnimationFrame(this.#animation);
    this.#animation = 0;
  }

  /** The frame as of now, and every listener told; the pages mounted change only at a slide's ends. */
  #publish() {
    const before = this.#frame;
    this.#publishFrame();
    const after = this.#frame;
    if (before.phase !== after.phase || before.pages.join() !== after.pages.join() || before.order.join() !== after.order.join()
      || before.originId !== after.originId || before.destinationId !== after.destinationId || before.dissolve !== after.dissolve) {
      for (const listener of this.#listeners) listener();
    }
  }

  /** Tells the frame listeners where the strip stands at `time`, on the document's timeline. */
  #publishFrame(time = performance.now()) {
    const motion = this.#motion;
    const origin = motion?.originId ?? this.#presentedId;
    const originIndex = origin ? this.#order.indexOf(origin) : -1;
    let position = Math.max(0, originIndex);
    const settling = motion?.settling;
    if (settling) position = settling.settlement.position(settling.began === null ? 0 : Math.max(0, time - settling.began) / 1000);
    else if (motion) position = originIndex + motion.offset;
    const destination = motion?.settling?.destinationId ?? motion?.targetId ?? origin;
    const pages = motion
      ? [...new Set([...(motion.carried ?? []), motion.originId, motion.targetId, motion.settling?.destinationId]
        .filter((id): id is string => !!id && this.#ids.includes(id)))]
      : origin ? [origin] : [];
    const previous = this.#frame;
    const phase: PagerPhase = !motion ? "idle" : motion.settling ? "settling" : "tracking";
    const sameOrder = previous.order.join() === this.#order.join();
    const samePages = previous.pages.join() === pages.join();
    if (sameOrder && samePages && previous.position === position && previous.phase === phase
      && previous.originId === origin && previous.destinationId === destination && previous.dissolve === this.#dissolve) return;
    this.#frame = {
      order: sameOrder ? previous.order : this.#order,
      position,
      phase,
      originId: origin,
      destinationId: destination,
      pages: samePages ? previous.pages : pages,
      dissolve: this.#dissolve,
    };
    for (const listener of this.#frameListeners) listener(this.#frame);
  }
}

function reducesMotion(): boolean {
  return matchMedia("(prefers-reduced-motion: reduce)").matches;
}

/** The window's one pager: each Crest window is its own document. */
export const spacePager = new SpacePager();

/** The pager's frame as of its last change of phase or pages; not every frame. */
export function useSpacePager(): PagerFrame {
  return useSyncExternalStore(spacePager.subscribe, () => spacePager.frame);
}

/** Follows every frame of the pager, for a leaf that draws as it moves. */
export function useSpacePagerFrames(): PagerFrame {
  return useSyncExternalStore(
    (listener) => spacePager.subscribeFrames(() => listener()),
    () => spacePager.frame,
  );
}

// MARK: - Swipes from the wheel

/** blink::WebMouseWheelEvent's phase flags, as Crest's Chromium sends them with a touchpad's scroll. */
const WheelPhase = { began: 1, stationary: 2, changed: 4, ended: 8, cancelled: 16, mayBegin: 32, blocked: 64 } as const;

/**
 * A precision touchpad's scroll with its phases, as Crest's Chromium sends
 * it beside the page's wheel events (crestWheel), for the swipe to follow.
 */
export const touchpadPhases = {
  /** Whether the engine sends them; until it says so, the swipe goes by the wheel's events alone. */
  available: false,
  listeners: new Set<(wheel: ShellWheel) => void>(),
  emit(wheel: ShellWheel) {
    for (const listener of this.listeners) listener(wheel);
  },
  subscribe(listener: (wheel: ShellWheel) => void): () => void {
    this.listeners.add(listener);
    return () => void this.listeners.delete(listener);
  },
};

/** How far back the fingers' speed is measured, as the Mac's SpacePagerGesture measures it. */
const velocityWindow = 0.08;
/** How long Chromium holds a touchpad's end back for momentum (MouseWheelPhaseHandler), in seconds. */
const endHeldBack = 0.1;

/**
 * Turns a touchpad's scroll over the sidebar into Space motion, as the Mac's
 * SpacePagerGesture: a precision touchpad's horizontal swipe tracks the strip
 * point for point from the moment it begins, holds where it is while the
 * fingers rest, and is released only when they lift, either plainly or into
 * the system's momentum, which never moves the strip itself; the strip then
 * carries on at the fingers' speed and settles. The phases come from Crest's
 * Chromium (`phased`). Where they don't, as in a development window, a swipe
 * ends once its input goes quiet. A wheel's horizontal notches step one Space
 * per burst.
 */
export class SpaceSwipe {
  static readonly #quiet = 0.12;
  static readonly #burstGap = 0.35;
  /** Where a swipe may begin: inside the sidebar's gesture area, for a place in the interface. */
  readonly #inside: (x: number, y: number) => boolean;
  #axis: "undecided" | "horizontal" | "vertical" | "outside" = "outside";
  #tracking = false;
  #samples: { time: number; position: number }[] = [];
  #position = 0;
  #accumulatedX = 0;
  #accumulatedY = 0;
  #lastTime = 0;
  #stepped = false;
  #timer = 0;

  constructor(inside: (x: number, y: number) => boolean) {
    this.#inside = inside;
  }

  /**
   * Takes a touchpad event with its phases, as SpacePagerGesture takes an
   * NSEvent: a begun gesture over the sidebar decides its axis on its first
   * motion, a horizontal one tracks every change, and its end or the start of
   * its momentum releases it.
   */
  phased(wheel: ShellWheel) {
    if (wheel.momentumPhase !== 0) {
      // Momentum means the fingers have lifted: the swipe ends at their own
      // speed, and the momentum after it moves nothing.
      if (this.#tracking && wheel.momentumPhase & WheelPhase.began) this.#release(wheel.time, false);
      return;
    }
    if (wheel.phase & WheelPhase.mayBegin) return;
    if (wheel.phase & WheelPhase.began) {
      this.#finishTracking();
      this.#axis = this.#inside(wheel.x, wheel.y) ? "undecided" : "outside";
      this.#accumulatedX = 0;
      this.#accumulatedY = 0;
      this.#position = 0;
      this.#samples = [{ time: wheel.time, position: 0 }];
    }
    if (wheel.phase & (WheelPhase.ended | WheelPhase.cancelled)) {
      if (this.#tracking) {
        if (wheel.deltaX !== 0) this.#move(wheel.deltaX, wheel.time);
        // Chromium holds a lift's end back to see whether momentum follows,
        // then sends it stamped as it goes, so the fingers left that much earlier.
        const lifted = Math.max(this.#samples.at(-1)?.time ?? wheel.time, wheel.time - endHeldBack);
        this.#release(lifted, (wheel.phase & WheelPhase.cancelled) !== 0);
      }
      this.#axis = "outside";
      return;
    }
    if (!(wheel.phase & (WheelPhase.began | WheelPhase.changed))) return;
    if (this.#axis === "outside" || this.#axis === "vertical") return;
    if (this.#axis === "undecided") {
      this.#accumulatedX += wheel.deltaX;
      this.#accumulatedY += wheel.deltaY;
      if (this.#accumulatedX === 0 && this.#accumulatedY === 0) return;
      if (Math.abs(this.#accumulatedX) <= Math.abs(this.#accumulatedY)) {
        this.#axis = "vertical";
        return;
      }
      if (reducesMotion()) {
        // Without motion a swipe steps once, as a wheel's notch does.
        this.#axis = "horizontal";
        stepSpace(this.#accumulatedX > 0 ? 1 : -1);
        return;
      }
      if (!spacePager.beginTracking()) {
        this.#axis = "outside";
        return;
      }
      this.#axis = "horizontal";
      this.#tracking = true;
      this.#move(this.#accumulatedX, wheel.time);
      return;
    }
    if (this.#tracking) this.#move(wheel.deltaX, wheel.time);
  }

  /** Takes a wheel event over the sidebar; true when it moved Spaces, or belongs to a swipe that did, and the event is spent. */
  handle(event: WheelEvent): boolean {
    const precise = isPrecise(event);
    // The phases drive a touchpad's swipe; its wheel events are only kept from scrolling what the swipe has claimed.
    if (precise && touchpadPhases.available) return this.#axis === "horizontal";
    const time = event.timeStamp / 1000;
    if (time - this.#lastTime > (precise ? SpaceSwipe.#quiet : SpaceSwipe.#burstGap) && !this.#tracking) {
      this.#axis = "undecided";
      this.#accumulatedX = 0;
      this.#accumulatedY = 0;
      this.#stepped = false;
    }
    this.#lastTime = time;
    // Content moves with the fingers: a swipe to the left brings the next Space in.
    const dx = event.deltaMode === 1 ? event.deltaX * 16 : event.deltaX;
    const dy = event.deltaMode === 1 ? event.deltaY * 16 : event.deltaY;
    if (this.#axis === "vertical" || this.#axis === "outside") return false;
    if (this.#axis === "undecided") {
      this.#accumulatedX += dx;
      this.#accumulatedY += dy;
      const distance = precise ? 8 : 0.25;
      if (Math.abs(this.#accumulatedY) >= distance && Math.abs(this.#accumulatedY) >= Math.abs(this.#accumulatedX) * 1.35) {
        this.#axis = "vertical";
        return false;
      }
      if (Math.abs(this.#accumulatedX) < distance || Math.abs(this.#accumulatedX) < Math.abs(this.#accumulatedY) * 1.35) return false;
      this.#axis = "horizontal";
      if (precise && !reducesMotion()) {
        if (!spacePager.beginTracking()) {
          this.#axis = "outside";
          return false;
        }
        this.#tracking = true;
        this.#position = 0;
        this.#samples = [{ time, position: 0 }];
        this.#move(this.#accumulatedX, time);
        this.#endWhenQuiet();
      } else if (!this.#stepped) {
        this.#stepped = true;
        stepSpace(this.#accumulatedX > 0 ? 1 : -1);
      }
      return true;
    }
    if (this.#tracking) {
      this.#move(dx, time);
      this.#endWhenQuiet();
    }
    return true;
  }

  /** Stops listening for a swipe that is under way, releasing it where it is. */
  dispose() {
    this.#finishTracking();
  }

  #move(dx: number, time: number) {
    this.#position += dx;
    this.#samples.push({ time, position: this.#position });
    this.#samples = this.#samples.filter((sample) => sample.time >= time - velocityWindow);
    spacePager.track(dx);
  }

  /** Without phases, a swipe ends when its input goes quiet. */
  #endWhenQuiet() {
    clearTimeout(this.#timer);
    this.#timer = window.setTimeout(() => this.#release(this.#lastTime + SpaceSwipe.#quiet, false), SpaceSwipe.#quiet * 1000);
  }

  #finishTracking() {
    if (this.#tracking) this.#release(this.#samples.at(-1)?.time ?? 0, true);
  }

  /**
   * Releases the swipe at `time` with the fingers' speed over the last 80 ms,
   * as the Mac measures it: none when they had rested longer than that.
   */
  #release(time: number, cancelled: boolean) {
    if (!this.#tracking) return;
    clearTimeout(this.#timer);
    this.#tracking = false;
    const first = this.#samples[0];
    const last = this.#samples.at(-1);
    const velocity = first && last && last.time > first.time && time - last.time <= velocityWindow
      ? (last.position - first.position) / (last.time - first.time) : 0;
    spacePager.release(velocity, cancelled);
  }
}

/** A precision touchpad's deltas: pixels, in steps a wheel's notches never take. */
function isPrecise(event: WheelEvent): boolean {
  if (event.deltaMode !== 0) return false;
  const legacy = event as WheelEvent & { wheelDeltaX?: number; wheelDeltaY?: number };
  const notch = (value: number | undefined) => value !== undefined && value !== 0 && value % 120 === 0;
  return !notch(legacy.wheelDeltaX) && !notch(legacy.wheelDeltaY);
}

let stepSpace: (direction: 1 | -1) => void = () => {};

/** How a wheel's step asks for the next or previous Space: the window's command. */
export function setSpaceStepper(step: (direction: 1 | -1) => void) {
  stepSpace = step;
}
