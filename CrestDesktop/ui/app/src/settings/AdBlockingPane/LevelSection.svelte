<script lang="ts">
  import { ContentBlockingLevel, type FilterLists, SetContentBlockingLevel } from "@crest/contracts";

  import type { Session } from "../../boot";
  import { Group, Row, Segmented } from "../controls";
  import { send } from "./ad-blocking";

  /**
   * BrowserAdBlockingLevelSection: Off, Balanced or Strict, each of which sets
   * the lists below to what it turns on. Once the person turns a list against
   * the level, the row says "Customized", and its reset restores the level's
   * lists. That word keeps its place while hidden, so the picker never moves.
   */
  let { session, lists, title }: { session: Session; lists: FilterLists; title?: string } = $props();

  const choose = (level: ContentBlockingLevel) => void send(session, SetContentBlockingLevel({ level }));
</script>

<Group {title} footer={lists.level.summary}>
  <Row title="Blocking" onReset={lists.isCustomized ? () => choose(lists.level) : null}>
    <span class="settings-customized" style:opacity={lists.isCustomized ? 1 : 0} aria-hidden="true">Customized</span>
    <Segmented label="Blocking" value={lists.level} onChange={choose}
      choices={ContentBlockingLevel.all.map((level) => ({ value: level, label: level.title }))} />
  </Row>
</Group>
