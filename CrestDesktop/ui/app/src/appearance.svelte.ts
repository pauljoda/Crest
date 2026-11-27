import { sidebarSlideDefault } from "@crest/design";
import { MediaQuery } from "svelte/reactivity";

/** Per-device presentation values, shared by the open windows on this device. */
const refreshers = new Map<string, () => void>();
function refresh(event: StorageEvent) {
  if (event.storageArea !== localStorage) return;
  if (event.key === null) refreshers.forEach(read => read());
  else refreshers.get(event.key)?.();
}
window.addEventListener("storage", refresh);
if (import.meta.hot) import.meta.hot.dispose(() => window.removeEventListener("storage", refresh));

function preference<T extends number | boolean | string>(name: string, fallback: T, parse: (text: string) => T) {
  const key = "crest.appearance." + name;
  function stored() {
    try {
      const value = localStorage.getItem(key);
      return value == null ? fallback : parse(value);
    } catch { return fallback; }
  }
  let current = $state.raw<T>(stored());
  refreshers.set(key, () => { current = stored(); });
  function set(value: T) {
    current = parse(String(value));
    try { localStorage.setItem(key, String(current)); }
    catch { /* This window can still use the chosen setting. */ }
  }
  return { fallback, get current() { return current; }, set, reset: () => set(fallback) };
}

function range(name: string, fallback: number, min: number, max: number, step: number) {
  const value = preference(name, fallback, text => {
    const number = text.trim() ? Number(text) : NaN;
    return Number.isFinite(number) ? Math.round(Math.min(max, Math.max(min, number)) / step) * step : fallback;
  });
  return Object.assign(value, { min, max, step });
}
function toggle(name: string, fallback: boolean) {
  return preference(name, fallback, text => text === "true" || (text !== "false" && fallback));
}

type ColorMode = "system" | "light" | "dark";
export const colorMode = preference<ColorMode>("mode", "system", text =>
  text === "light" || text === "dark" ? text : "system");
const systemDark = new MediaQuery("(prefers-color-scheme: dark)");
export const useReadsDark = () => colorMode.current === "system" ? systemDark.current : colorMode.current === "dark";
export const customChromeAccent = preference<string>("chrome-accent", "", text => /^#[0-9a-f]{6}$/i.test(text) ? text : "");
export const sidebarOnRight = toggle("sidebar-on-right", false);
export const addressPlacement = preference<"sidebar" | "top">("address-bar-placement", "sidebar", text => text === "top" ? "top" : "sidebar");
export const animateCommandPalette = toggle("animate-command-palette", true);
export const windowBorder = range("window-border-width", 8, 0, 10, 1);
export const spaceIconDisplay = preference<"icons" | "dots">("space-icons", "icons", text => text === "dots" ? "dots" : "icons");
export const spaceIconSizing = preference<"automatic" | "manual">("spaceIconSizing", "automatic", text => text === "manual" ? "manual" : "automatic");
// This preference is stored as a factor so existing windows keep their chosen size.
export const spaceIconScale = range("spaceIconScale", 1, 0.3, 1.5, 0.05);
export const darkSpaceDimming = range("dark-space-dimming", 0, 0, 100, 1);

export const sidebarSlide = range("sidebar-slide-length", sidebarSlideDefault, 0, 480, 10);
export const sidebarMotionFactor = () => sidebarSlide.current / sidebarSlide.fallback;
export const fullscreenSidebarReveal = toggle("sidebar-fullscreen-reveal", false);
export const sidebarRevealWidth = range("sidebar-reveal-width", 14, 1, 24, 1);
export const sidebarRevealDelay = range("sidebar-reveal-delay", 200, 0, 1000, 10);
export const animateSpacePages = toggle("animate-space-pages", true);
export const paperSelection = toggle("selected-tab-paper", true);
export const paperOpacity = range("selected-tab-paper-opacity", 80, 50, 100, 1);
export const tintSelectedPins = toggle("tint-selected-pins", true);
export const websitePinColors = toggle("website-pin-colors", true);
export const dimUnloaded = toggle("dim-unloaded-tabs", true);
export const tabSize = range("tab-size", 100, 60, 140, 10);
export const pinLayout = range("pin-columns", 0, 0, 6, 1);
export const stretchPins = toggle("pins-fill-row", false);
export const spacingChoices = [
  { value: 0, label: "None" }, { value: 0.5, label: "Tight" }, { value: 1, label: "Default" }, { value: 1.5, label: "Relaxed" },
];
export const sidebarSpacing = range("sidebar-spacing", 1, 0, 1.5, 0.5);
export const tabScale = () => tabSize.current / 100;
export const tabContentScale = () => (1 + tabScale()) / 2;
export const pinGap = () => Math.max(2, 8 * tabScale() * sidebarSpacing.current);
export const previewTabs = toggle("hover-preview.tabs", true);
export const previewFolders = toggle("hover-preview.folders", true);
export const peekTime = range("peek-open-duration", 240, 0, 800, 10);
export const peekSize = range("peek-size", 100, 80, 100, 1);
export type AppearanceRange = ReturnType<typeof range>;
