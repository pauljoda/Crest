import type { BrandColor } from "@crest/contracts";
import { motion as tokens } from "@crest/design";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  type KeyboardEvent as ReactKeyboardEvent,
  type PointerEvent as ReactPointerEvent,
  type RefObject,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from "react";

import { css } from "../branding";
import { Grain } from "../shell/SpaceBanner";
import {
  ColorStops,
  edgeLightness,
  maximumFillColors,
  readWheel,
  sameColor,
  wheelColor,
  wheelPoint,
  wheelPointAt,
  wheelPosition,
  withLightness,
} from "../spaces/color-harmony";
import { cuspLightness, fromLch, type SpaceFill } from "../spaces/space-fills";
import { Symbol } from "../symbols";

/** CrestColorPopoverMetrics, CrestColorWheelMetrics and CrestColorSliderMetrics. */
const metrics = {
  wheelHeight: 296,
  handle: 26,
  chosenHandle: 36,
  reach: 22,
  turnStep: 1 / 36,
  gridSpacing: 9,
  imageSize: 240,
  lightnessSteps: 64,
  trackSteps: 8,
  sliderThumb: 22,
  commitInterval: 33,
  slowestCommitInterval: 120,
  lateness: 8,
  paceStep: 8,
} as const;

/** The spectrum: a hue every 30° from a red, at one soft chroma, each leaning toward the lightness where it is most vivid. */
const spectrum: readonly { readonly name: string; readonly color: BrandColor }[] = [
  "Red", "Orange", "Yellow", "Lime", "Green", "Mint", "Teal", "Sky", "Blue", "Violet", "Purple", "Pink",
].map((name, step) => {
  const degrees = 25 + step * 30;
  const lightness = 0.7 + 0.4 * (cuspLightness(degrees) - 0.7);
  return { name, color: fromLch(lightness, 0.12, degrees / 360) };
});

/** Whether two fills draw the same: their colors, and, for a gradient, its kind and direction. */
export function sameFill(left: SpaceFill, right: SpaceFill): boolean {
  if (left.colors.length !== right.colors.length) return false;
  if (!left.colors.every((color, index) => sameColor(color, right.colors[index]))) return false;
  return left.colors.length < 2 || (left.kind === right.kind && Math.abs(left.degrees - right.degrees) < 0.5);
}

/** How the handles move to their places: springing, as a pick or a press on the open wheel does, or at once under the pointer. */
type Placing = "spring" | "instant";

/**
 * CrestColorPopover's content: the color wheel with a handle for each of
 * the fill's colors; minus and plus under it, with the gradient's direction
 * and the link at either end once there are two colors; the chosen color's
 * Brightness; the Texture where the well has one; and the spectrum. Every
 * gradient it touches runs straight. It edits its own copy, which reaches
 * `onCommit` at most every 33 ms, and further apart while the window is
 * still drawing the last one; `flush` hands over what is pending at once,
 * as the popover closes.
 */
