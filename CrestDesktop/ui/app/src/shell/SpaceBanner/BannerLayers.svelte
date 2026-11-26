<script lang="ts" module>
  import { type FillBox, type FillDefinition as Definition, fillPaint, type SpaceFill } from "../../spaces/space-fills";

  /** One shape of a banner's field, as an SVG `rect` or `polygon` draws it. */
  type FieldShape =
    | {
      readonly kind: "rect";
      readonly x?: number;
      readonly y?: number;
      readonly width: number;
      readonly height: number;
      readonly fill: string;
      readonly fillOpacity?: number;
    }
    | { readonly kind: "polygon"; readonly points: string; readonly fill: string; readonly fillOpacity?: number };

  /** A banner's field: the gradients its fills name, and its shapes, in the order they are drawn. */
  interface Field {
    readonly definitions: readonly Definition[];
    readonly shapes: readonly FieldShape[];
  }

  /**
   * BrowserSpaceBannerField: each pattern's shapes over the first fill, each
   * fill one color or a gradient of its own across the shape it paints: a
   * half or a band its own, the shapes laid over the whole banner the banner.
   */
  function patternField(pattern: string, fills: readonly SpaceFill[], id: string, w: number, h: number): Field {
    const definitions: Definition[] = [];
    const paint = (slot: number, box: FillBox) => {
      const index = Math.min(slot, fills.length - 1);
      const painted = fillPaint(fills[index], `${id}-${definitions.length}`, box);
      if (painted.definition) definitions.push(painted.definition);
      return painted.paint;
    };
    const whole: FillBox = { x: 0, y: 0, width: w, height: h };
    const polygon = (points: readonly (readonly [number, number])[], fill: string): FieldShape => (
      { kind: "polygon", points: points.map(([x, y]) => `${x * w},${y * h}`).join(" "), fill }
    );
    const shapes = (() => {
      switch (pattern) {
        case "split":
          return [
            { kind: "rect", width: w / 2, height: h, fill: paint(0, { x: 0, y: 0, width: w / 2, height: h }) },
            { kind: "rect", x: w / 2, width: w / 2, height: h, fill: paint(1, { x: w / 2, y: 0, width: w / 2, height: h }) },
          ] satisfies FieldShape[];
        case "bands":
          return [0, 1, 2].map((band): FieldShape => ({
            kind: "rect", y: (band * h) / 3, width: w, height: h / 3,
            fill: paint(band, { x: 0, y: (band * h) / 3, width: w, height: h / 3 }),
          }));
        default:
          return overlaidShapes(pattern, paint(0, whole), () => paint(1, whole), () => paint(2, whole), polygon, w, h);
      }
    })();
    return { definitions, shapes };
  }

  /** The patterns whose shapes lie over the whole banner, each painted from its fill across the banner. */
  function overlaidShapes(pattern: string, baseFill: string, secondFill: () => string, thirdFill: () => string,
    polygon: (points: readonly (readonly [number, number])[], fill: string) => FieldShape, w: number, h: number,
  ): FieldShape[] {
    const second = pattern === "solid" ? "" : secondFill();
    const third = pattern === "solid" ? "" : thirdFill();
    const base: FieldShape = { kind: "rect", width: w, height: h, fill: baseFill };
    switch (pattern) {
      case "solid":
        return [base];
      case "diagonal":
        return [
          base,
          polygon([[0, 0.5], [1, 0.34], [1, 0.5], [0, 0.68]], second),
          polygon([[0, 0.68], [1, 0.5], [1, 1], [0, 1]], third),
        ];
      case "chevron":
        return [
          base,
          polygon([[0, 0.42], [0.5, 0.58], [1, 0.42], [1, 0.62], [0.5, 0.78], [0, 0.62]], second),
          polygon([[0, 0.62], [0.5, 0.78], [1, 0.62], [1, 1], [0, 1]], third),
        ];
      case "quartered":
        return [
          base,
          { kind: "rect", x: w / 2, width: w / 2, height: h / 2, fill: second },
          { kind: "rect", y: h / 2, width: w / 2, height: h / 2, fill: third },
        ];
      case "stripes":
      case "checkered":
      case "lozenges":
        return [base, ...cells(pattern, second, third, w, h)];
      default:
        return [base];
    }
  }

  /** The tiled patterns, in cells a fifth of the banner wide. */
  function cells(pattern: string, second: string, third: string, width: number, height: number): FieldShape[] {
    const cell = Math.max(16, width / 5);
    const rows = Math.min(200, Math.ceil(height / cell) + 1);
    const columns = Math.min(200, Math.ceil(width / cell) + 1);
    const shapes: FieldShape[] = [];
    for (let row = 0; row < rows; row++) {
      for (let column = 0; column < columns; column++) {
        const x = column * cell;
        const y = row * cell;
        if (pattern === "stripes" && column % 2 === 0) {
          shapes.push({ kind: "rect", x, y, width: cell, height: cell, fill: second, fillOpacity: 0.35 });
        } else if (pattern === "checkered" && (row + column) % 2 === 0) {
          shapes.push({ kind: "rect", x, y, width: cell, height: cell, fill: second, fillOpacity: 0.35 });
        } else if (pattern === "lozenges") {
          const points = `${x + cell / 2},${y} ${x + cell},${y + cell / 2} ${x + cell / 2},${y + cell} ${x},${y + cell / 2}`;
          shapes.push({ kind: "polygon", points, fill: (row + column) % 2 === 0 ? second : third, fillOpacity: 0.35 });
        }
      }
    }
    return shapes;
  }

  /** BrowserSpaceGradientField: the sidebar's colors as one gradient of its kind, across the banner. */
  function gradientField(fill: SpaceFill, id: string, width: number, height: number): Field {
    const painted = fillPaint(fill, `${id}-gradient`, { x: 0, y: 0, width, height });
    return {
      definitions: painted.definition ? [painted.definition] : [],
      shapes: [{ kind: "rect", width, height, fill: painted.paint }],
    };
  }
