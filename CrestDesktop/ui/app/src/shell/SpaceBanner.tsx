import type { SpaceBranding, SpaceState } from "@crest/contracts";
import { type RefObject, useEffect, useId, useLayoutEffect, useRef, useState } from "react";

import { type FillBox, fillPaint, type SpaceFill, sidebarFill, slotFill } from "../spaces/space-fills";
import {
  animateSettle, applyLeafStyle, type LeafStyle, type PagerFrame, placedIndex, spacePager, stopSettle, useSpacePager,
} from "../spaces/space-pager";

/**
 * The Spaces' banners behind the window, drawn as the Mac draws each
 * (BrowserSpaceBannerBackground): the window's background, the Space's
 * pattern or gradient at the look's strength, a fade that keeps the chrome
 * readable, and the look's grain. As the Space pager moves, they blend as the
 * Mac's SpaceBackdropBlend does: stacked in the strip's order, each fading in
 * over the one before it as the strip reaches it. The shown Space's
 * neighbours wait drawn beneath it, unseen, each on its layer, so a slide
 * fades in banners the compositor already holds.
 */
export function SpaceBanner({ spaces, spaceId }: { spaces: readonly SpaceState[]; spaceId: string }) {
  const frame = useRef<HTMLDivElement>(null);
  const size = useElementSize(frame);
  const pager = useSpacePager();
  const layers = useRef(new Map<string, HTMLDivElement>());
  const shown = [...new Set([...pager.pages, spaceId, ...pager.prepared])]
    .map((id) => spaces.find((space) => space.id === id))
    .filter((space): space is SpaceState => !!space);
  const shownIds = shown.map((space) => space.id).join();
  useLayoutEffect(() => spacePager.subscribeFrames((current) => blend(current, layers.current, spaceId)), [spaceId, shownIds]);
  return (
    <div ref={frame} className="space-banner" aria-hidden>
      {shown.map((space) => (
        <div key={space.id} className="space-banner-layer"
          ref={(element) => {
            if (element) layers.current.set(space.id, element);
            else layers.current.delete(space.id);
          }}>
          {size && <BannerLayers branding={space.settings.look} width={size.width} height={size.height} />}
        </div>
      ))}
    </div>
  );
}

/** A banner's opacity at the pager's position: clamp(position − index + 1), stacked by its place in the strip. */
function bannerStyle(id: string, frame: PagerFrame, spaceId: string): LeafStyle {
  const count = frame.order.length;
  const index = frame.order.indexOf(id);
  if (frame.phase === "idle" || index < 0) {
    // At rest only the Space shown; one the pager hasn't taken up yet waits unseen.
    const resting = frame.phase === "idle" && frame.originId ? frame.originId : spaceId;
    return { opacity: id === resting ? "1" : "0", zIndex: id === resting ? "1" : "0" };
  }
  // A neighbour the slide doesn't take up stays unseen beneath it.
  if (!frame.pages.includes(id)) return { opacity: "0", zIndex: "0" };
  const placed = placedIndex(index, frame.position, count);
  return { zIndex: `${placed + count + 1}`, opacity: `${Math.min(1, Math.max(0, frame.position - placed + 1))}` };
}

/** Blends the banners: a settle on the compositor, a swipe and rest each frame. */
function blend(frame: PagerFrame, layers: ReadonlyMap<string, HTMLDivElement>, spaceId: string) {
  const settle = frame.phase === "settling" ? spacePager.settle : null;
  for (const [id, element] of layers) {
    if (settle) {
      animateSettle(element, settle, (at) => bannerStyle(id, at, spaceId));
      continue;
    }
    stopSettle(element);
    applyLeafStyle(element, bannerStyle(id, frame, spaceId));
  }
}

/** The Space's sidebar field at `width` by `height`, as its banner draws it: the Space editor's stage shows it too. */
export function BannerLayers({ branding, width, height }: { branding: SpaceBranding; width: number; height: number }) {
  const reducesTransparency = useMediaQuery("(prefers-reduced-transparency: reduce)");
  const increasesContrast = useMediaQuery("(prefers-contrast: more)");
  const fieldOpacity = reducesTransparency ? Math.max(branding.bannerStrength, 0.85) : branding.bannerStrength;
  const configuredFade = reducesTransparency ? Math.max(branding.readabilityFade, 0.42) : branding.readabilityFade;
  const fade = Math.min(configuredFade * 0.55 + (increasesContrast ? 0.1 : 0), 0.7);
  const grain = branding.textureStrength * (reducesTransparency ? 0.24 : 0.38);
  // The palette's colors as the banner fills them, each running into its own gradient where it has one.
  const fills = (branding.colors.colors.length > 0 ? branding.colors.colors : [null]).map((_, slot) => slotFill(branding, slot));
  // Banners blend over each other, so each one's gradients need names of their own.
  const id = `space-banner-${useId().replace(/:/g, "")}`;
  return (
    <>
      <div className="space-banner-window" />
      <svg className="space-banner-field" width={width} height={height} viewBox={`0 0 ${width} ${height}`}
        style={{ opacity: fieldOpacity }}>
        {branding.themeMode.name === "gradient"
          ? <GradientField fill={sidebarFill(branding)} id={id} width={width} height={height} />
          : <PatternField pattern={branding.bannerPattern.name} fills={fills} id={id} width={width} height={height} />}
      </svg>
      {fade > 0 && <div className="space-banner-fade" style={{ opacity: fade }} />}
      {branding.textureStrength > 0 && <Grain width={width} height={height} opacity={grain} />}
    </>
  );
}

