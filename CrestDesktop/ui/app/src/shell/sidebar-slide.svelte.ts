import { sidebarSlideDefault } from "@crest/design";

const storageKey = "crest.appearance.sidebar-slide-length";

function milliseconds(value: string | null): number {
  const parsed = value?.trim() ? Number(value) : NaN;
  return Number.isFinite(parsed) ? Math.round(Math.min(480, Math.max(0, parsed)) / 10) * 10 : sidebarSlideDefault;
}

function stored(): number {
  try { return milliseconds(localStorage.getItem(storageKey)); }
  catch { return sidebarSlideDefault; }
}

let duration = $state(stored());

// Other Crest windows share this device preference. A storage event also fires for clear().
window.addEventListener("storage", event => {
  if (event.key === storageKey || event.key === null) duration = stored();
});

export const sidebarSlide = {
  get milliseconds() { return duration; },
  get factor() { return duration / sidebarSlideDefault; },
  set(millisecondsValue: number) {
    duration = milliseconds(String(millisecondsValue));
    try { localStorage.setItem(storageKey, String(duration)); }
    catch { /* The current window still uses the chosen duration. */ }
  },
};