export function ColorPopoverContent({ fill, onCommit, texture = null, flush }: {
  fill: SpaceFill;
  onCommit: (fill: SpaceFill) => void;
  texture?: { readonly value: number; readonly onChange: (value: number) => void } | null;
  flush: RefObject<(() => void) | null>;
}) {
  const reducesMotion = useReducedMotion() ?? false;
  const stops = useRef<ColorStops | null>(null);
  if (!stops.current) {
    stops.current = new ColorStops();
    stops.current.adopt(fill);
  }
  const [draft, setDraft] = useState(fill);
  const draftRef = useRef(draft);
  const [selection, setSelection] = useState(0);
  const [isLinked, setIsLinked] = useState(true);
  const [placing, setPlacing] = useState<Placing>("instant");
  const commitRef = useRef(onCommit);
  commitRef.current = onCommit;
  const pending = useRef<number | null>(null);
  const pace = useRef<number>(metrics.commitInterval);

  /** Hands the copy over once the pace has passed; waking late slows the pace, waking on time quickens it. */
  const schedule = () => {
    if (pending.current !== null) return;
    const wait = pace.current;
    const asked = performance.now();
    pending.current = window.setTimeout(() => {
      const late = performance.now() - asked - wait;
      pace.current = late > metrics.lateness
        ? Math.min(wait + late, metrics.slowestCommitInterval)
        : Math.max(wait - metrics.paceStep, metrics.commitInterval);
      pending.current = null;
      commitRef.current(draftRef.current);
    }, wait);
  };

  const edit = (next: SpaceFill, how: Placing = "instant") => {
    draftRef.current = next;
    setDraft(next);
    setPlacing(how);
    setSelection((chosen) => Math.min(chosen, next.colors.length - 1));
    schedule();
  };

  useLayoutEffect(() => {
    // Every gradient runs straight; one of another kind takes a line, which counts as an edit.
    if (draftRef.current.colors.length > 1 && draftRef.current.kind !== "linear") edit({ ...draftRef.current, kind: "linear" });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A change from elsewhere, with nothing of the popover's own pending, takes over the copy.
  useEffect(() => {
    if (pending.current !== null || sameFill(fill, draftRef.current)) return;
    draftRef.current = fill;
    setDraft(fill);
    stops.current!.adopt(fill);
    stops.current!.releaseShape();
  }, [fill]);

  useEffect(() => {
    const commitNow = () => {
      if (pending.current === null) return;
      window.clearTimeout(pending.current);
      pending.current = null;
      commitRef.current(draftRef.current);
    };
    flush.current = commitNow;
    return () => {
      commitNow();
      flush.current = null;
    };
  }, [flush]);

  const chosenIndex = Math.min(selection, draft.colors.length - 1);
  const chosen = readWheel(draft.colors[chosenIndex]);
  const isGradient = draft.colors.length > 1;

  const move = (color: BrandColor, index: number, how: Placing = "instant") => {
    edit(stops.current!.move(color, index, draftRef.current, isLinked), how);
  };

  const add = () => {
    const next = stops.current!.add(draftRef.current);
    edit(next, "spring");
    setSelection(next.colors.length - 1);
  };

  const remove = () => {
    const index = chosenIndex;
    const next = stops.current!.remove(index, draftRef.current);
    edit(next, "spring");
    setSelection(Math.min(index, next.colors.length - 1));
  };

  const toggleLink = () => {
    setIsLinked((linked) => !linked);
    stops.current!.releaseShape();
  };

  const selectionMotion = reducesMotion ? { duration: 0 } : tokens.selection;

  return (
    <div className="color-popover-content">
      <div className="color-popover-wheel-group">
        <ColorWheel fill={draft} ids={stops.current.ids(draft)} selection={chosenIndex} placing={placing} reducesMotion={reducesMotion}
          onChoose={setSelection}
          onPlace={(color, index, springs) => move(color, index, springs ? "spring" : "instant")} />
        <div className="color-popover-controls">
          <div className="color-popover-count">
            <button type="button" className="color-popover-button" aria-label="Remove Color" title="Remove Color"
              disabled={draft.colors.length <= 1} onClick={remove}>
              <Symbol name="minus" size={17} strokeWidth={2.25} />
            </button>
            <button type="button" className="color-popover-button" aria-label="Add Color" title="Add Color"
              disabled={draft.colors.length >= maximumFillColors} onClick={add}>
              <Symbol name="plus" size={17} strokeWidth={2.25} />
            </button>
          </div>
          <AnimatePresence initial={false}>
            {isGradient && (
              <motion.div key="knob" className="color-popover-leading"
                initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.6 }}
                transition={selectionMotion}>
                <AngleKnob degrees={draft.degrees} onChange={(degrees) => edit({ ...draftRef.current, degrees })} />
              </motion.div>
            )}
            {isGradient && (
              <motion.div key="link" className="color-popover-trailing"
                initial={{ opacity: 0, scale: 0.6 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.6 }}
                transition={selectionMotion}>
                <button type="button" className={`color-link${isLinked ? " on" : ""}`} data-testid="color-link"
                  aria-label={isLinked ? "Unlink Colors" : "Link Colors"} aria-pressed={isLinked} title={isLinked ? "Unlink Colors" : "Link Colors"}
                  onClick={toggleLink}>
                  <Symbol name="link" size={16} strokeWidth={2.25} />
                </button>
              </motion.div>
            )}
          </AnimatePresence>
        </div>
      </div>
      <ColorSlider title="Brightness" value={chosen.lightness}
        track={Array.from({ length: metrics.trackSteps + 1 }, (_, step) => wheelColor(withLightness(chosen, step / metrics.trackSteps)))}
        thumb={draft.colors[chosenIndex]}
        onChange={(value) => move(wheelColor(withLightness(chosen, Math.min(Math.max(value, edgeLightness), 1 - edgeLightness))), chosenIndex)} />
      {texture && (
        <ColorSlider title="Texture" value={texture.value} track={[draft.colors[0], draft.colors[0]]} thumb={draft.colors[0]} showsGrain
          onChange={texture.onChange} />
      )}
      <div className="color-spectrum" role="group" aria-label="Spectrum">
        {spectrum.map(({ name, color }) => {
          const selected = sameColor(draft.colors[chosenIndex], color);
          return (
            <span key={name} className="color-spectrum-slot">
              <button type="button" className={`color-spectrum-swatch${selected ? " selected" : ""}`} aria-label={name} aria-pressed={selected}
                title={name} onClick={() => move(color, chosenIndex, "spring")}>
                <span className="color-spectrum-dot" style={{ background: css(color) }} />
              </button>
            </span>
          );
        })}
      </div>
    </div>
  );
}

