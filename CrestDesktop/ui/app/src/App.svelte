<script lang="ts">
  import type { SetupEntry } from "@crest/contracts";

  import { useReadsDark } from "./appearance.svelte";
  import { boot, type Session } from "./boot";
  import { setupLauncher } from "./commands";
  import SetupWindow from "./setup/SetupWindow.svelte";
  import BrowserWindow from "./shell/BrowserWindow.svelte";
  import ContextMenuLayer from "./shell/ContextMenu/ContextMenuLayer.svelte";

  $effect.pre(() => { document.documentElement.dataset.appearance = useReadsDark() ? "dark" : "light"; });

  const bridge = new URLSearchParams(location.search).get("bridge") ?? "ws://127.0.0.1:8787/core";

  let session = $state<Session | null>(null);
  let failure = $state<string | null>(null);
  // Setup over the window: a launch held for first-run Setup shows it until it finishes, then the window opens beneath it
  // and Setup fades into it; Settings opens it over the window that is already open.
  let setup = $state<{ entry: SetupEntry; held: boolean; handingOver: boolean } | null>(null);

  setupLauncher.open = (entry) => {
    setup ??= { entry, held: false, handingOver: false };
  };
  boot(bridge).then((started) => {
    // Development builds expose the session for inspection from the console.
    if (import.meta.env.DEV) Object.assign(window, { crest: started });
    const held = started.setup.current;
    setup = held ? { entry: held.entry, held: true, handingOver: false } : null;
    session = started;
  }, (error: unknown) => {
    failure = String(error);
  });
</script>

{#if failure}
  <div class="boot-failure">{failure}</div>
{:else if !session}
  <div class="window-loading"></div>
{:else}
  {#if !(setup?.held && !setup.handingOver)}
    <BrowserWindow {session} />
  {/if}
  {#if setup}
    <SetupWindow {session} entry={setup.entry} holdsLaunch={setup.held}
      onOpened={() => {
        if (setup) setup = { ...setup, handingOver: true };
      }}
      onHandedOver={() => (setup = null)}
      onCancel={setup.held ? null : () => (setup = null)} />
  {/if}
  <ContextMenuLayer />
{/if}
