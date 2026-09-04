# Chrome side-panel acceptance probe

Install this folder only in an isolated test profile, with the operator's approval. It reads tab metadata and stores its own diagnostic log. It has no content scripts, host permissions or native-messaging host. The offscreen permission is used only for the included coexistence document. Create test tab and the example link navigate to example.com.

Open Extension Settings for controls that remain available when the panel is hidden. The status includes native tab/window IDs, document identity, options, views, worker-observed sender metadata, and the event log.

1. Enable action opening, close the panel, then click the pinned action. Expect a trailing panel, an opened event and no action-clicked event. The popup must not appear. Disable action opening and verify that the action instead opens the popup.
2. Create two test tabs. Keep one on default options and use the tab dropdown to configure the other with Use tab-specific document. Switch between them. Expect panel.html and tab.html respectively, with distinct document identities.
3. Disable the configured tab's panel. Switching to that tab must remove the card; returning to the default tab must restore it without another open call. Re-enable the configured tab from the controls while another tab is active.
4. With a default-only panel, Try tab-only close must reject. Close global panel must close it. Open from extension page must work on a real click.
5. Try worker open after 6.5 seconds, do not interact with this extension during the delay, then refresh the log. Expect delayed-open-rejected with the user-gesture error. An unexpected success is a failure, not a fallback.
6. In the panel, panelAppearsAsTab must be false and worker.senderHasTab must be false. windows.getCurrent and the active tab must describe the owning Space. Views must include the panel document.
7. Create the offscreen document while the panel is open. Both document-ready events must arrive with senderHasTab false; the panel must remain usable. Close the offscreen document afterward.
8. Type into Panel focus test, switch ordinary tabs, and resize the divider. The page must not take keyboard focus from the panel. Follow the example link; it must open a normal tab instead of replacing the extension document.
9. Close using the card header, then reopen. Expect a new document identity, proving the old document was unloaded. Check opened/closed event counts and paths.
10. Enable action opening, quit and relaunch the isolated app. The panel must start closed, while getPanelBehavior still reports true. The background only sets behavior on installation, not on ordinary startup.

Do not count this probe as ChatGPT acceptance. The unchanged vendor extension must also pass its own startup and end-to-end workflow.
