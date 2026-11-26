<script lang="ts" module>
  import { timed } from "../motion";

  /** Where a file flies: from the shown card to the lists button, kept below `top`. */
  export interface FlightPath {
    readonly from: Point;
    readonly to: Point;
    readonly top: number;
  }

  interface Point {
    readonly x: number;
    readonly y: number;
  }

  const appearing = timed({ duration: 0.14, ease: "easeOut" });
  const flying = timed({ duration: 0.78, ease: "easeInOut", delay: 0.1 });
</script>

<script lang="ts">
  import { untrack } from "svelte";
  import { Tween } from "svelte/motion";

  import SymbolIcon from "../SymbolIcon.svelte";

  /**
   * BrowserMacDownloadFlightIcon: the file comes up in a beat, then flies along
   * a quadratic arc lifted above both ends by a third of the way, up to 140,
   * shrinking to a third, and fades in the last tenth of the way.
   */
  let { path, onLanded }: { path: FlightPath; onLanded: () => void } = $props();

  const appearance = new Tween(0);
  const progress = new Tween(0);
  // The flight runs once.
  $effect(() => {
    let stopped = false;
    const run = async () => {
      await appearance.set(1, { duration: appearing.duration, easing: appearing.easing });
      if (stopped) return;
      await progress.set(1, { duration: flying.duration, easing: flying.easing, delay: flying.delay });
      if (!stopped) onLanded();
    };
    untrack(() => void run());
    return () => {
      stopped = true;
    };
  });
  const lift = $derived(Math.min(140, Math.hypot(path.to.x - path.from.x, path.to.y - path.from.y) * 0.3));
  const control = $derived({ x: (path.from.x + path.to.x) / 2, y: Math.max(path.top + 20, Math.min(path.from.y, path.to.y) - lift) });
  const along = (t: number, a: number, c: number, b: number) => (1 - t) * (1 - t) * a + 2 * (1 - t) * t * c + t * t * b;
  const x = $derived(along(progress.current, path.from.x, control.x, path.to.x) - 21);
  const y = $derived(along(progress.current, path.from.y, control.y, path.to.y) - 23);
  const scale = $derived((1 - progress.current * 0.68) * (0.55 + 0.45 * appearance.current));
  const opacity = $derived(appearance.current * (1 - Math.min(Math.max((progress.current - 0.9) / 0.1, 0), 1)));
</script>

<div class="flying-file" style:transform="translateX({x}px) translateY({y}px) scale({scale})" style:opacity={opacity}>
  <SymbolIcon name="doc.fill" size={28} />
</div>
