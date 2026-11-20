import { SetDefaultSearch } from "@crest/contracts";
import { useId } from "react";

import type { Session } from "../../boot";
import { ProviderIcon } from "../../palette/CommandPalette";
import { LevelSection } from "../../settings/AdBlockingPane";
import { Group, Row } from "../../settings/controls";
import { Symbol } from "../../symbols";
import { useCoreVersion } from "../../use-core";

/**
 * BrowserSetupHomePage: what makes Crest home, each choice taking effect at
 * once, as in Settings: the search engine and the level ad blocking blocks
 * at. The Mac's Default browser row waits for Windows to register Crest as a
 * browser, which only an installer does.
 */
export function HomePage({ session }: { session: Session }) {
  useCoreVersion(session);
  const searchId = useId();
  const catalog = session.core.state.search;
  const lists = session.core.state.filterLists;
  const choices = catalog?.providers.filter((provider) => provider.kind.canBeDefault) ?? [];
  return (
    <div className="setup-page-content">
      <h2 className="setup-page-heading">Make It Home</h2>
      {catalog && (
        <Group title="Search">
          <Row title="Search with" htmlFor={searchId}>
            <span className="setup-search-choice" data-testid="setup-default-search">
              <ProviderIcon provider={catalog.default} size={20} />
              <span className="settings-select">
                <select id={searchId} value={catalog.default.name}
                  onChange={(event) => {
                    const provider = choices.find((each) => each.name === event.target.value);
                    if (provider) void session.core.send(SetDefaultSearch({ provider })).catch(() => undefined);
                  }}>
                  {choices.map((provider) => <option key={provider.name} value={provider.name}>{provider.title}</option>)}
                </select>
                <Symbol name="chevron.up.chevron.down" size={11} className="settings-select-glyph" />
              </span>
            </span>
          </Row>
        </Group>
      )}
      {lists && <LevelSection session={session} lists={lists} title="Ad Blocking" />}
    </div>
  );
}
