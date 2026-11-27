<script lang="ts" module>
  import type { PaletteCommand, ShortcutBinding, ShortcutCommand, SpaceState } from "@crest/contracts";

  import type { Session } from "../boot";

  /** A request for a Start Page's palette to start over, for the tab it names. */
  export interface StartPageFocus {
    readonly tabId: string | null;
    readonly count: number;
  }

  /** What the window lends each card it shows (BrowserWindow), read as it stands now. */
  export interface CardHost {
    readonly session: Session;
    /** The tabs whose pages are being opened, and the pages whose first load has been asked for. */
    readonly opening: Set<string>;
    readonly loading: Set<string>;
    /** The Space the window is entering, which opens no remembered page until it shows a Start Page. */
    readonly entering: { readonly current: string | null };
    /** Whether a tab is taking a Peek's page, which no card opens another page for meanwhile. */
    readonly adopting: { readonly current: boolean };
    readonly entries: number;
    readonly commands: Readonly<Record<string, () => void>>;
    readonly offered: { readonly current: { bindings?: readonly ShortcutBinding[]; unavailable?: readonly ShortcutCommand[] } };
    readonly copyAnswer: (text: string) => void;
    readonly bindings: readonly ShortcutBinding[];
    /** Whether the overlay palette covers the cards. */
    readonly obscured: boolean;
    readonly isPrivate: boolean;
    readonly startPageFocus: StartPageFocus;
    /** The pages the window's own cards show, which another Space's preview leaves to them. */
    readonly livePageIds: ReadonlySet<string>;
    /** The workspace's Spaces, which Settings lists. */
    readonly spaces: readonly SpaceState[];
  }

  /**
   * The commands the palette may offer, as the Mac's registry offers them: each
   * the core offers on this device that the palette lists, that this window
   * runs and can run now, under its title and section.
   */
  export function paletteCommands(bindings: readonly ShortcutBinding[], unavailable: readonly ShortcutCommand[],
    handlers: Readonly<Record<string, () => void>>): PaletteCommand[] {
    const blocked = new Set(unavailable.map((command) => command.name));
    return bindings.map((binding) => binding.command)
      .filter((command) => command.offersInPalette && handlers[command.name] && !blocked.has(command.name))
      .map((command) => ({ command, title: command.title, sectionTitle: command.section.title }));
  }
</script>