/**
 * BrowserSpaceBannerField: each pattern's shapes over the first fill, each
 * fill one color or a gradient of its own across the shape it paints: a
 * half or a band its own, the shapes laid over the whole banner the banner.
 */
function PatternField({ pattern, fills, id, width: w, height: h }: {
  pattern: string;
  fills: readonly SpaceFill[];
  id: string;
  width: number;
  height: number;
}) {
  const definitions: React.ReactNode[] = [];
  const paint = (slot: number, box: FillBox) => {
    const index = Math.min(slot, fills.length - 1);
    const painted = fillPaint(fills[index], `${id}-${definitions.length}`, box);
    if (painted.definition) definitions.push(painted.definition);
    return painted.paint;
  };
  const whole: FillBox = { x: 0, y: 0, width: w, height: h };
  const polygon = (points: readonly (readonly [number, number])[], fill: string) => (
    <polygon points={points.map(([x, y]) => `${x * w},${y * h}`).join(" ")} fill={fill} />
  );
  const shapes = (() => {
    switch (pattern) {
      case "split":
        return (
          <>
            <rect width={w / 2} height={h} fill={paint(0, { x: 0, y: 0, width: w / 2, height: h })} />
            <rect x={w / 2} width={w / 2} height={h} fill={paint(1, { x: w / 2, y: 0, width: w / 2, height: h })} />
          </>
        );
      case "bands":
        return (
          <>
            {[0, 1, 2].map((band) => (
              <rect key={band} y={(band * h) / 3} width={w} height={h / 3}
                fill={paint(band, { x: 0, y: (band * h) / 3, width: w, height: h / 3 })} />
            ))}
          </>
        );
      default:
        return <OverlaidShapes pattern={pattern} base={paint(0, whole)} second={() => paint(1, whole)} third={() => paint(2, whole)}
          polygon={polygon} width={w} height={h} />;
    }
  })();
  return <>{definitions.length > 0 && <defs>{definitions}</defs>}{shapes}</>;
}

/** The patterns whose shapes lie over the whole banner, each painted from its fill across the banner. */
function OverlaidShapes({ pattern, base: baseFill, second: secondFill, third: thirdFill, polygon, width: w, height: h }: {
  pattern: string;
  base: string;
  second: () => string;
  third: () => string;
  polygon: (points: readonly (readonly [number, number])[], fill: string) => React.ReactNode;
  width: number;
  height: number;
}) {
  const second = pattern === "solid" ? "" : secondFill();
  const third = pattern === "solid" ? "" : thirdFill();
  const base = <rect width={w} height={h} fill={baseFill} />;
  switch (pattern) {
    case "solid":
      return base;
    case "diagonal":
      return (
        <>
          {base}
          {polygon([[0, 0.5], [1, 0.34], [1, 0.5], [0, 0.68]], second)}
          {polygon([[0, 0.68], [1, 0.5], [1, 1], [0, 1]], third)}
        </>
      );
    case "chevron":
      return (
        <>
          {base}
          {polygon([[0, 0.42], [0.5, 0.58], [1, 0.42], [1, 0.62], [0.5, 0.78], [0, 0.62]], second)}
          {polygon([[0, 0.62], [0.5, 0.78], [1, 0.62], [1, 1], [0, 1]], third)}
        </>
      );
    case "quartered":
      return (
        <>
          {base}
          <rect x={w / 2} width={w / 2} height={h / 2} fill={second} />
          <rect y={h / 2} width={w / 2} height={h / 2} fill={third} />
        </>
      );
    case "stripes":
    case "checkered":
    case "lozenges":
      return <>{base}<Cells pattern={pattern} second={second} third={third} width={w} height={h} /></>;
    default:
      return base;
  }
}