// MARK: - Wheel

/** The wheel's images, one for each step of lightness, drawn as they're first needed. */
const wheelImages = new Map<number, HTMLCanvasElement>();

/**
 * CrestColorWheelImage: every hue round the wheel, red at the top and
 * clockwise, and every vibrancy out from its gray center, at one step of
 * lightness, with a one-pixel soft rim.
 */
function wheelImage(step: number): HTMLCanvasElement {
  const cached = wheelImages.get(step);
  if (cached) return cached;
  const size = metrics.imageSize;
  const half = size / 2;
  const lightness = step / metrics.lightnessSteps;
  const image = document.createElement("canvas");
  image.width = size;
  image.height = size;
  const context = image.getContext("2d")!;
  const pixels = context.createImageData(size, size);
  for (let row = 0; row < size; row++) {
    for (let column = 0; column < size; column++) {
      const x = (column + 0.5 - half) / half;
      const y = (row + 0.5 - half) / half;
      const coverage = Math.min(Math.max((1 - Math.hypot(x, y)) * half + 0.5, 0), 1);
      if (coverage <= 0) continue;
      const color = wheelColor(wheelPointAt(x, y, lightness));
      const at = (row * size + column) * 4;
      pixels.data[at] = Math.round(color.red * 255);
      pixels.data[at + 1] = Math.round(color.green * 255);
      pixels.data[at + 2] = Math.round(color.blue * 255);
      pixels.data[at + 3] = Math.round(coverage * 255);
    }
  }
  context.putImageData(pixels, 0, 0);
  wheelImages.set(step, image);
  return image;
}

