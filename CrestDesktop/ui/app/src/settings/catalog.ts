import { brand } from "@crest/design";

/**
 * The Mac's BrowserSettingsDestination catalog, as Windows offers it: each
 * page of Settings, its sidebar row's words and symbol, the brand color its
 * symbol wears, and the words search finds it by. Windows leaves out what
 * only Apple's systems back: iCloud Sync, the WebKit engine choice, and the
 * coding-agent helper.
 */
export interface SettingsDestination {
  readonly name: SettingsPageName;
  /** The page's own title, which its header shows. */
  readonly title: string;
  /** What the sidebar row says, where the title is too long for it. */
  readonly navigationTitle: string;
  readonly subtitle: string;
  readonly searchTerms: string;
  readonly symbol: string;
  /** The brand color its glyph wears, as red, green and blue from 0 through 255. */
  readonly color: readonly [number, number, number];
}

export type SettingsPageName =
  | "general" | "tabs" | "search" | "lookAndFeel" | "links" | "shortcuts" | "privacy" | "adBlocking"
  | "spaces" | "featureFlags" | "extensions" | "advanced" | "about";

const destination = (name: SettingsPageName, title: string, subtitle: string, symbol: string,
  color: readonly [number, number, number], searchTerms: string, navigationTitle = title): SettingsDestination =>
  ({ name, title, navigationTitle, subtitle, searchTerms, symbol, color });

export const destinations: Readonly<Record<SettingsPageName, SettingsDestination>> = {
  general: destination("general", "General", "Browsing and startup", "gearshape", brand.crestBlue,
    "browser startup default Space developer toolbar localhost local pages new tab"),
  tabs: destination("tabs", "Tabs", "New, pinned and saved tabs", "square.on.square", brand.sky,
    "focus switch new tabs follow move between Spaces Ctrl-click middle-click Shift pinned saved close resume restore root URL favicon Split View focus follows mouse pointer recent tabs switcher"),
  search: destination("search", "Search", "Search engine, command palette and site searches", "magnifyingglass", brand.butter,
    "search engine Google suggestions command palette address bar results order top hit blended sections complete addresses inline autocomplete learn choices clear site searches shortcuts Tab YouTube Wikipedia scopes calculator paste and go reasons"),
  lookAndFeel: destination("lookAndFeel", "Appearance", "Window, tabs, zoom and motion", "paintpalette", brand.coral,
    "theme animation sidebar slide hover area delay pin layout stretch tab size spacing paper opacity website colors previews folders Super Copy"),
  links: destination("links", "Links", "Quick Window and Peek", "link", brand.sage,
    "Peek size animation time modifier cross-site pinned saved links dim test"),
  shortcuts: destination("shortcuts", "Shortcuts", "Keyboard commands", "keyboard", brand.butter,
    "keyboard keys commands rebind remap hotkeys navigation tabs Spaces page"),
  privacy: destination("privacy", "Privacy & Permissions", "Site access and data", "hand.raised", brand.coral,
    "camera microphone site access history cookies data website cache clear browsing", "Privacy"),
  adBlocking: destination("adBlocking", "Ad Blocking", "Filter lists, your rules and sites", "shield.lefthalf.filled", brand.sage,
    "ads trackers content blocking filter lists subscribe EasyList uBlock AdGuard my filters custom rules block element cookie notices strict balanced"),
  spaces: destination("spaces", "Spaces", "Profiles and appearance", "square.grid.2x2", brand.crestBlue,
    "profile name identity icon color appearance theme search cleanup isolation reorder browsing archive independence"),
  extensions: destination("extensions", "Extensions", "Space extensions and permissions", "puzzlepiece.extension", brand.sky,
    "extensions permissions Chromium Chrome Web Store install copies Spaces"),
  featureFlags: destination("featureFlags", "Feature Flags", "Chromium features", "flag", brand.sage, "engine experimental flags"),
  advanced: destination("advanced", "Advanced", "Setup and onboarding", "switch.2", brand.coral,
    "setup onboarding rerun welcome review customize Spaces feature flags"),
  about: destination("about", "About", "Version, updates, and support", "info.circle", brand.sky,
    "version build updates changelog what's new feedback Reddit GitHub issues roadmap support community"),
};

/** The sidebar's rows before the Spaces, and after them, in the Mac's order less what Windows leaves out. */
export const leadingRows: readonly SettingsPageName[] = ["general", "tabs", "search", "lookAndFeel", "links", "shortcuts", "privacy", "adBlocking"];
export const trailingRows: readonly SettingsPageName[] = ["advanced", "about"];

/** Whether `destination` answers a search for `query`, by any of its words, ignoring case and accents. */
export function matches(destination: SettingsDestination, query: string): boolean {
  const fold = (text: string) => text.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase();
  const wanted = fold(query.trim());
  if (!wanted) return true;
  return [destination.title, destination.navigationTitle, destination.subtitle, destination.searchTerms]
    .some((text) => fold(text).includes(wanted));
}

/**
 * The sidebar glyph's colour, as the Mac's sidebarGlyphColor: the brand
 * color lifted a little in Dark Mode, and the bright ones, such as butter and
 * sky, deepened in Light Mode so they hold on cream, keeping the hue.
 */
export function sidebarTint(color: readonly [number, number, number], dark: boolean): string {
  const [red, green, blue] = color.map((channel) => channel / 255);
  const max = Math.max(red, green, blue);
  const min = Math.min(red, green, blue);
  const delta = max - min;
  let hue = 0;
  if (delta > 0) {
    if (max === red) hue = ((green - blue) / delta) % 6;
    else if (max === green) hue = (blue - red) / delta + 2;
    else hue = (red - green) / delta + 4;
    hue /= 6;
    if (hue < 0) hue += 1;
  }
  const saturation = max === 0 ? 0 : delta / max;
  const brightness = max;
  const shown = dark ? Math.max(brightness, 0.8) : Math.min(brightness, 0.72);
  const muted = dark ? saturation : Math.min(1, saturation * 1.12);
  // HSB back to RGB.
  const i = Math.floor(hue * 6);
  const f = hue * 6 - i;
  const p = shown * (1 - muted);
  const q = shown * (1 - f * muted);
  const t = shown * (1 - (1 - f) * muted);
  const [r, g, b] = [[shown, t, p], [q, shown, p], [p, shown, t], [p, q, shown], [t, p, shown], [shown, p, q]][i % 6];
  return `rgb(${Math.round(r * 255)} ${Math.round(g * 255)} ${Math.round(b * 255)})`;
}

/** Every page Settings has, as the palette's Settings Pages finds them. */
export const settingsPages = Object.values(destinations).filter(destination => destination.name !== "featureFlags").map((destination) => ({
  name: destination.name,
  title: destination.title,
  terms: `${destination.subtitle} ${destination.searchTerms}`,
}));
