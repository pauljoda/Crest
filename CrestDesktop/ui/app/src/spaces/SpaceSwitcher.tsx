import type { SpaceState } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { animate, AnimatePresence, motion } from "motion/react";
import { type ReactNode, type RefObject, useLayoutEffect, useRef, useState } from "react";

import { foregroundTone } from "../branding";
import { Symbol } from "../symbols";
import { interpolate, type PagerFrame, useSpacePagerFrames } from "./space-pager";
import { SpaceSymbolArtwork } from "./SpaceIdentity";

/**
 * The sidebar's Space switcher, as the Mac's compact strip
 * (BrowserSpaceSwitcherCompactStrip): the sidebar toggle and the lists
 * button held clear at either edge, and between them a centred track of the
 * Spaces' crests whose selection follows the Space pager, wrapped in a
 * group's outline while it shows a Space of a group.
 */
export function SpaceSwitcher({ spaces, selectedId, onSelect, leading, trailing }: {
  spaces: readonly SpaceState[];
  selectedId: string;
  onSelect: (spaceId: string) => void;
  leading: ReactNode;
  trailing: ReactNode;
}) {
  const strip = useRef<HTMLDivElement>(null);
  const width = useWidth(strip);
  const frame = useSpacePagerFrames();
  const showsDots = spaceIconDisplay() === "dots";
  const viewport = pickerViewportWidth(width, leading ? utilityButtonSize : 0, trailing ? utilityButtonSize : 0);
  const base = showsDots ? dotted(compact) : compact;
  const scale = fittedScale(base, spaces.length, viewport);
  const style = scaled(base, scale);
  const contentWidth = style.contentWidth(spaces.length);
  const overflows = contentWidth > viewport;
  const laneWidth = Math.max(0, viewport - (overflows ? 2 * overflowButtonWidth : 0));
  const geometry: TrackGeometry = { ...style, count: spaces.length, offset: Math.max(0, (laneWidth - contentWidth) / 2) };
  // At rest, the Space the strip shows: a swipe settles before the window
  // takes the Space it settled on, and the selection stays where it landed
  // rather than going back for the moment between.
  const restingId = frame.phase === "idle" && frame.originId && spaces.some((space) => space.id === frame.originId)
    ? frame.originId : selectedId;
  const position = pickerPosition(frame, spaces, restingId);
  const lane = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ previous: null as number | null, next: null as number | null });

  // The lane keeps the selection centred as it moves, as the Mac's clip view follows the pager.
  const centred = useRef<number | null>(null);
  useLayoutEffect(() => {
    const element = lane.current;
    if (!element) return;
    if (centred.current === position && element.dataset.width === `${laneWidth}`) return;
    centred.current = position;
    element.dataset.width = `${laneWidth}`;
    // A lane its Spaces fit stays where it is. Scrolling it, or reading where
    // it stands, would lay the window out again in the middle of each frame
    // the pager moves.
    if (!overflows) {
      setEdges((current) => (current.previous === null && current.next === null ? current : { previous: null, next: null }));
      return;
    }
    const at = segmentFrame(geometry, position);
    if (at) element.scrollLeft = Math.max(0, at.x + at.width / 2 - laneWidth / 2);
    setEdges(overflowEdges(element, geometry));
  });

  const reveal = (forward: boolean) => {
    const element = lane.current;
    const target = forward ? edges.next : edges.previous;
    if (!element || target === null) return;
    const start = geometry.offset + geometry.trackPadding + target * geometry.segmentWidth;
    const goal = forward ? start : start + geometry.segmentWidth - laneWidth;
    const limit = element.scrollWidth - element.clientWidth;
    void animate(element.scrollLeft, Math.min(limit, Math.max(0, goal)), {
      ...tokens.scrollAlignment,
      onUpdate: (value) => { element.scrollLeft = value; },
      onComplete: () => setEdges(overflowEdges(element, geometry)),
    });
  };

  return (
    <div ref={strip} className="space-strip" role="group" aria-label="Spaces">
      <div className="space-strip-utilities">
        {leading}
        <span className="space-strip-spacer" />
        {trailing}
      </div>
      <div className="space-picker" style={{ width: viewport }}>
        {overflows && (
          <OverflowButton forward={false} enabled={edges.previous !== null} height={style.height} onClick={() => reveal(false)} />
        )}
        <div ref={lane} className="space-picker-lane" style={{ width: laneWidth, height: style.height, borderRadius: wellRadius(style) }}
          onScroll={(event) => setEdges(overflowEdges(event.currentTarget, geometry))}>
          <div className={`space-picker-track${showsDots ? " dotted" : ""}`} aria-label="Space"
            style={{
              marginInlineStart: geometry.offset, padding: style.trackPadding, borderRadius: wellRadius(style),
              background: showsDots ? undefined : `rgb(0 0 0 / ${toneAt(spaces, position).well})`,
            }}>
            {!showsDots && <Highlight spaces={spaces} geometry={geometry} position={position} />}
            {spaces.map((space) => (
              <Segment key={space.id} space={space} selected={space.id === restingId} width={style.segmentWidth} height={style.segmentHeight}
                scale={scale} showsDots={showsDots} dotOpacity={showsDots ? dotOpacity(space, spaces, frame, restingId) : 1}
                onSelect={() => onSelect(space.id)} />
            ))}
          </div>
        </div>
        {overflows && (
          <OverflowButton forward enabled={edges.next !== null} height={style.height} onClick={() => reveal(true)} />
        )}
      </div>
    </div>
  );
}

