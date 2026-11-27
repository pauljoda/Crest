<script lang="ts">
  import {
    AddLinkRoute, EditLinkRoute, type LinkRoute, LinkRouteMatch, MoveLinkRoute, RemoveLinkRoute, type SpaceState,
  } from "@crest/contracts";

  import type { Session } from "../boot";
  import SymbolIcon from "../SymbolIcon.svelte";
  import { Button, Group, Picker, Row, Toggle } from "./controls";
  import { send } from "./preferences.svelte";

  let { session, routes, spaces, spaceId }: {
    session: Session; routes: readonly LinkRoute[]; spaces: readonly SpaceState[]; spaceId: string;
  } = $props();
  const uid = $props.id();
  const choices = $derived(spaces.map(space => ({value: space.id, label: space.settings.name || "Untitled Space"})));
  function edit(routeId: string, update: Partial<Pick<LinkRoute, "match" | "pattern" | "isEnabled" | "destinationSpaceId">>) {
    send(session, EditLinkRoute({routeId, match: null, pattern: null, isEnabled: null, destinationSpaceId: null, ...update}));
  }
</script>

<Group title="Routing" footer="Routes apply to links from other apps. The first matching route wins.">
  {#each routes as route, index (route.id)}
    <Toggle title="Enable route" checked={route.isEnabled} onChange={isEnabled => edit(route.id, { isEnabled })} />
    <Picker title="URL" value={route.match.name} choices={LinkRouteMatch.all.map(match => ({ value: match.name, label: match.title }))}
      onChange={name => { const match = LinkRouteMatch.named(name); if (match) edit(route.id, { match }); }} />
    <Row title="Pattern" htmlFor={uid + "-pattern-" + route.id}>
      <input id={uid + "-pattern-" + route.id} class="settings-route-pattern" type="text" value={route.pattern}
        onchange={event => edit(route.id, { pattern: event.currentTarget.value })}
        onkeydown={event => { if (event.key === "Enter" && !event.isComposing) event.currentTarget.blur(); }} />
    </Row>
    <Picker title="Open in Space" value={route.destinationSpaceId} {choices}
      onChange={destinationSpaceId => edit(route.id, { destinationSpaceId })} />
    <Row title="Route actions">
      <button class="settings-icon-button" aria-label="Move route up" disabled={index === 0}
        onclick={() => send(session, MoveLinkRoute({routeId: route.id, offset: -1}))}><SymbolIcon name="arrow.up" size={14} /></button>
      <button class="settings-icon-button" aria-label="Move route down" disabled={index + 1 === routes.length}
        onclick={() => send(session, MoveLinkRoute({routeId: route.id, offset: 1}))}><SymbolIcon name="arrow.down" size={14} /></button>
      <button class="settings-icon-button" aria-label="Delete route"
        onclick={() => send(session, RemoveLinkRoute({routeId: route.id}))}><SymbolIcon name="trash" size={14} /></button>
    </Row>
  {:else}
    <Row title="No routes yet." />
  {/each}
  <div class="settings-row"><Button onClick={() => send(session, AddLinkRoute({ routeId: crypto.randomUUID(), destinationSpaceId: spaceId }))}>
    <SymbolIcon name="plus" size={13} /> New Route
  </Button></div>
</Group>
