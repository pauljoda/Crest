<script lang="ts" module>
  import type { Spring } from "@crest/design";
  import { untrack } from "svelte";
  import type { Attachment } from "svelte/attachments";

  import { wheelColor, wheelPointAt } from "../spaces/color-harmony";
  import { metrics } from "./color-popover";

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
  function paintSurface(side: number, step: number): Attachment<HTMLCanvasElement> {
    return (element) => {
      const context = element.getContext("2d");
      if (!context || side <= 0) return;
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
    };
  }

  interface Point {
    readonly x: number;
    readonly y: number;
  }

  /** How near its place, in points, and how slow, in points a second, a springing handle settles there. */
  const rest = { distance: 0.1, speed: 2 } as const;

  /**
   * Where a spring left `offset` from its rest at `velocity` stands `seconds`
   * later, and how fast it moves then: SwiftUI's spring of the token's
   * duration and bounce, as `springCurve` draws it from rest, here from
   * anywhere at any speed.
   */
  function springAt(spring: Spring, offset: number, velocity: number, seconds: number): { offset: number; velocity: number } {
    const omega = (2 * Math.PI) / spring.visualDuration;
    const damping = Math.min(1, Math.max(0.01, 1 - spring.bounce));
    const decay = Math.exp(-damping * omega * seconds);
    if (damping >= 1) {
      const rate = velocity + omega * offset;
      return { offset: decay * (offset + rate * seconds), velocity: decay * (velocity - omega * seconds * rate) };
    }
    const ringing = omega * Math.sqrt(1 - damping * damping);
    const cos = Math.cos(ringing * seconds);
    const sin = Math.sin(ringing * seconds);
    return {
      offset: decay * (offset * cos + ((velocity + damping * omega * offset) / ringing) * sin),
      velocity: decay * (velocity * cos - ((damping * omega * velocity + omega * omega * offset) / ringing) * sin),
    };
  }

  /**
   * Keeps a handle where `target` puts it: at once without a spring, and with
   * one, springing there from where it stands at the speed it was going, as
   * Motion carried a value's velocity into the animation that took over. The
   * place is the element's `translate`, which stands outside the scale the
   * handle comes and goes with, as Motion's x and y stood before it.
   */
  function travel(target: () => Point, spring: () => Spring | null): Attachment<HTMLElement> {
    return (element) => {
      let goal: Point | null = null;
      let run: { readonly spring: Spring; readonly start: number; readonly offset: Point; readonly velocity: Point } | null = null;
      let frame = 0;
      const place = (point: Point) => {
        element.style.translate = `${point.x}px ${point.y}px`;
      };
      /** The running spring's offset from the goal and its velocity, at `now`. */
      const sample = (now: number) => {
        if (!run) return { offset: { x: 0, y: 0 }, velocity: { x: 0, y: 0 } };
        const seconds = Math.max(now - run.start, 0) / 1000;
        const x = springAt(run.spring, run.offset.x, run.velocity.x, seconds);
        const y = springAt(run.spring, run.offset.y, run.velocity.y, seconds);
        return { offset: { x: x.offset, y: y.offset }, velocity: { x: x.velocity, y: y.velocity } };
      };
      const tick = (now: number) => {
        if (!run || !goal) return;
        const { offset, velocity } = sample(now);
        if (Math.hypot(offset.x, offset.y) < rest.distance && Math.hypot(velocity.x, velocity.y) < rest.speed) {
          run = null;
          place(goal);
          return;
        }
        place({ x: goal.x + offset.x, y: goal.y + offset.y });
        frame = requestAnimationFrame(tick);
      };
      $effect(() => {
        const next = target();
        const timing = spring();
        untrack(() => {
          if (goal && goal.x === next.x && goal.y === next.y) return;
          const from = goal;
          const { offset, velocity } = sample(performance.now());
          cancelAnimationFrame(frame);
          goal = next;
          if (!from || !timing) {
            run = null;
            place(next);
            return;
          }
          run = {
            spring: timing,
            start: performance.now(),
            offset: { x: from.x + offset.x - next.x, y: from.y + offset.y - next.y },
            velocity,
          };
          frame = requestAnimationFrame(tick);
        });
      });
      return () => cancelAnimationFrame(frame);
    };
  }
</script>

