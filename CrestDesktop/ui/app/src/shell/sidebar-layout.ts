/**
 * How wide the sidebar may be and the width a window opens with when it
 * keeps none of its own, as the Mac's BrowserChromeLayout sets them.
 */
export const sidebarWidths = { minimum: 164, ideal: 289, maximum: 380 } as const;

export function clampedSidebarWidth(width: number): number {
  return Math.min(Math.max(width, sidebarWidths.minimum), sidebarWidths.maximum);
}

/**
 * A window's sidebar layout on this device, as the Mac's BrowserWindowState:
 * how wide the sidebar is and whether it is shown. Only the platform reads
 * it; what the window shows is the core's window state.
 */
interface WindowLayout {
  readonly id: string;
  readonly sidebarWidth?: number;
  readonly sidebarIsPresented?: boolean;
}

/** Every window's layout, the window used longest ago first, as the Mac's BrowserWindowLayouts keeps them. */
const layoutsKey = "crest.windowLayouts.v1";
/** The width a window last committed, which a window keeping none of its own opens with. */
const widthKey = "crest.sidebarWidth";
/** More windows than anyone keeps open; the one used longest ago is forgotten first. */
const maximumCount = 16;

// The interface's storage can be missing or refuse a write; the sidebar then
// opens at the ideal width and forgets what it was given.
function readLayouts(): WindowLayout[] {
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(layoutsKey) ?? "[]");
    return Array.isArray(parsed)
      ? parsed.filter((layout): layout is WindowLayout => typeof layout?.id === "string")
      : [];
  } catch {
    return [];
  }
}

function write(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    // Nothing to keep it in.
  }
}

/** The width the window `id` opens its sidebar at: its own, or the one last committed. */
export function initialSidebarWidth(id: string): number {
  const own = readLayouts().find((layout) => layout.id === id)?.sidebarWidth;
  if (typeof own === "number" && Number.isFinite(own) && own > 0) return clampedSidebarWidth(own);
  try {
    const last = Number(localStorage.getItem(widthKey));
    return last > 0 ? clampedSidebarWidth(last) : sidebarWidths.ideal;
  } catch {
    return sidebarWidths.ideal;
  }
}

/** Whether the window `id` opens with its sidebar shown, as it last had it. */
export function initialSidebarIsPresented(id: string): boolean {
  return readLayouts().find((layout) => layout.id === id)?.sidebarIsPresented ?? true;
}

/**
 * Keeps what changed of the window's sidebar as its most recently used
 * layout. A committed width also becomes the width new windows open with.
 */
export function captureSidebar(id: string, change: { readonly width?: number; readonly isPresented?: boolean }) {
  const layouts = readLayouts();
  const previous = layouts.find((layout) => layout.id === id) ?? { id };
  const next: WindowLayout = {
    ...previous,
    ...(change.width !== undefined && Number.isFinite(change.width) && change.width > 0 ? { sidebarWidth: change.width } : {}),
    ...(change.isPresented !== undefined ? { sidebarIsPresented: change.isPresented } : {}),
  };
  if (change.width !== undefined) write(widthKey, String(change.width));
  if (next.sidebarWidth === previous.sidebarWidth && next.sidebarIsPresented === previous.sidebarIsPresented) return;
  const kept = [...layouts.filter((layout) => layout.id !== id), next].slice(-maximumCount);
  write(layoutsKey, JSON.stringify(kept));
}