/** The wheel at the chosen color's lightness under its fine grid of dots, set into the popover. */
function WheelSurface({ side, step }: { side: number; step: number }) {
  const canvas = useRef<HTMLCanvasElement>(null);
  useLayoutEffect(() => {
    const element = canvas.current;
    const context = element?.getContext("2d");
    if (!element || !context || side <= 0) return;
    const scale = window.devicePixelRatio || 1;
    element.width = Math.round(side * scale);
    element.height = Math.round(side * scale);
    context.setTransform(scale, 0, 0, scale, 0, 0);
    context.clearRect(0, 0, side, side);
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";
    context.drawImage(wheelImage(step), 0, 0, side, side);
    context.save();
    context.beginPath();
    context.arc(side / 2, side / 2, side / 2, 0, Math.PI * 2);
    context.clip();
    context.fillStyle = "rgb(255 255 255 / 0.3)";
    context.beginPath();
    for (let x = metrics.gridSpacing / 2; x < side; x += metrics.gridSpacing) {
      for (let y = metrics.gridSpacing / 2; y < side; y += metrics.gridSpacing) {
        context.moveTo(x + 0.6, y);
        context.arc(x, y, 0.6, 0, Math.PI * 2);
      }
    }
    context.fill();
    context.restore();
  }, [side, step]);
  return (
    <span className="color-wheel-surface color-inset" style={{ width: side, height: side }}>
      <canvas ref={canvas} style={{ width: side, height: side }} />
    </span>
  );
}

/**
 * CrestColorWheel: a handle for each of the fill's colors over the wheel.
 * Pressing within reach of a handle chooses it and drags it; pressing
 * anywhere else springs the chosen handle there and drags it on. A handle
 * keeps its lightness, held within the rim.
 */
function ColorWheel({ fill, ids, selection, placing, reducesMotion, onChoose, onPlace }: {
  fill: SpaceFill;
  ids: readonly number[];
  selection: number;
  placing: Placing;
  reducesMotion: boolean;
  onChoose: (index: number) => void;
  onPlace: (color: BrandColor, index: number, springs: boolean) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(296);
  useLayoutEffect(() => {
    const element = box.current;
    if (!element) return;
    const observer = new ResizeObserver(() => setWidth(element.offsetWidth));
    observer.observe(element);
    setWidth(element.offsetWidth);
    return () => observer.disconnect();
  }, []);
  const side = Math.max(Math.min(width, metrics.wheelHeight) - metrics.chosenHandle, 0);
  const center = { x: width / 2, y: metrics.wheelHeight / 2 };
  const radius = Math.max(side / 2, 1);
  const chosen = readWheel(fill.colors[selection]);
  const step = Math.round(chosen.lightness * metrics.lightnessSteps);
  const dragging = useRef<{ pointer: number; index: number } | null>(null);
  const [lifted, setLifted] = useState(false);

  const location = (color: BrandColor) => {
    const position = wheelPosition(readWheel(color));
    return { x: center.x + position.x * radius, y: center.y + position.y * radius };
  };
  const colorAt = (event: ReactPointerEvent, lightness: number) => {
    const bounds = box.current!.getBoundingClientRect();
    return wheelColor(wheelPointAt((event.clientX - bounds.left - center.x) / radius, (event.clientY - bounds.top - center.y) / radius, lightness));
  };

  const press = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    const bounds = box.current!.getBoundingClientRect();
    const pressed = { x: event.clientX - bounds.left, y: event.clientY - bounds.top };
    let near: number | null = null;
    let nearest = Infinity;
    fill.colors.forEach((color, index) => {
      const handle = location(color);
      const distance = Math.hypot(handle.x - pressed.x, handle.y - pressed.y);
      if (distance < metrics.reach && distance < nearest) {
        near = index;
        nearest = distance;
      }
    });
    const index = near ?? selection;
    if (near !== null) onChoose(near);
    dragging.current = { pointer: event.pointerId, index };
    setLifted(true);
    onPlace(colorAt(event, readWheel(fill.colors[index]).lightness), index, near === null);
  };
  const drag = (event: ReactPointerEvent<HTMLDivElement>) => {
    const press = dragging.current;
    if (!press || event.pointerId !== press.pointer) return;
    onPlace(colorAt(event, readWheel(fill.colors[press.index]).lightness), press.index, false);
  };
  const release = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (dragging.current?.pointer !== event.pointerId) return;
    dragging.current = null;
    setLifted(false);
  };

  const turn = (index: number, by: number) => {
    const point = readWheel(fill.colors[index]);
    onChoose(index);
    onPlace(wheelColor(wheelPoint(point.hue + by + 1, point.vibrancy, point.lightness)), index, false);
  };
  const handleKey = (index: number) => (event: ReactKeyboardEvent) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? metrics.turnStep
      : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -metrics.turnStep : 0;
    if (by === 0) return;
    event.preventDefault();
    turn(index, by);
  };

  const travel = placing === "spring" && !reducesMotion ? tokens.colorPop : { duration: 0 };
  const pop = reducesMotion ? { duration: 0 } : tokens.colorPop;
  return (
    <div ref={box} className="color-wheel" role="group" aria-label="Colors" style={{ height: metrics.wheelHeight }}
      onPointerDown={press} onPointerMove={drag} onPointerUp={release} onPointerCancel={release}>
      <span className="color-wheel-place" style={{ left: center.x - side / 2, top: center.y - side / 2 }}>
        <WheelSurface side={side} step={step} />
      </span>
      <AnimatePresence initial={false}>
        {fill.colors.map((color, index) => {
          const isChosen = index === selection;
          const at = location(color);
          return (
            <motion.div key={ids[index]} className="color-wheel-handle" style={{ zIndex: isChosen ? 1 : 0 }}
              initial={{ x: at.x, y: at.y, scale: 0.2, opacity: 0 }}
              animate={{ x: at.x, y: at.y, scale: 1, opacity: 1 }}
              exit={{ scale: 0.2, opacity: 0 }}
              transition={{ default: pop, x: travel, y: travel }}>
              <span role="slider" tabIndex={isChosen ? 0 : -1} aria-label={`Color ${index + 1}`} aria-selected={isChosen}
                aria-valuemin={0} aria-valuemax={360} aria-valuenow={Math.round(readWheel(color).hue * 360)}
                className={`color-wheel-dot${isChosen ? " chosen" : ""}${isChosen && lifted ? " lifted" : ""}`}
                style={{ background: css(color) }} onKeyDown={handleKey(index)} onFocus={() => onChoose(index)} />
            </motion.div>
          );
        })}
      </AnimatePresence>
    </div>
  );
}