<script lang="ts">
  import type { BrandColor } from "@crest/contracts";
  import { motion as tokens } from "@crest/design";

  import { css } from "../branding";
  import { presence } from "../motion";
  import { readWheel, wheelPoint, wheelPosition } from "../spaces/color-harmony";
  import type { SpaceFill } from "../spaces/space-fills";
  import type { Placing } from "./color-popover";

  /**
   * CrestColorWheel: a handle for each of the fill's colors over the wheel.
   * Pressing within reach of a handle chooses it and drags it; pressing
   * anywhere else springs the chosen handle there and drags it on. A handle
   * keeps its lightness, held within the rim.
   */
  let { fill, ids, selection, placing, reducesMotion, onChoose, onPlace }: {
    fill: SpaceFill;
    ids: readonly number[];
    selection: number;
    placing: Placing;
    reducesMotion: boolean;
    onChoose: (index: number) => void;
    onPlace: (color: BrandColor, index: number, springs: boolean) => void;
  } = $props();

  let box: HTMLDivElement | undefined = $state();
  let width = $state(296);
  $effect(() => {
    const element = box;
    if (!element) return;
    const observer = new ResizeObserver(() => (width = element.offsetWidth));
    observer.observe(element);
    width = element.offsetWidth;
    return () => observer.disconnect();
  });
  const side = $derived(Math.max(Math.min(width, metrics.wheelHeight) - metrics.chosenHandle, 0));
  const center = $derived({ x: width / 2, y: metrics.wheelHeight / 2 });
  const radius = $derived(Math.max(side / 2, 1));
  const chosen = $derived(readWheel(fill.colors[selection]));
  const step = $derived(Math.round(chosen.lightness * metrics.lightnessSteps));
  let dragging: { pointer: number; index: number } | null = null;
  let lifted = $state(false);

  const location = (color: BrandColor): Point => {
    const position = wheelPosition(readWheel(color));
    return { x: center.x + position.x * radius, y: center.y + position.y * radius };
  };
  const colorAt = (event: PointerEvent, lightness: number) => {
    const bounds = box!.getBoundingClientRect();
    return wheelColor(wheelPointAt((event.clientX - bounds.left - center.x) / radius, (event.clientY - bounds.top - center.y) / radius, lightness));
  };

  const press = (event: PointerEvent & { currentTarget: HTMLDivElement }) => {
    if (event.button !== 0) return;
    event.currentTarget.setPointerCapture(event.pointerId);
    const bounds = box!.getBoundingClientRect();
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
    dragging = { pointer: event.pointerId, index };
    lifted = true;
    onPlace(colorAt(event, readWheel(fill.colors[index]).lightness), index, near === null);
  };
  const drag = (event: PointerEvent) => {
    const press = dragging;
    if (!press || event.pointerId !== press.pointer) return;
    onPlace(colorAt(event, readWheel(fill.colors[press.index]).lightness), press.index, false);
  };
  const release = (event: PointerEvent) => {
    if (dragging?.pointer !== event.pointerId) return;
    dragging = null;
    lifted = false;
  };

  const turn = (index: number, by: number) => {
    const point = readWheel(fill.colors[index]);
    onChoose(index);
    onPlace(wheelColor(wheelPoint(point.hue + by + 1, point.vibrancy, point.lightness)), index, false);
  };
  const handleKey = (index: number) => (event: KeyboardEvent) => {
    const by = event.key === "ArrowRight" || event.key === "ArrowUp" ? metrics.turnStep
      : event.key === "ArrowLeft" || event.key === "ArrowDown" ? -metrics.turnStep : 0;
    if (by === 0) return;
    event.preventDefault();
    turn(index, by);
  };

  const travelSpring = $derived(placing === "spring" && !reducesMotion ? tokens.colorPop : null);
  const pop = $derived(reducesMotion ? { duration: 0 } : tokens.colorPop);
  const handles = $derived(fill.colors.map((color, index) => ({ id: ids[index], color, index })));
</script>

<div bind:this={box} class="color-wheel" role="group" aria-label="Colors" style:height="{metrics.wheelHeight}px"
  onpointerdown={press} onpointermove={drag} onpointerup={release} onpointercancel={release}>
  <span class="color-wheel-place" style:left="{center.x - side / 2}px" style:top="{center.y - side / 2}px">
    <span class="color-wheel-surface color-inset" style:width="{side}px" style:height="{side}px">
      <canvas style:width="{side}px" style:height="{side}px" {@attach paintSurface(side, step)}></canvas>
    </span>
  </span>
  {#each handles as handle (handle.id)}
    {@const isChosen = handle.index === selection}
    <div class="color-wheel-handle" style:z-index={isChosen ? 1 : 0} {@attach travel(() => location(handle.color), () => travelSpring)}
      in:presence={{ pose: { scale: 0.2, opacity: 0 }, timing: pop }} out:presence={{ pose: { scale: 0.2, opacity: 0 }, timing: pop }}>
      <!-- svelte-ignore a11y_role_supports_aria_props -->
      <span role="slider" tabindex={0} aria-label={`Color ${handle.index + 1}`} aria-selected={isChosen}
        aria-valuemin={0} aria-valuemax={360} aria-valuenow={Math.round(readWheel(handle.color).hue * 360)}
        class={`color-wheel-dot${isChosen ? " chosen" : ""}${isChosen && lifted ? " lifted" : ""}`}
        style:background={css(handle.color)} onkeydown={handleKey(handle.index)} onfocusin={() => onChoose(handle.index)}></span>
    </div>
  {/each}
</div>