// MARK: - Metrics

/** BrowserSpaceSwitcherLayout. */
const utilityButtonSize = 32;
const stripHorizontalInset = 12;
const stripSpacing = 2;
const overflowButtonWidth = 28;

/** CrestSpaceIconPickerMetrics and the pointer's picker style. */
interface PickerStyle {
  readonly height: number;
  readonly trackPadding: number;
  readonly cornerRadius: number;
  readonly segmentWidth: number;
  readonly segmentHeight: number;
  readonly contentWidth: (count: number) => number;
}

interface BaseStyle { readonly segmentHeight: number; readonly trackPadding: number; readonly cornerRadius: number; readonly segmentWidth: number }

const compact: BaseStyle = { segmentHeight: 30, trackPadding: 3, cornerRadius: 8, segmentWidth: 40 };

/** Dots pack together in segments as wide as a dot's room under a pointer. */
function dotted(style: BaseStyle): BaseStyle {
  return { ...style, segmentWidth: 16 };
}

const evenPoints = (length: number) => 2 * Math.round(length / 2);

/** CrestSpaceIconPickerStyle.scaled(by:): segments for a crest `scale` times its size, the track keeping its shape. */
function scaled(style: BaseStyle, scale: number): PickerStyle {
  const segmentHeight = evenPoints(style.segmentHeight * scale);
  const shape = segmentHeight / style.segmentHeight;
  const trackPadding = Math.round(style.trackPadding * shape);
  const segmentWidth = evenPoints(style.segmentWidth * scale);
  return {
    height: segmentHeight + 2 * trackPadding,
    trackPadding,
    cornerRadius: style.cornerRadius * shape,
    segmentWidth,
    segmentHeight,
    contentWidth: (count) => (count > 0 ? 2 * trackPadding + count * segmentWidth : 0),
  };
}

/** BrowserSpaceIconSizing.automatic: the largest step from 1 down to 0.3 at which every Space fits. */
function fittedScale(style: BaseStyle, count: number, width: number): number {
  const chosen = manualIconScale();
  if (chosen !== null) return chosen;
  let narrowest = { scale: 1, width: Infinity };
  for (let percent = 100; percent >= 30; percent -= 5) {
    const candidate = scaled(style, percent / 100).contentWidth(count);
    if (candidate <= width) return percent / 100;
    if (candidate < narrowest.width) narrowest = { scale: percent / 100, width: candidate };
  }
  return narrowest.scale;
}