// MARK: - Controls

/**
 * CrestColorSlider: a track of the colors it runs through, set into the
 * popover, under a thumb wearing the color it stands at. Pressing anywhere
 * on the track moves the thumb there and drags it on.
 */
function ColorSlider({ title, value, track, thumb, showsGrain = false, onChange }: {
  title: string;
  value: number;
  track: readonly BrandColor[];
  thumb: BrandColor;
  showsGrain?: boolean;
  onChange: (value: number) => void;
}) {
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(296);
  const dragging = useRef<number | null>(null);
  const [lifted, setLifted] = useState(false);
  useLayoutEffect(() => {
    const element = box.current;
    if (!element) return;
    const observer = new ResizeObserver(() => setWidth(element.offsetWidth));
    observer.observe(element);
    setWidth(element.offsetWidth);
    return () => observer.disconnect();
  }, []);
  const inset = metrics.sliderThumb / 2;
  const span = Math.max(width - 2 * inset, 1);
  const valueAt = (event: ReactPointerEvent) => {
    const bounds = box.current!.getBoundingClientRect();
    return Math.min(Math.max((event.clientX - bounds.left - inset) / span, 0), 1);
  };
  const key = (event: ReactKeyboardEvent) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? 0.05 : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -0.05 : 0;
    if (by === 0) return;
    event.preventDefault();
    onChange(Math.min(Math.max(value + by, 0), 1));
  };
  const gradient = `linear-gradient(to right, ${track.map((color) => css(color)).join(", ")})`;
  return (
    <div ref={box} className="color-slider" role="slider" tabIndex={0} aria-label={title} title={title}
      aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(value * 100)} aria-valuetext={`${Math.round(value * 100)}%`}
      onKeyDown={key}
      onPointerDown={(event) => {
        if (event.button !== 0) return;
        event.currentTarget.setPointerCapture(event.pointerId);
        dragging.current = event.pointerId;
        setLifted(true);
        onChange(valueAt(event));
      }}
      onPointerMove={(event) => {
        if (dragging.current === event.pointerId) onChange(valueAt(event));
      }}
      onPointerUp={(event) => {
        if (dragging.current !== event.pointerId) return;
        dragging.current = null;
        setLifted(false);
      }}
      onPointerCancel={() => {
        dragging.current = null;
        setLifted(false);
      }}>
      <span className="color-slider-track color-inset slim" style={{ background: gradient }}>
        {showsGrain && (
          <span className="color-slider-grain">
            <Grain width={width} height={14} opacity={0.38} />
          </span>
        )}
      </span>
      <span className={`color-slider-thumb${lifted ? " lifted" : ""}`}
        style={{ left: inset + Math.min(Math.max(value, 0), 1) * span, background: css(thumb) }} />
    </div>
  );
}

