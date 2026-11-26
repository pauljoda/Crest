<script lang="ts" module>
  /** Windows names the modifier keys Ctrl, Alt and Shift, where the Mac has ⌘, ⌥ and ⇧. */
  const modifierTitles: Readonly<Record<string, string>> = { option: "Alt", command: "Ctrl", shift: "Shift" };
</script>

<script lang="ts">
  import { ChoosePeekModifier, LinkBehavior, LinkPeekModifier } from "@crest/contracts";

  import { Group, Picker, Toggle } from "./controls";
  import type { PaneProps } from "./panes.svelte";
  import { send, useLinkPreferences } from "./preferences.svelte";

  /** BrowserLinkSettingsPane's Peek section, as Windows opens Peeks. */
  let { session }: PaneProps = $props();

  const links = useLinkPreferences(() => session);
</script>

{#if links.current}
  {@const modifier = links.current.peekModifier}
  {@const newTabKey = modifierTitles[modifier.name === "command" ? "option" : "command"]}
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
  </Group>
{/if}
