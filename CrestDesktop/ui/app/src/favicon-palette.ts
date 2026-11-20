import { useEffect, useState } from "react";

/**
 * A favicon's own color, as the Mac's BrowserFaviconPaletteExtractor finds it:
 * the icon's colors binned, clustered in Oklab, and the cluster that stands
 * out most from the icon's background chosen, preferring a chromatic one. A
 * pinned tile's selection ring wears it, as the Mac's does.
 */

type Lab = readonly [number, number, number];

const clusterLimit = 8;
const iterationLimit = 8;

const linear = (value: number) => (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
const encoded = (value: number) => (value <= 0.0031308 ? 12.92 * value : 1.055 * value ** (1 / 2.4) - 0.055);
const clamp = (value: number) => Math.min(Math.max(value, 0), 1);

function toLab(red: number, green: number, blue: number): Lab {
  const r = linear(red), g = linear(green), b = linear(blue);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [
    0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
    1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
    0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s,
  ];
}

function fromLab([x, y, z]: Lab): string {
  const l = (x + 0.3963377774 * y + 0.2158037573 * z) ** 3;
  const m = (x - 0.1055613458 * y - 0.0638541728 * z) ** 3;
  const s = (x - 0.0894841775 * y - 1.291485548 * z) ** 3;
  const channel = (value: number) => Math.round(clamp(encoded(value)) * 255);
  return `rgb(${channel(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)} ${channel(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)} ${channel(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)})`;
}

const distance2 = (a: Lab, b: Lab) => (a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2;
const chroma = (color: Lab) => Math.hypot(color[1], color[2]);
const nearest = (color: Lab, centers: Lab[]) =>
  centers.reduce((best, center, index) => (distance2(color, center) < distance2(color, centers[best]) ? index : best), 0);
const argmax = (count: number, score: (index: number) => number) => {
  let best = -1, bestScore = -Infinity;
  for (let index = 0; index < count; index++) {
    const value = score(index);
    if (value > bestScore) [best, bestScore] = [index, value];
  }
  return best;
};

/** The icon's primary color as CSS, or null for an icon with no visible pixels. */
export function faviconPrimaryColor(pixels: Uint8ClampedArray, width: number, height: number): string | null {
  if (width <= 0 || height <= 0 || pixels.length !== width * height * 4) return null;

  // 15-bit bins of each visible pixel's color, weighted by its alpha, with the
  // weight that falls in the icon's outer eighth kept apart as its edge.
  const bins = new Map<number, { red: number; green: number; blue: number; weight: number; edge: number }>();
  const edgeDepth = Math.max(1, Math.floor(Math.min(width, height) / 8));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const offset = (y * width + x) * 4;
      const alpha = pixels[offset + 3] / 255;
      if (alpha < 0.05) continue;
      const key = ((pixels[offset] >> 3) << 10) | ((pixels[offset + 1] >> 3) << 5) | (pixels[offset + 2] >> 3);
      const isEdge = x < edgeDepth || x >= width - edgeDepth || y < edgeDepth || y >= height - edgeDepth;
      const bin = bins.get(key) ?? { red: 0, green: 0, blue: 0, weight: 0, edge: 0 };
      bin.red += (pixels[offset] / 255) * alpha;
      bin.green += (pixels[offset + 1] / 255) * alpha;
      bin.blue += (pixels[offset + 2] / 255) * alpha;
      bin.weight += alpha;
      bin.edge += isEdge ? alpha : 0;
      bins.set(key, bin);
    }
  }
  const colors: Lab[] = [], weights: number[] = [], edges: number[] = [];
  for (const key of [...bins.keys()].sort((a, b) => a - b)) {
    const bin = bins.get(key)!;
    if (bin.weight <= 0) continue;
    colors.push(toLab(clamp(bin.red / bin.weight), clamp(bin.green / bin.weight), clamp(bin.blue / bin.weight)));
    weights.push(bin.weight);
    edges.push(bin.edge);
  }
  if (colors.length === 0) return null;

  // Weighted k-means, seeded from the heaviest color (its edge counting
  // twice) and then the colors farthest from every seed so far.
  const count = Math.min(clusterLimit, colors.length);
  let centers: Lab[] = [colors[argmax(colors.length, (i) => weights[i] + 2 * edges[i])]];
  while (centers.length < count) {
    const candidate = colors[argmax(colors.length, (i) => Math.min(...centers.map((c) => distance2(colors[i], c))) * Math.sqrt(weights[i]))];
    if (!centers.every((center) => distance2(center, candidate) > 0.000001)) break;
    centers.push(candidate);
  }
  for (let iteration = 0; iteration < iterationLimit; iteration++) {
    const sums = centers.map(() => [0, 0, 0]);
    const totals = centers.map(() => 0);
    colors.forEach((color, index) => {
      const cluster = nearest(color, centers);
      for (let axis = 0; axis < 3; axis++) sums[cluster][axis] += color[axis] * weights[index];
      totals[cluster] += weights[index];
    });
    let movement = 0;
    const next = centers.map((center, index) => {
      if (totals[index] <= 0) return center;
      const moved: Lab = [sums[index][0] / totals[index], sums[index][1] / totals[index], sums[index][2] / totals[index]];
      movement = Math.max(movement, distance2(center, moved));
      return moved;
    });
    centers = next;
    if (movement < 0.000004) break;
  }
  const clusterWeights = centers.map(() => 0);
  const clusterEdges = centers.map(() => 0);
  colors.forEach((color, index) => {
    const cluster = nearest(color, centers);
    clusterWeights[cluster] += weights[index];
    clusterEdges[cluster] += edges[index];
  });
  const populated = centers.map((_, index) => index).filter((index) => clusterWeights[index] > 0);
  const clustered = populated.map((index) => centers[index]);
  const clusteredWeights = populated.map((index) => clusterWeights[index]);
  const clusteredEdges = populated.map((index) => clusterEdges[index]);

  // The background is the cluster that covers most of the icon and its edge;
  // the primary color the one that stands out from it most, a chromatic one
  // where there is any, since a brand's color may be the background itself.
  const totalWeight = clusteredWeights.reduce((sum, weight) => sum + weight, 0);
  const totalEdge = Math.max(clusteredEdges.reduce((sum, edge) => sum + edge, 0), 1);
  const background = Math.max(0, argmax(clustered.length, (i) => 0.7 * (clusteredWeights[i] / totalWeight) + 0.3 * (clusteredEdges[i] / totalEdge)));
  const indices = clustered.map((_, index) => index);
  const chromatic = indices.filter((i) => clusteredWeights[i] / totalWeight >= 0.02 && chroma(clustered[i]) >= 0.04);
  const candidates = chromatic.length > 0
    ? chromatic
    : indices.filter((i) => i !== background && clusteredWeights[i] / totalWeight >= 0.02);
  let primary = background, primaryScore = -Infinity;
  for (const index of candidates) {
    const score = Math.sqrt(clusteredWeights[index] / totalWeight) * (0.08 + chroma(clustered[index]))
      * (0.2 + Math.sqrt(distance2(clustered[index], clustered[background])));
    if (score > primaryScore) [primary, primaryScore] = [index, score];
  }
  return fromLab(clustered[primary]);
}

