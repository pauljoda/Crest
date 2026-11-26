<script lang="ts" module>
  import type { SpaceState } from "@crest/contracts";

  import { spaceIconDisplay, spaceIconScale, spaceIconSizing } from "../appearance.svelte";
  import { foregroundTone } from "../branding";
  import { interpolate, type PagerFrame } from "./space-pager";

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
    if (spaceIconSizing.current === "manual" && spaceIconDisplay.current === "icons") return spaceIconScale.current;
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

  /** Where the selector and a group's highlight stand, and how strongly each shows. */
  interface HighlightFrames {
    readonly outline: { readonly frame: Frame; readonly opacity: number; readonly background: string } | null;
    readonly selection: { readonly frame: Frame; readonly cornerRadius: number; readonly background: string };
  }

  /**
   * The selector and a group's highlight, as PlatformSpacePickerPresentation
   * draws them: white, at the strength the picker's tone over each Space's
   * sidebar gives, blended along the pager, with no outline; inside a group,
   * the selector stands three points into the group's highlight, its corners
   * concentric with it.
   */
  function highlightFrames(spaces: readonly SpaceState[], geometry: TrackGeometry, position: number): HighlightFrames | null {
    const groups = groupRanges(spaces.map((space) => space.profileId));
    const outlinesGroups = groups.some((group) => group.last > group.first) && new Set(groups).size > 1;
    const sample = interpolate(position, geometry.count);
    if (!sample) return null;
    const tone = toneAt(spaces, position);

    let outline: { frame: Frame; opacity: number; background: string } | null = null;
    if (outlinesGroups) {
      const wrap = (index: number) => {
        const group = groups[index];
        return union(Array.from({ length: group.last - group.first + 1 }, (_, offset) => segmentAt(geometry, group.first + offset)));
      };
      const grouped = (index: number) => (groups[index].last > groups[index].first ? 1 : 0);
      outline = {
        frame: lerpFrame(wrap(sample.lower), wrap(sample.upper), sample.fraction),
        opacity: grouped(sample.lower) + (grouped(sample.upper) - grouped(sample.lower)) * sample.fraction,
        background: `rgb(255 255 255 / ${tone.group})`,
      };
    }
    const inset = groupSelectionInset * (outline?.opacity ?? 0);
    const segment = lerpFrame(segmentAt(geometry, sample.lower), segmentAt(geometry, sample.upper), sample.fraction);
    return {
      outline,
      selection: {
        frame: { x: segment.x + inset, y: segment.y + inset, width: segment.width - 2 * inset, height: segment.height - 2 * inset },
        cornerRadius: Math.max(0, geometry.cornerRadius - inset),
        background: `rgb(255 255 255 / ${tone.selector})`,
      },
    };
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
</script>

<script lang="ts">
  import { motion as tokens } from "@crest/design";
  import { type Snippet, untrack } from "svelte";

  import { presence, timed } from "../motion";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { useSpacePagerFrames } from "./space-pager";
  import { SpaceSymbolArtwork } from "./SpaceIdentity";

  /**
   * The sidebar's Space switcher, as the Mac's compact strip
   * (BrowserSpaceSwitcherCompactStrip): the sidebar toggle and the lists
   * button held clear at either edge, and between them a centred track of the
   * Spaces' crests whose selection follows the Space pager, wrapped in a
   * group's outline while it shows a Space of a group.
   */
  let { spaces, selectedId, onSelect, leading, trailing }: {
    spaces: readonly SpaceState[];
    selectedId: string;
    onSelect: (spaceId: string) => void;
    leading?: Snippet;
    trailing?: Snippet;
  } = $props();

  let strip: HTMLDivElement | undefined;
  let width = $state(0);
  $effect(() => {
    const target = strip;
    if (!target) return;
    width = target.getBoundingClientRect().width;
    const observer = new ResizeObserver(([entry]) => (width = entry.contentRect.width + 0));
    observer.observe(target);
    return () => observer.disconnect();
  });

  // Every frame of the pager draws the strip again, as it moves; the
  // person's icon settings are read afresh with each.
  const frame = $derived(useSpacePagerFrames());
  const showsDots = $derived(spaceIconDisplay.current === "dots");
  const viewport = $derived(pickerViewportWidth(width, leading ? utilityButtonSize : 0, trailing ? utilityButtonSize : 0));
  const base = $derived(showsDots ? dotted(compact) : compact);
  const scale = $derived((useSpacePagerFrames(), fittedScale(base, spaces.length, viewport)));
  const style = $derived(scaled(base, scale));
  const contentWidth = $derived(style.contentWidth(spaces.length));
  const overflows = $derived(contentWidth > viewport);
  const laneWidth = $derived(Math.max(0, viewport - (overflows ? 2 * overflowButtonWidth : 0)));
  const geometry: TrackGeometry = $derived({ ...style, count: spaces.length, offset: Math.max(0, (laneWidth - contentWidth) / 2) });
  // At rest, the Space the strip shows: a swipe settles before the window
  // takes the Space it settled on, and the selection stays where it landed
  // rather than going back for the moment between.
  const restingId = $derived(frame.phase === "idle" && frame.originId && spaces.some((space) => space.id === frame.originId)
    ? frame.originId : selectedId);
  const position = $derived(pickerPosition(frame, spaces, restingId));
  const highlight = $derived(showsDots ? null : highlightFrames(spaces, geometry, position));
  let lane: HTMLDivElement | undefined;
  let edges = $state.raw({ previous: null as number | null, next: null as number | null });

  // The lane keeps the selection centred as it moves, as the Mac's clip view follows the pager.
  let centred: number | null = null;
  $effect(() => {
    void [position, laneWidth, overflows, geometry];
    untrack(() => {
      const element = lane;
      if (!element) return;
      if (centred === position && element.dataset.width === `${laneWidth}`) return;
      centred = position;
      element.dataset.width = `${laneWidth}`;
      // A lane its Spaces fit stays where it is. Scrolling it, or reading where
      // it stands, would lay the window out again in the middle of each frame
      // the pager moves.
      if (!overflows) {
        if (edges.previous !== null || edges.next !== null) edges = { previous: null, next: null };
        return;
      }
      const at = segmentFrame(geometry, position);
      if (at) element.scrollLeft = Math.max(0, at.x + at.width / 2 - laneWidth / 2);
      edges = overflowEdges(element, geometry);
    });
  });

  let scrolling: number | null = null;
  const reveal = (forward: boolean) => {
    const element = lane;
    const target = forward ? edges.next : edges.previous;
    if (!element || target === null) return;
    const shape = geometry;
    const start = shape.offset + shape.trackPadding + target * shape.segmentWidth;
    const goal = forward ? start : start + shape.segmentWidth - laneWidth;
    const limit = element.scrollWidth - element.clientWidth;
    // The lane scrolls there on the token's spring, a step each frame, and
    // says which Spaces lie beyond its edges once it arrives.
    const from = element.scrollLeft;
    const to = Math.min(limit, Math.max(0, goal));
    const { duration, easing } = timed(tokens.scrollAlignment);
    if (scrolling !== null) cancelAnimationFrame(scrolling);
    let began: number | null = null;
    const step = (now: number) => {
      began ??= now;
      const progress = duration > 0 ? Math.min(1, (now - began) / duration) : 1;
      element.scrollLeft = from + (to - from) * easing(progress);
      if (progress < 1) {
        scrolling = requestAnimationFrame(step);
        return;
      }
      scrolling = null;
      edges = overflowEdges(element, shape);
    };
    scrolling = requestAnimationFrame(step);
  };
</script>

{#snippet overflowButton(forward: boolean, enabled: boolean)}
  {@const title = forward ? "Show Next Spaces" : "Show Previous Spaces"}
  <button class="space-picker-overflow" style:width="{overflowButtonWidth}px" style:height="{style.height}px" disabled={!enabled}
    {title} aria-label={title} onclick={() => reveal(forward)}>
    <SymbolIcon name={forward ? "chevron.forward" : "chevron.backward"} size={11} strokeWidth={2.5} />
  </button>
{/snippet}

<div bind:this={strip} class="space-strip" role="group" aria-label="Spaces">
  <div class="space-strip-utilities">
    {@render leading?.()}
    <span class="space-strip-spacer"></span>
    {@render trailing?.()}
  </div>
  <div class="space-picker" style:width="{viewport}px">
    {#if overflows}
      {@render overflowButton(false, edges.previous !== null)}
    {/if}
    <div bind:this={lane} class="space-picker-lane" style:width="{laneWidth}px" style:height="{style.height}px"
      style:border-radius="{wellRadius(style)}px" onscroll={(event) => (edges = overflowEdges(event.currentTarget, geometry))}>
      <div class={["space-picker-track", showsDots && "dotted"]} aria-label="Space"
        style:margin-inline-start="{geometry.offset}px" style:padding="{style.trackPadding}px" style:border-radius="{wellRadius(style)}px"
        style:background={showsDots ? undefined : `rgb(0 0 0 / ${toneAt(spaces, position).well})`}>
        {#if highlight}
          {@const outline = highlight.outline}
          {@const selection = highlight.selection}
          {#if outline && outline.opacity > 0}
            <span class="space-picker-outline" aria-hidden="true" style:left="{outline.frame.x}px" style:top="{outline.frame.y}px"
              style:width="{outline.frame.width}px" style:height="{outline.frame.height}px" style:border-radius="{geometry.cornerRadius}px"
              style:opacity={outline.opacity} style:background={outline.background}></span>
          {/if}
          <span class="space-picker-selection" aria-hidden="true" style:left="{selection.frame.x}px" style:top="{selection.frame.y}px"
            style:width="{selection.frame.width}px" style:height="{selection.frame.height}px" style:border-radius="{selection.cornerRadius}px"
            style:background={selection.background}></span>
        {/if}
        {#each spaces as space (space.id)}
          {@const { name, look, symbol, requiresAuthentication: locked } = space.settings}
          {@const selected = space.id === restingId}
          {@const value = `${selected ? "Selected, " : ""}${locked ? "Private Space" : "Open Space"}`}
          {@const diameter = 7 * Math.max(scale, 0.6)}
          <!-- A lifted tab drops on another Space's segment, which names its Space in data-space. The description goes
               by spread, as Svelte's element types don't know aria-description yet. -->
          <button
            class="space-segment"
            style:width="{style.segmentWidth}px"
            style:height="{style.segmentHeight}px"
            title={name}
            aria-label={name}
            {...{ "aria-description": `${value}. Select this Space, or drop a tab to move it here` }}
            aria-current={selected ? "true" : undefined}
            data-space={selected ? undefined : space.id}
            onclick={() => onSelect(space.id)}
          >
            {#if showsDots}
              <span class="space-dot-mark" aria-hidden="true"
                in:presence={{ pose: { opacity: 0 }, timing: tokens.styleChange }}
                out:presence={{ pose: { opacity: 0 }, timing: tokens.styleChange, pop: true }}
                style:width="{diameter}px" style:height="{diameter}px" style:opacity={dotOpacity(space, spaces, frame, restingId)}
                style:box-shadow={`inset 0 0 0 ${locked ? 1.5 : diameter / 2}px rgb(var(--primary-rgb))`}></span>
            {:else}
              <span class="space-segment-icon"
                in:presence={{ pose: { opacity: 0 }, timing: tokens.styleChange }}
                out:presence={{ pose: { opacity: 0 }, timing: tokens.styleChange, pop: true }}>
                <SpaceSymbolArtwork {symbol} branding={look} {locked} size={2 * Math.round((24 * scale) / 2)} lockSize={Math.round(6 * scale)} />
              </span>
            {/if}
          </button>
        {/each}
      </div>
    </div>
    {#if overflows}
      {@render overflowButton(true, edges.next !== null)}
    {/if}
  </div>
</div>