/** The width the picker has between the utilities, reserving the larger side on both so it stays centred. */
function pickerViewportWidth(available: number, leading: number, trailing: number): number {
  const reservation = (width: number) => (width > 0 ? width + stripSpacing : 0);
  const content = Math.max(0, available - 2 * stripHorizontalInset);
  return Math.max(0, content - 2 * Math.max(reservation(leading), reservation(trailing)));
}

/** The person's Space icons on this device: crests, or dots. */
function spaceIconDisplay(): "icons" | "dots" {
  try {
    return localStorage.getItem("crest.appearance.space-icons") === "dots" ? "dots" : "icons";
  } catch {
    return "icons";
  }
}

/** The scale the person set for Space icons, or null while they fit the strip. */
function manualIconScale(): number | null {
  try {
    if (localStorage.getItem("crest.appearance.spaceIconSizing") !== "manual") return null;
    const value = Number(localStorage.getItem("crest.appearance.spaceIconScale"));
    return Number.isFinite(value) ? Math.min(1.5, Math.max(0.3, value)) : 1;
  } catch {
    return null;
  }
}

// MARK: - Position and frames

interface TrackGeometry extends PickerStyle {
  readonly count: number;
  /** How far the track stands in from the lane's leading edge, centred while it fits. */
  readonly offset: number;
}

interface Frame { readonly x: number; readonly y: number; readonly width: number; readonly height: number }

/**
 * Where the pager stands among the picker's own order, as Snapshot.place:
 * a jump moves the pager along another order while the icons keep their places.
 */
function pickerPosition(frame: PagerFrame, spaces: readonly SpaceState[], selectedId: string): number {
  const ids = spaces.map((space) => space.id);
  const resting = Math.max(0, ids.indexOf(selectedId));
  if (frame.phase === "idle" || frame.order.length !== ids.length) return resting;
  if (frame.order.every((id, index) => id === ids[index])) return frame.position;
  const sample = interpolate(frame.position, frame.order.length);
  if (!sample) return resting;
  const lower = ids.indexOf(frame.order[sample.lower]);
  const upper = ids.indexOf(frame.order[sample.upper]);
  if (lower < 0 || upper < 0) return resting;
  return lower + (upper - lower) * sample.fraction;
}

/** The segment at `index` in the track's own coordinates. */
function segmentAt(geometry: TrackGeometry, index: number): Frame {
  return { x: geometry.trackPadding + index * geometry.segmentWidth, y: geometry.trackPadding, width: geometry.segmentWidth, height: geometry.segmentHeight };
}

/** The segment the pager shows at `position`, between the two either side of it; in the lane's coordinates. */
function segmentFrame(geometry: TrackGeometry, position: number): Frame | null {
  const sample = interpolate(position, geometry.count);
  if (!sample) return null;
  const frame = lerpFrame(segmentAt(geometry, sample.lower), segmentAt(geometry, sample.upper), sample.fraction);
  return { ...frame, x: frame.x + geometry.offset };
}

function lerpFrame(start: Frame, end: Frame, fraction: number): Frame {
  return {
    x: start.x + (end.x - start.x) * fraction,
    y: start.y + (end.y - start.y) * fraction,
    width: start.width + (end.width - start.width) * fraction,
    height: start.height + (end.height - start.height) * fraction,
  };
}

function union(frames: readonly Frame[]): Frame {
  const left = Math.min(...frames.map((frame) => frame.x));
  const top = Math.min(...frames.map((frame) => frame.y));
  const right = Math.max(...frames.map((frame) => frame.x + frame.width));
  const bottom = Math.max(...frames.map((frame) => frame.y + frame.height));
  return { x: left, y: top, width: right - left, height: bottom - top };
}

/** BrowserSpacePickerOverflow: the first Space hidden each way, if any. */
function overflowEdges(lane: HTMLElement, geometry: TrackGeometry) {
  const left = lane.scrollLeft;
  const right = left + lane.clientWidth;
  const index = (x: number) => Math.min(geometry.count - 1, Math.max(0, Math.floor((x - geometry.offset - geometry.trackPadding) / geometry.segmentWidth)));
  return {
    previous: left > 0.5 ? index(left) : null,
    next: right < lane.scrollWidth - 0.5 ? index(right) : null,
  };
}