<script lang="ts">
  import { Navigate, NativeView, OpenPage, type PageState, PagePresentation, TabSurface } from "@crest/contracts";
  import { untrack } from "svelte";

  import GettingStartedView from "../guide/GettingStartedView.svelte";
  import { PaletteModel } from "../palette/palette-model";
  import { suggestionFetcher } from "../palette/suggestions";
  import SettingsView from "../settings/SettingsView.svelte";
  import { useSpacePager } from "../spaces/space-pager";
  import { coreState } from "../use-core";
  import FindBar from "./FindBar.svelte";
  import PageCard, { focusShownPage } from "./PageCard.svelte";
  import type { ColumnCard } from "./PageColumns.svelte";
  import { usePagePresentation } from "./page-presentation.svelte";
  import { sheetPrompt } from "./prompts/prompt-text";
  import { PromptSheet } from "./prompts/PromptSheet";
  import StartPage from "./StartPage.svelte";

  /**
   * One card of the cards a window shows, as the Mac's BrowserSplitCardView:
   * what the core presents for its own tab, focused or not, with the page's
   * find bar and the questions it asks. A card opens its tab's page when the
   * core says the tab restores one, and gives a page its first load. A card
   * of another Space, which the pager shows in passing, is its still preview:
   * the page its tab holds, or the Start Page the window shows on entering
   * it, and a page the window's own cards show, as a group's shared pin can
   * be, stays with them. Live and passing cards are the same element, so a
   * card the window leaves keeps its page attached as it slides away.
   */
  let { host, space, tabId, pages, passive, card }: {
    host: CardHost;
    space: SpaceState;
    tabId: string;
    pages: readonly PageState[];
    passive: boolean;
    card: ColumnCard;
  } = $props();

  const tab = $derived(space.tabs.find((candidate) => candidate.id === tabId));
  const page = $derived(pages.find((candidate) => candidate.tabId === tabId) ?? null);
  const presentation = usePagePresentation(untrack(() => host.session.core), () => ({
    surface: tab?.surface ?? null,
    hasPage: page !== null,
    hasNavigationFailure: !!page?.live.failure,
    hasProcessFailure: false,
    restoresUnloaded: true,
  }));
  const showsStartPage = $derived(passive
    ? !tab || tab.surface === TabSurface.startPage || (tab.surface === TabSurface.webPage && !page)
    : presentation.current === PagePresentation.startPage);
  const restoresPage = $derived(!passive && presentation.current === PagePresentation.automaticRestore);

  // A tab whose surface is a page and that has none restores itself, as the
  // Mac's window restores the tabs it shows.
  const spaceId = $derived(space.id);
  $effect(() => {
    const restores = restoresPage;
    const shownPage = page;
    const restoring = { spaceId, tabId };
    void host.entries;
    untrack(() => {
      const { session, opening, entering, adopting } = host;
      if (!restores || shownPage || opening.has(restoring.tabId) || session.closing.current
        || entering.current === restoring.spaceId || adopting.current) return;
      opening.add(restoring.tabId);
      void session.core.send(OpenPage({
        pageId: crypto.randomUUID(), workspaceId: session.workspaceId, spaceId: restoring.spaceId, tabId: restoring.tabId,
        windowId: session.windowId, transient: null, openerPageId: null,
      })).finally(() => opening.delete(restoring.tabId));
    });
  });

  // A page's first load goes through the core's Navigate, which resolves the
  // tab's address by the Space's rules and asks the engine to load it.
  const firstAddress = $derived(tab?.url ?? tab?.savedUrl ?? null);
  $effect(() => {
    const shownPage = page;
    const address = firstAddress;
    const still = passive;
    untrack(() => {
      if (still || !shownPage || shownPage.phase.name !== "live" || shownPage.live.url || shownPage.live.pendingUrl || !address) return;
      if (host.loading.has(shownPage.id)) return;
      host.loading.add(shownPage.id);
      void host.session.core.send(Navigate({ pageId: shownPage.id, input: address }));
    });
  });

  // The Start Page's palette, which speaks for the tab it shows and starts
  // over for another tab, another Space, or New Tab on the page. A card the
  // pager shows still keeps its palette, results and all, as the Mac's does,
  // so a slide carries it whole rather than it appearing once the slide ends;
  // the strip keeps such a card inert, and only the live one takes the keys.
  let focusRequest = 0;
  const focusCount = $derived.by(() => {
    if (host.startPageFocus.tabId === tabId) focusRequest = host.startPageFocus.count;
    return focusRequest;
  });
  // A palette starts over only for another tab, Space or focus request.
  const palette = $derived.by(() => {
    if (!showsStartPage) return null;
    const shown = { spaceId, tabId, commands: host.commands };
    void focusCount;
    return untrack(() => {
      const { session, offered, copyAnswer } = host;
      return new PaletteModel({
        core: session.core,
        // Crest's Chromium fetches the search engine's suggestions, as the Mac app does.
        fetchSuggestions: suggestionFetcher(session.shell),
        windowId: session.windowId,
        workspaceId: session.workspaceId,
        spaceId: shown.spaceId,
        tabId: shown.tabId,
        pageId: null,
        get commands() {
          return paletteCommands(offered.current.bindings ?? [], offered.current.unavailable ?? [], shown.commands);
        },
        runCommand: (name) => shown.commands[name]?.(),
        copy: copyAnswer,
        // The page's palette stays where it is.
        dismiss: () => {},
      }, { kind: "startPage" });
    });
  });
  $effect(() => {
    const model = palette;
    return () => model?.close();
  });
  // A Start Page card that becomes the focused one takes the keyboard from the page that had it.
  const focused = $derived(card.focused);
  $effect(() => {
    if (!passive && focused && showsStartPage && document.activeElement instanceof HTMLEmbedElement) {
      requestAnimationFrame(focusShownPage);
    }
  });

  // A card is inert while the pager moves it, so its palette takes the keys once it settles.
  const moving = $derived(useSpacePager().phase !== "idle");
  const pageId = $derived(showsStartPage ? null
    : passive ? (tab?.surface === TabSurface.webPage && page && !host.livePageIds.has(page.id) ? page.id : null)
      : page?.id ?? null);
  // A tab can show one of Crest's own views in place of a page: Settings, or the Getting Started guide.
  // Another Space's card in passing shows the guide's canvas alone, since its practice is the live card's.
  const native = $derived(tab?.surface === TabSurface.nativeView ? tab.nativeView : null);
  const showsNative = $derived(!!tab && native !== null);
</script>

{#snippet nativeContent()}
  {#if native === NativeView.settings}
    <SettingsView session={host.session} {tabId} spaces={host.spaces} shownSpace={space} />
  {:else if native === NativeView.gettingStarted}
    {#if passive}
      <div class="getting-started" aria-hidden="true"></div>
    {:else}
      <GettingStartedView session={host.session} {tabId} />
    {/if}
  {:else}
    {@render unknownNativeView()}
  {/if}
{/snippet}

<!-- BrowserNativeTabHost's answer for a view this build doesn't draw. -->
{#snippet unknownNativeView()}
  <div class="native-unknown">
    <h2>This tab needs a newer Crest</h2>
    <p>Its content is still saved. Update Crest to open it.</p>
  </div>
{/snippet}

{#snippet startPage()}
  <StartPage {palette} isPrivate={host.isPrivate} bindings={palette ? host.bindings : []}
    tabs={palette ? space.tabs : []} obscured={host.obscured} takesFocus={card.focused && !passive && !moving} />
{/snippet}

<PageCard session={host.session} pageId={showsNative ? null : pageId} {passive} focused={card.focused} transition={card.transition}
  startPage={showsNative ? nativeContent : showsStartPage ? startPage : null}>
  {#if !passive && page && !showsStartPage}
    <FindBar core={host.session.core} pageId={page.id} />
  {/if}
  {#if !passive}
    <PromptSheet session={host.session} prompt={sheetPrompt(coreState(host.session), page?.id ?? null)} spaceName={space.settings.name} />
  {/if}
</PageCard>
