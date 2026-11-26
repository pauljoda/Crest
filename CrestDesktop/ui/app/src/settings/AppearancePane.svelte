<script lang="ts">
  import { LinkBehavior } from "@crest/contracts";

  import {
    addressPlacement, animateCommandPalette, animateSpacePages, colorMode, customChromeAccent, darkSpaceDimming, dimUnloaded, fullscreenSidebarReveal, paperOpacity, paperSelection, pinLayout, previewFolders, previewTabs,
    sidebarOnRight, sidebarRevealDelay, sidebarRevealWidth, sidebarSlide, sidebarSpacing, spacingChoices, stretchPins, tabSize,
    spaceIconDisplay, spaceIconSizing, spaceIconScale, tintSelectedPins, websitePinColors, windowBorder,
  } from "../appearance.svelte";
  import { Group, Picker, Row, Segmented, Switch, Toggle } from "./controls";
  import AppearanceSlider from "./controls/AppearanceSlider.svelte";
  import { primaryColor } from "../branding";
  import SymbolIcon from "../SymbolIcon.svelte";
  import LayoutChoice from "./controls/LayoutChoice.svelte";
  import type { PaneProps } from "./panes.svelte";
  import { useLinkPreferences } from "./preferences.svelte";

  /** BrowserLookAndFeelSettingsPane, as far as Windows draws it: motion, previews on hover, and Super Copy. */
  let { session, shownSpace }: PaneProps = $props();

  const accentId = $props.id();
  const chosenAccent = $derived.by(() => {
    const { red, green, blue } = primaryColor(shownSpace.settings.look);
    return "#" + [red, green, blue].map(channel => Math.round(channel * 255).toString(16).padStart(2, "0")).join("");
  });
  function resetGroup(...settings: { readonly current: unknown; readonly fallback: unknown; reset(): void }[]) {
    return settings.some(setting => setting.current !== setting.fallback) ? () => settings.forEach(setting => setting.reset()) : null;
  }
  let showsMore = $state(false);
  const links = useLinkPreferences(() => session);
</script>

<Group title="Address bar" onReset={resetGroup(addressPlacement, animateCommandPalette)}>
  <LayoutChoice label="Address bar" value={addressPlacement.current}
    choices={[{ value: "sidebar", label: "Sidebar" }, { value: "top", label: "Top" }]}
    choose={addressPlacement.set} />
  <Toggle title="Animate into command palette" checked={animateCommandPalette.current} defaultValue={true} onChange={animateCommandPalette.set} />
</Group>
<Group title="Space icons" onReset={spaceIconDisplay.current === "icons" ? null : () => spaceIconDisplay.set("icons")}>
  <LayoutChoice label="Space icons" value={spaceIconDisplay.current} switcher
    choices={[{ value: "icons", label: "Icons" }, { value: "dots", label: "Dots" }]}
    choose={spaceIconDisplay.set} />
