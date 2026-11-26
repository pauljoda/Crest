<script lang="ts" module>
  /** Windows names the modifier keys Ctrl, Alt and Shift, where the Mac has ⌘, ⌥ and ⇧. */
  const modifierTitles: Readonly<Record<string, string>> = { option: "Alt", command: "Ctrl", shift: "Shift" };
</script>

<script lang="ts">
  import { ChooseExternalLinkDestination, ChoosePeekModifier, ExternalLinkDestination, LinkBehavior, LinkPeekModifier } from "@crest/contracts";

  import { peekSize, peekTime } from "../appearance.svelte";
  import { getSamplePeek } from "../shell/peek-sample";
  import AppearanceSlider from "./controls/AppearanceSlider.svelte";
  import LinkRoutingSection from "./LinkRoutingSection.svelte";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { Button, Group, Picker, Toggle } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { send, useLinkPreferences } from "./preferences.svelte";

  /** BrowserLinkSettingsPane's Peek section, as Windows opens Peeks. */
  let { session, spaces, shownSpace }: PaneProps = $props();

  const testPeek = getSamplePeek();
  const links = useLinkPreferences(() => session);
</script>

{#if links.current}
  {@const modifier = links.current.peekModifier}
  {@const newTabKey = modifierTitles[modifier.name === "command" ? "option" : "command"]}
  {@const destination = links.current.destination.opensQuickWindow ? ExternalLinkDestination.mostRecentSpace : links.current.destination}
  <Group title="Links from other apps">
    <Picker title="Open in" value={destination.name}
      choices={ExternalLinkDestination.all.filter(value => !value.opensQuickWindow).map(value => ({ value: value.name, label: value.title }))}
      onChange={name => {
        const choice = ExternalLinkDestination.named(name);
        if (choice) send(session, ChooseExternalLinkDestination({destination: choice, spaceId: choice.asksForSpace ? shownSpace.id : null}));
      }} />
    {#if destination.asksForSpace}
      <Picker title="Space" value={links.current.destinationSpaceId ?? shownSpace.id}
        choices={spaces.map(space => ({value: space.id, label: space.settings.name || "Untitled Space"}))}
        onChange={spaceId => send(session, ChooseExternalLinkDestination({ destination, spaceId }))} />
    {/if}
  </Group>
  <Group title="Peek" footer={`${newTabKey}-click opens a new tab${modifier.name === "command" ? ", while Ctrl-click opens Peek" : ""}.`}>
    <Toggle title="Open cross-site links from pinned and saved tabs in Peek" checked={links.current.opensPeekAutomatically} defaultValue
      onChange={(on) => links.setBehavior(LinkBehavior.opensPeekAutomatically, on)} />
    <Picker title="Open Peek with" value={modifier.name} defaultValue="option"
      choices={LinkPeekModifier.all.map((value) => ({ value: value.name, label: modifierTitles[value.name] ?? value.title }))}
      onChange={(name) => {
        const chosen = LinkPeekModifier.named(name);
        if (chosen) send(session, ChoosePeekModifier({ modifier: chosen }));
      }} />
    <Toggle title="Dim the page behind Peek" checked={links.current.dimsPageBehindPeek} defaultValue
      onChange={(on) => links.setBehavior(LinkBehavior.dimsPageBehindPeek, on)} />
    <AppearanceSlider title="Peek size" id="peek-size" preference={peekSize} unit="%" />
    <AppearanceSlider title="Peek animation time" id="peek-animation-time" preference={peekTime} unit=" ms" zero="Instant" />
    <div class="settings-row"><Button onClick={testPeek}><SymbolIcon name="rectangle.on.rectangle" size={13} /> Test Peek</Button></div>
  </Group>
  <LinkRoutingSection {session} {spaces} routes={links.current.routes} spaceId={shownSpace.id} />
{/if}