/**
 * CrestAngleKnob at 32: a dial of eight ticks with an arrow along the
 * gradient's direction and a handle on its ring. Turning it settles on a
 * multiple of 45° within 4°, and on whole degrees otherwise.
 */
function AngleKnob({ degrees, onChange }: { degrees: number; onChange: (degrees: number) => void }) {
  const diameter = 32;
  const radius = diameter / 2;
  const turning = useRef<number | null>(null);
  const [lifted, setLifted] = useState(false);
  const normalized = (value: number) => ((value % 360) + 360) % 360;
  const settled = (value: number) => {
    const eighth = Math.round(value / 45) * 45;
    return normalized(Math.abs(value - eighth) <= 4 ? eighth : Math.round(value));
  };
  const turnTo = (event: ReactPointerEvent<HTMLDivElement>) => {
    const bounds = event.currentTarget.getBoundingClientRect();
    const x = event.clientX - bounds.left - radius;
    const y = event.clientY - bounds.top - radius;
    if (Math.hypot(x, y) <= 4) return;
    onChange(settled(normalized((Math.atan2(y, x) * 180) / Math.PI)));
  };
  const ring = radius - 6 - 2;
  const radians = (degrees * Math.PI) / 180;
  return (
    <div className="angle-knob" role="slider" tabIndex={0} aria-label="Direction" title="Direction"
      aria-valuemin={0} aria-valuemax={359} aria-valuenow={Math.round(degrees)} aria-valuetext={`${Math.round(degrees)} degrees`}
      onKeyDown={(event) => {
        const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? 15 : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -15 : 0;
        if (by === 0) return;
        event.preventDefault();
        onChange(normalized(degrees + by));
      }}
      onPointerDown={(event) => {
        if (event.button !== 0) return;
        event.currentTarget.setPointerCapture(event.pointerId);
        turning.current = event.pointerId;
        setLifted(true);
        turnTo(event);
      }}
      onPointerMove={(event) => {
        if (turning.current === event.pointerId) turnTo(event);
      }}
      onPointerUp={(event) => {
        if (turning.current !== event.pointerId) return;
        turning.current = null;
        setLifted(false);
      }}
      onPointerCancel={() => {
        turning.current = null;
        setLifted(false);
      }}>
      {Array.from({ length: 8 }, (_, index) => (
        <span key={index} className="angle-knob-tick" style={{ transform: `rotate(${index * 45}deg) translateY(${-radius + 4}px)` }} />
      ))}
      <span className="angle-knob-arrow" style={{ transform: `rotate(${degrees}deg)` }}>
        <Symbol name="arrow.right" size={11} strokeWidth={2.5} />
      </span>
      <span className={`angle-knob-handle${lifted ? " turning" : ""}`}
        style={{ left: radius + ring * Math.cos(radians), top: radius + ring * Math.sin(radians) }} />
    </div>
  );
}