const cache = new Map<string, string | null>();

/** The primary color of the icon at `source`, a same-origin image, once it is read. */
export function useFaviconColor(source: string | null): string | null {
  const [color, setColor] = useState(() => (source ? cache.get(source) ?? null : null));
  useEffect(() => {
    if (!source) {
      setColor(null);
      return;
    }
    if (cache.has(source)) {
      setColor(cache.get(source) ?? null);
      return;
    }
    let current = true;
    const image = new Image();
    image.onload = () => {
      const width = Math.min(image.naturalWidth || 32, 64);
      const height = Math.min(image.naturalHeight || 32, 64);
      const canvas = document.createElement("canvas");
      canvas.width = width;
      canvas.height = height;
      const context = canvas.getContext("2d", { willReadFrequently: true });
      let found: string | null = null;
      try {
        if (context) {
          context.drawImage(image, 0, 0, width, height);
          found = faviconPrimaryColor(context.getImageData(0, 0, width, height).data, width, height);
        }
      } catch {
        // An icon the interface may not read keeps the tile's default ring.
      }
      cache.set(source, found);
      if (current) setColor(found);
    };
    image.onerror = () => {
      cache.set(source, null);
      if (current) setColor(null);
    };
    image.src = source;
    return () => {
      current = false;
    };
  }, [source]);
  return color;
}
