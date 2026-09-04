# Firefox sidebar acceptance probe

Install this folder only in an isolated test profile, with the operator's approval. It reads tab metadata and stores its own diagnostic log. It has no content scripts, host permissions or native-messaging host. Create test tab and the example link navigate to example.com.

Use Extension Settings or the action popup for controls when the sidebar is closed. The status includes the full panel URL, layered title, isOpen, document identity, native tabs/windows, views and worker-observed sender metadata.

1. A fresh installation should open the sidebar once. Its title must be the localized Firefox Sidebar Probe, never the raw __MSG_title__ token.
2. Toggle sidebar, Open sidebar and Close sidebar must agree with isOpen. The reserved command, Command-Shift-Y on macOS, must toggle the same sidebar.
3. Clear global panel must hide the card. Restore global panel must return the full extension URL from getPanel. Opening it again must load panel.html.
4. Configure a second tab with Use tab-specific document and switch tabs. Confirm document identity and getPanel resolution. Clear selected tab panel assigns null, which means no sidebar for that tab; it does not remove the override.
5. Set global, window and selected-tab titles. Confirm tab wins over window, which wins over global. Clear selected tab title must reveal the window title.
6. In the sidebar, panelAppearsAsTab and worker.senderHasTab must be false. The current window and active tab must be the owning Space. Follow the example link and verify it opens a normal tab.
7. Type into Panel focus test and resize the divider. Close with the card header and reopen; expect a new document identity.
8. Quit and relaunch the isolated app. The sidebar must remain closed. open_at_install must not reopen it on ordinary startup.

Repeat close, Space switch and permission-disable checks without losing access to the controls. Record real UI results separately from unit-test results.