// MARK: - Selection

/**
 * The selector and a group's highlight, as PlatformSpacePickerPresentation
 * draws them: white, at the strength the picker's tone over each Space's
 * sidebar gives, blended along the pager, with no outline; inside a group,
 * the selector stands three points into the group's highlight, its corners
 * concentric with it.
 */
function Highlight({ spaces, geometry, position }: { spaces: readonly SpaceState[]; geometry: TrackGeometry; position: number }) {
  const groups = groupRanges(spaces.map((space) => space.profileId));
  const outlinesGroups = groups.some((group) => group.last > group.first) && new Set(groups).size > 1;
  const sample = interpolate(position, geometry.count);
  if (!sample) return null;
  const tone = toneAt(spaces, position);

  let outline: { frame: Frame; opacity: number } | null = null;
  if (outlinesGroups) {
    const wrap = (index: number) => {
      const group = groups[index];
      return union(Array.from({ length: group.last - group.first + 1 }, (_, offset) => segmentAt(geometry, group.first + offset)));
    };
    const grouped = (index: number) => (groups[index].last > groups[index].first ? 1 : 0);
    outline = {
      frame: lerpFrame(wrap(sample.lower), wrap(sample.upper), sample.fraction),
      opacity: grouped(sample.lower) + (grouped(sample.upper) - grouped(sample.lower)) * sample.fraction,
    };
  }
  const inset = groupSelectionInset * (outline?.opacity ?? 0);
  const segment = lerpFrame(segmentAt(geometry, sample.lower), segmentAt(geometry, sample.upper), sample.fraction);
  return (
    <>
      {outline && outline.opacity > 0 && (
        <span className="space-picker-outline" aria-hidden style={{
          left: outline.frame.x, top: outline.frame.y, width: outline.frame.width, height: outline.frame.height,
          borderRadius: geometry.cornerRadius, opacity: outline.opacity, background: `rgb(255 255 255 / ${tone.group})`,
        }} />
      )}
      <span className="space-picker-selection" aria-hidden style={{
        left: segment.x + inset, top: segment.y + inset, width: segment.width - 2 * inset, height: segment.height - 2 * inset,
        borderRadius: Math.max(0, geometry.cornerRadius - inset), background: `rgb(255 255 255 / ${tone.selector})`,
      }} />
    </>
  );
}

const groupSelectionInset = 3;

/**
 * CrestSpaceIconPickerTone: how the picker's surfaces show over a sidebar,
 * a black well recessed into it, a soft white highlight across the shown
 * Space's group, and a brighter white selector. Over a dark sidebar, whose
 * text reads light, the well deepens and the highlights stay faint; over a
 * light one the well is a shade and the highlights near white.
 */
const tones = {
  onDark: { well: 0.22, group: 0.09, selector: 0.22 },
  onLight: { well: 0.07, group: 0.4, selector: 0.85 },
} as const;

/** The tone over each Space's sidebar, blended between the two the pager stands between. */
function toneAt(spaces: readonly SpaceState[], position: number): { well: number; group: number; selector: number } {
  const toneOf = (index: number) => (spaces[index] && foregroundTone(spaces[index].settings.look) === "light" ? tones.onDark : tones.onLight);
  const sample = interpolate(position, spaces.length);
  const lower = toneOf(sample?.lower ?? 0);
  const upper = toneOf(sample?.upper ?? 0);
  const fraction = sample?.fraction ?? 0;
  const mixed = (key: "well" | "group" | "selector") => lower[key] + (upper[key] - lower[key]) * fraction;
  return { well: mixed("well"), group: mixed("group"), selector: mixed("selector") };
}

/** The well's corner, concentric with a segment's: the segment's grown by the well's padding. */
function wellRadius(style: { readonly cornerRadius: number; readonly trackPadding: number }): number {
  return style.cornerRadius + style.trackPadding;
}

