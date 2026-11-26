<script lang="ts" module>
  /** A preference this device keeps for itself, in local storage, as the Mac's appearance store keeps its own. */
  function useDeviceToggle(key: () => string, fallback: () => boolean): { current: boolean } {
    const read = () => {
      try {
        const stored = localStorage.getItem(key());
        return stored === null ? fallback() : stored !== "false";
      } catch {
        return fallback();
      }
    };
    let value = $state(read());
    return {
      get current() {
        return value;
      },
      set current(on) {
        try {
          localStorage.setItem(key(), String(on));
        } catch {
          // The preference stays for this session only.
        }
        value = on;
      },
    };
  }
</script>

<script lang="ts">
  import { LinkBehavior } from "@crest/contracts";

  import { sidebarSlideDefault } from "@crest/design";
  import { sidebarSlide } from "../shell/sidebar-slide.svelte";
  import { Group, Row, Toggle } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { useLinkPreferences } from "./preferences.svelte";

  /** BrowserLookAndFeelSettingsPane, as far as Windows draws it: motion, previews on hover, and Super Copy. */
  let { session }: PaneProps = $props();

  const slides = useDeviceToggle(() => "crest.appearance.animate-space-pages", () => true);
  const previewsTabs = useDeviceToggle(() => "crest.appearance.hover-preview.tabs", () => true);
  const links = useLinkPreferences(() => session);
</script>

<Group title="Window">
  <Row title="Sidebar slide time" htmlFor="sidebar-slide-time"
    onReset={sidebarSlide.milliseconds === sidebarSlideDefault ? null : () => sidebarSlide.set(sidebarSlideDefault)}>
    <input id="sidebar-slide-time" class="forge-slider" type="range" min="0" max="480" step="10"
      value={sidebarSlide.milliseconds} aria-valuetext={sidebarSlide.milliseconds ? `${sidebarSlide.milliseconds} ms` : "Snap"}
      oninput={(event) => sidebarSlide.set(event.currentTarget.valueAsNumber)} />
    <span class="forge-readout">{sidebarSlide.milliseconds ? `${sidebarSlide.milliseconds} ms` : "Snap"}</span>
  </Row>
  <Toggle title="Animate pages when switching Spaces" checked={slides.current} defaultValue onChange={(on) => (slides.current = on)} />
</Group>
<Group title="Address field"
  footer="With Super Copy, copying or sharing a link leaves out its trackers, using AdGuard's URL Tracking filter. Copying the selected address keeps everything.">
  <Toggle title="Super Copy" checked={links.current?.cleansCopiedLinks ?? true} defaultValue disabled={!links.current}
    onChange={(on) => links.setBehavior(LinkBehavior.cleansCopiedLinks, on)} />
</Group>
<Group title="Preview hover" footer="Applies to every Space on this device. Doesn’t sync.">
  <Toggle title="Tabs" checked={previewsTabs.current} defaultValue onChange={(on) => (previewsTabs.current = on)} />
</Group>