</Group>
<Group title="Window" onReset={resetGroup(sidebarOnRight, customChromeAccent, colorMode, animateSpacePages, sidebarRevealDelay, sidebarSlide, fullscreenSidebarReveal)}>
  <Toggle title="Sidebar on right" checked={sidebarOnRight.current} defaultValue={false} onChange={sidebarOnRight.set} />
  <Row title="Follow Space accent" htmlFor={accentId} onReset={customChromeAccent.current ? () => customChromeAccent.set("") : null}>
    {#if customChromeAccent.current}
      <input class="settings-accent-color" type="color" aria-label="Custom accent" value={customChromeAccent.current}
        oninput={event => customChromeAccent.set(event.currentTarget.value)} />
    {/if}
    <Switch id={accentId} checked={!customChromeAccent.current} onChange={follows => customChromeAccent.set(follows ? "" : chosenAccent)} />
  </Row>
  <Row title="Appearance" onReset={colorMode.current === colorMode.fallback ? null : () => colorMode.set(colorMode.fallback)}>
    <Segmented label="Appearance" value={colorMode.current}
      choices={[{ value: "system", label: "System" }, { value: "light", label: "Light" }, { value: "dark", label: "Dark" }]}
      onChange={colorMode.set} />
  </Row>
  <Toggle title="Animate pages when switching Spaces" checked={animateSpacePages.current} defaultValue onChange={animateSpacePages.set} />
  <AppearanceSlider title="Sidebar hover delay" id="sidebar-reveal-delay" preference={sidebarRevealDelay} unit=" ms" zero="Instant" />
  <AppearanceSlider title="Sidebar slide time" id="sidebar-slide-time" preference={sidebarSlide} unit=" ms" zero="Snap" />
  <Toggle title="Show sidebar on hover in full screen" checked={fullscreenSidebarReveal.current} defaultValue={false}
    onChange={fullscreenSidebarReveal.set} />
</Group>
<Group title="Tabs" onReset={resetGroup(tabSize, sidebarSpacing, pinLayout, websitePinColors, dimUnloaded)}>
  <AppearanceSlider title="Tab size" id="tab-scale" preference={tabSize} unit="%" labels={{60: "Thin", 80: "Compact", 100: "Default", 120: "Comfortable", 140: "Large"}} />
  <Row title="Spacing" onReset={sidebarSpacing.current === sidebarSpacing.fallback ? null : () => sidebarSpacing.set(sidebarSpacing.fallback)}>
    <Segmented label="Spacing" value={sidebarSpacing.current} choices={spacingChoices} onChange={sidebarSpacing.set} />
  </Row>
  <Picker title="Pin layout" value={pinLayout.current} defaultValue={pinLayout.fallback}
    choices={["Balanced rows", "One per row", ...[2, 3, 4, 5, 6].map(n => `Up to ${n} per row`)].map((label, value) => ({ value, label }))}
    onChange={pinLayout.set} />
  <Toggle title="Website colors for pins" checked={websitePinColors.current} defaultValue onChange={websitePinColors.set} />
  <Toggle title="Dim unloaded tabs" checked={dimUnloaded.current} defaultValue onChange={dimUnloaded.set} />
</Group>
<Group title="Address field"
  footer="With Super Copy, copying or sharing a link leaves out its trackers, using AdGuard's URL Tracking filter. Copying the selected address keeps everything.">
  <Toggle title="Super Copy" checked={links.current?.cleansCopiedLinks ?? true} defaultValue disabled={!links.current}
    onChange={(on) => links.setBehavior(LinkBehavior.cleansCopiedLinks, on)} />
</Group>
<Group title="Preview hover" onReset={resetGroup(previewFolders, previewTabs)} footer="Applies to every Space on this device. Doesn’t sync.">
  <Toggle title="Folders" checked={previewFolders.current} defaultValue onChange={previewFolders.set} />
  <Toggle title="Tabs" checked={previewTabs.current} defaultValue onChange={previewTabs.set} />
</Group>

<button type="button" class="settings-card forge-more" aria-expanded={showsMore} onclick={() => (showsMore = !showsMore)}>
  <span>More Customization</span>
  <SymbolIcon name="chevron.right" size={11} strokeWidth={2.5} />
</button>
{#if showsMore}
  {#if spaceIconDisplay.current === "icons"}
    <Group title="Space icons" onReset={resetGroup(spaceIconSizing, spaceIconScale)}>
      <Toggle title="Fit Space icons to sidebar" checked={spaceIconSizing.current === "automatic"} defaultValue
        onChange={fits => spaceIconSizing.set(fits ? "automatic" : "manual")} />
      <AppearanceSlider title="Space icon size" id="space-icon-size" preference={spaceIconScale} unit="%" multiplier={100}
        disabled={spaceIconSizing.current === "automatic"} />
    </Group>
  {/if}
  <Group title="Window" onReset={resetGroup(windowBorder, darkSpaceDimming, sidebarRevealWidth)}>
    <AppearanceSlider title="Window border" id="window-border-width" preference={windowBorder} unit=" pt" zero="Borderless" />
    <AppearanceSlider title="Dim Space colors in dark" id="dark-space-dimming" preference={darkSpaceDimming}
      unit="%" labels={{0: "Off", 100: "Full"}} />
    <AppearanceSlider title="Sidebar hover area" id="sidebar-reveal-width" preference={sidebarRevealWidth} unit=" pt" />
  </Group>
  <Group title="Tabs" onReset={resetGroup(stretchPins, paperSelection, paperOpacity, tintSelectedPins)}>
    <Toggle title="Stretch pins to fill the row" checked={stretchPins.current} defaultValue={false} onChange={stretchPins.set} />
    <Row title="Selected tab" onReset={paperSelection.current ? null : () => paperSelection.set(true)}>
      <Segmented label="Selected tab" value={paperSelection.current} choices={[{value: true, label: "White"}, {value: false, label: "Material"}]}
        onChange={paperSelection.set} />
    </Row>
    <AppearanceSlider title="Selected tab opacity" id="selected-tab-opacity" preference={paperOpacity} unit="%"
      labels={{100: "Opaque"}} disabled={!paperSelection.current} />
    <Toggle title="Tint selected pins" checked={tintSelectedPins.current} defaultValue disabled={!paperSelection.current} onChange={tintSelectedPins.set} />
  </Group>
{/if}
