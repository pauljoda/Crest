<script lang="ts" module>
  import type { SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";

  /** What each of Settings' pages is given. */
  export interface PaneProps {
    readonly session: Session;
    readonly spaces: readonly SpaceState[];
    readonly shownSpace: SpaceState;
  }
</script>

<script lang="ts">
  import AboutPane from "./AboutPane.svelte";
  import { AdBlockingPane } from "./AdBlockingPane";
  import AdvancedPane from "./AdvancedPane.svelte";
  import AppearancePane from "./AppearancePane.svelte";
  import type { SettingsPageName } from "./catalog";
  import GeneralPane from "./GeneralPane.svelte";
  import LinksPane from "./LinksPane.svelte";
  import PrivacyPane from "./PrivacyPane.svelte";
  import SearchPane from "./SearchPane.svelte";
  import ShortcutsPane from "./ShortcutsPane.svelte";
  import TabsPane from "./TabsPane.svelte";

  /** The page Settings shows for `name`. */
  let { name, onFlags, ...props }: PaneProps & { name: SettingsPageName; onFlags?: () => void } = $props();
</script>

{#if name === "general"}
  <GeneralPane {...props} />
{:else if name === "tabs"}
  <TabsPane {...props} />
{:else if name === "search"}
  <SearchPane {...props} />
{:else if name === "lookAndFeel"}
  <AppearancePane {...props} />
{:else if name === "links"}
  <LinksPane {...props} />
{:else if name === "shortcuts"}
  <ShortcutsPane session={props.session} />
{:else if name === "privacy"}
  <PrivacyPane {...props} />
{:else if name === "adBlocking"}
  <AdBlockingPane session={props.session} />
{:else if name === "advanced"}
  <AdvancedPane {onFlags} />
{:else if name === "about"}
  <AboutPane {...props} />
{/if}