</script>

<script lang="ts">
  import type { SpaceBranding } from "@crest/contracts";
  import { MediaQuery } from "svelte/reactivity";

  import FillDefinition from "../../spaces/FillDefinition.svelte";
  import { sidebarFill, slotFill } from "../../spaces/space-fills";
  import Grain from "./Grain.svelte";

  /** The Space's sidebar field at `width` by `height`, as its banner draws it: the Space editor's stage shows it too. */
  let { branding, width, height }: { branding: SpaceBranding; width: number; height: number } = $props();

  const reducedTransparency = new MediaQuery("(prefers-reduced-transparency: reduce)");
  const moreContrast = new MediaQuery("(prefers-contrast: more)");
  const reducesTransparency = $derived(reducedTransparency.current);
  const increasesContrast = $derived(moreContrast.current);
  const fieldOpacity = $derived(reducesTransparency ? Math.max(branding.bannerStrength, 0.85) : branding.bannerStrength);
  const configuredFade = $derived(reducesTransparency ? Math.max(branding.readabilityFade, 0.42) : branding.readabilityFade);
  const fade = $derived(Math.min(configuredFade * 0.55 + (increasesContrast ? 0.1 : 0), 0.7));
  const grain = $derived(branding.textureStrength * (reducesTransparency ? 0.24 : 0.38));
  // The palette's colors as the banner fills them, each running into its own gradient where it has one.
  const fills = $derived((branding.colors.colors.length > 0 ? branding.colors.colors : [null])
    .map((_, slot) => slotFill(branding, slot)));
  // Banners blend over each other, so each one's gradients need names of their own.
  const uid = $props.id();
  const id = `space-banner-${uid.replace(/:/g, "")}`;
  const field = $derived(branding.themeMode.name === "gradient"
    ? gradientField(sidebarFill(branding), id, width, height)
    : patternField(branding.bannerPattern.name, fills, id, width, height));
</script>

<div class="space-banner-window"></div>
<svg class="space-banner-field" {width} {height} viewBox="0 0 {width} {height}" style:opacity={fieldOpacity}>
  {#if field.definitions.length > 0}
    <defs>
      {#each field.definitions as definition (definition.id)}
        <FillDefinition {definition} />
      {/each}
    </defs>
  {/if}
  {#each field.shapes as shape}
    {#if shape.kind === "rect"}
      <rect x={shape.x} y={shape.y} width={shape.width} height={shape.height} fill={shape.fill}
        fill-opacity={shape.fillOpacity} />
    {:else}
      <polygon points={shape.points} fill={shape.fill} fill-opacity={shape.fillOpacity} />
    {/if}
  {/each}
</svg>
{#if fade > 0}<div class="space-banner-fade" style:opacity={fade}></div>{/if}
{#if branding.textureStrength > 0}<Grain {width} {height} opacity={grain} />{/if}