/** The tiled patterns, in cells a fifth of the banner wide. */
function Cells({ pattern, second, third, width, height }: {
  pattern: string;
  second: string;
  third: string;
  width: number;
  height: number;
}) {
  const cell = Math.max(16, width / 5);
  const rows = Math.min(200, Math.ceil(height / cell) + 1);
  const columns = Math.min(200, Math.ceil(width / cell) + 1);
  const shapes = [];
  for (let row = 0; row < rows; row++) {
    for (let column = 0; column < columns; column++) {
      const x = column * cell;
      const y = row * cell;
      const key = `${row}-${column}`;
      if (pattern === "stripes" && column % 2 === 0) {
        shapes.push(<rect key={key} x={x} y={y} width={cell} height={cell} fill={second} fillOpacity={0.35} />);
      } else if (pattern === "checkered" && (row + column) % 2 === 0) {
        shapes.push(<rect key={key} x={x} y={y} width={cell} height={cell} fill={second} fillOpacity={0.35} />);
      } else if (pattern === "lozenges") {
        const points = `${x + cell / 2},${y} ${x + cell},${y + cell / 2} ${x + cell / 2},${y + cell} ${x},${y + cell / 2}`;
        shapes.push(<polygon key={key} points={points} fill={(row + column) % 2 === 0 ? second : third} fillOpacity={0.35} />);
      }
    }
  }
  return <>{shapes}</>;
}

/** BrowserSpaceGradientField: the sidebar's colors as one gradient of its kind, across the banner. */
function GradientField({ fill, id, width, height }: { fill: SpaceFill; id: string; width: number; height: number }) {
  const painted = fillPaint(fill, `${id}-gradient`, { x: 0, y: 0, width, height });
  return (
    <>
      {painted.definition && <defs>{painted.definition}</defs>}
      <rect width={width} height={height} fill={painted.paint} />
    </>
  );
}

/**
 * BrowserSpaceThemeTexture: the same grain the Mac lays over the banner, one
 * particle per 24 square points, light and dark in turn, from the same seed.
 */
export function Grain({ width, height, opacity }: { width: number; height: number; opacity: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const element = canvas.current;
    const context = element?.getContext("2d");
    if (!element || !context) return;
    const scale = window.devicePixelRatio || 1;
    element.width = Math.round(width * scale);
    element.height = Math.round(height * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.clearRect(0, 0, width, height);
    const count = Math.min(grainSamples.length, Math.max(800, Math.floor((width * height) / 24)));
    for (const [light, fill] of [[true, "rgb(255 255 255 / 0.46)"], [false, "rgb(0 0 0 / 0.38)"]] as const) {
      context.fillStyle = fill;
      context.beginPath();
      for (let index = light ? 0 : 1; index < count; index += 2) {
        const [x, y, diameter] = grainSamples[index];
        const radius = diameter / 2;
        context.moveTo(x * width + diameter, y * height + radius);
        context.arc(x * width + radius, y * height + radius, radius, 0, Math.PI * 2);
      }
      context.fill();
    }
  }, [width, height]);
  return <canvas ref={canvas} className="space-banner-grain" style={{ width, height, opacity }} />;
}

/** The Mac's particles, as unit positions and point diameters (SplitMix64, seed 0xC2E57A11). */
export const grainSamples: readonly (readonly [number, number, number])[] = (() => {
  const mask = (1n << 64n) - 1n;
  let state = 0xC2E5_7A11n;
  const next = () => {
    state = (state + 0x9E37_79B9_7F4A_7C15n) & mask;
    let value = state;
    value = ((value ^ (value >> 30n)) * 0xBF58_476D_1CE4_E5B9n) & mask;
    value = ((value ^ (value >> 27n)) * 0x94D0_49BB_1331_11EBn) & mask;
    value ^= value >> 31n;
    return Number(value) / Number(mask);
  };
  const samples: (readonly [number, number, number])[] = [];
  for (let index = 0; index < 20_000; index++) {
    const x = next();
    const y = next();
    samples.push([x, y, 0.85 + next() * 1.5]);
  }
  return samples;
})();

function useElementSize(element: RefObject<HTMLElement | null>) {
  const [size, setSize] = useState<{ width: number; height: number } | null>(null);
  useLayoutEffect(() => {
    const target = element.current;
    if (!target) return;
    const observer = new ResizeObserver(([entry]) => {
      const { width, height } = entry.contentRect;
      setSize((current) => (current?.width === width && current.height === height ? current : { width, height }));
    });
    observer.observe(target);
    return () => observer.disconnect();
  }, [element]);
  return size;
}

function useMediaQuery(query: string) {
  const [matches, setMatches] = useState(() => matchMedia(query).matches);
  useEffect(() => {
    const list = matchMedia(query);
    const update = () => setMatches(list.matches);
    list.addEventListener("change", update);
    return () => list.removeEventListener("change", update);
  }, [query]);
  return matches;
}