/** SpacePickerGroupOutline: each Space's group, the run of Spaces that browse with one profile. */
function groupRanges(profiles: readonly string[]): { first: number; last: number }[] {
  const groups: { first: number; last: number }[] = [];
  let first = 0;
  profiles.forEach((profile, index) => {
    if (index === profiles.length - 1 || profiles[index + 1] !== profile) {
      const group = { first, last: index };
      for (let member = first; member <= index; member++) groups[member] = group;
      first = index + 1;
    }
  });
  return groups;
}

// MARK: - Segments

/** BrowserSpaceDot.Field: the shown Space's dot brightest, its group's lighter, the rest dark, blended along the pager. */
function dotOpacity(space: SpaceState, spaces: readonly SpaceState[], frame: PagerFrame, selectedId: string): number {
  let from = selectedId;
  let to = selectedId;
  let fraction = 0;
  const sample = frame.phase === "idle" ? null : interpolate(frame.position, frame.order.length);
  if (sample) {
    from = frame.order[sample.lower];
    to = frame.order[sample.upper];
    fraction = sample.fraction;
  }
  const profileOf = (id: string) => spaces.find((candidate) => candidate.id === id)?.profileId;
  const shares = (other: string) => profileOf(other) === space.profileId;
  const shown = (space.id === from ? 1 - fraction : 0) + (space.id === to ? fraction : 0);
  const grouped = (shares(from) ? 1 - fraction : 0) + (shares(to) ? fraction : 0);
  return 0.18 + (0.45 - 0.18) * grouped + (1 - 0.45) * shown;
}

function Segment({ space, selected, width, height, scale, showsDots, dotOpacity: opacity, onSelect }: {
  space: SpaceState;
  selected: boolean;
  width: number;
  height: number;
  scale: number;
  showsDots: boolean;
  dotOpacity: number;
  onSelect: () => void;
}) {
  const { name, look, symbol, requiresAuthentication: locked } = space.settings;
  const iconSize = 2 * Math.round((24 * scale) / 2);
  const value = `${selected ? "Selected, " : ""}${locked ? "Private Space" : "Open Space"}`;
  const diameter = 7 * Math.max(scale, 0.6);
  return (
    <button
      className="space-segment"
      style={{ width, height }}
      title={name}
      aria-label={name}
      aria-description={`${value}. Select this Space, or drop a tab to move it here`}
      aria-current={selected ? "true" : undefined}
      // A lifted tab drops on another Space's segment.
      data-space={selected ? undefined : space.id}
      onClick={onSelect}
    >
      <AnimatePresence initial={false} mode="popLayout">
        {showsDots ? (
          <motion.span key="dot" className="space-dot-mark" aria-hidden
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.styleChange}
            style={{
              width: diameter, height: diameter, opacity,
              boxShadow: `inset 0 0 0 ${locked ? 1.5 : diameter / 2}px rgb(var(--primary-rgb))`,
            }} />
        ) : (
          <motion.span key="crest" className="space-segment-icon"
            initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={tokens.styleChange}>
            <SpaceSymbolArtwork symbol={symbol} branding={look} locked={locked} size={iconSize} lockSize={Math.round(6 * scale)} />
          </motion.span>
        )}
      </AnimatePresence>
    </button>
  );
}

function OverflowButton({ forward, enabled, height, onClick }: { forward: boolean; enabled: boolean; height: number; onClick: () => void }) {
  const title = forward ? "Show Next Spaces" : "Show Previous Spaces";
  return (
    <button className="space-picker-overflow" style={{ width: overflowButtonWidth, height }} disabled={!enabled}
      title={title} aria-label={title} onClick={onClick}>
      <Symbol name={forward ? "chevron.forward" : "chevron.backward"} size={11} strokeWidth={2.5} />
    </button>
  );
}

function useWidth(element: RefObject<HTMLElement | null>): number {
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    setWidth(target.getBoundingClientRect().width);
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width + 0));
    observer.observe(target);
    return () => observer.disconnect();
  }, [element]);
  return width;
}
