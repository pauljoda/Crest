#ifndef CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_
#define CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
@class ASWebAuthenticationSessionRequest;
#endif

#include <string>

class Browser;
class GURL;
class Profile;
namespace content { class WebContents; class NavigationThrottleRegistry; struct DropData; struct OpenURLParams; }

namespace crest {
// The isolated world Crest's content bridges run in. It sits at the top of
// the embedder range, far from the worlds extensions allocate upward, and the
// patched evaluator awaits promises in this world only.
inline constexpr int kContentWorldID = (1 << 29) - 1;
// Enabled only by the explicitly selected Crest host command-line switch.
bool IsEnabled();
void OnBrowserWindowCreated(Browser* browser);
void OnBrowserWindowDestroyed(Browser* browser);
// A Browser the engine created for itself was shown. Crest opens the window it
// reserved for that Browser when the Browser's first tab is offered, so this
// only records whether `chrome.windows.create` asked for focus.
void OnEngineWindowShown(Browser* browser, bool focused);
// Whether a browsing window the engine wants to create for itself has a Crest
// Space to live in. A window Crest is creating for itself always does.
//
// Answered before the Browser exists, so a request no Space can host is
// refused at the one point Chromium already reports as an error:
// `chrome.windows.create` rejects instead of leaving its promise unsettled, and
// no unowned Browser is left running with tabs to decline.
bool CanCreateEngineBrowser(Profile* profile);
void EnsureCrestUIStarted(Browser* browser);
// Chrome's AppController retains its lifecycle role. A quit waits for core saves.
bool DeferQuit();
// A Dock click or reopen with no windows. Crest activates an existing window
// or opens its initial one; Chromium creates no browser of its own.
bool Reopen();
// Consumes the result of a native close preflight without destroying the page.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed);
// Called after Chromium has approved a renderer's drag request.
bool BeginLinkDrag(content::WebContents* contents, const content::DropData& data);
void AddNavigationThrottle(content::NavigationThrottleRegistry& registry);
// Chromium's toasts ("Link copied" and similar) anchor to a Views browser frame
// that this build never creates. Their message is shown as a Crest notice
// named by an SF Symbol instead.
void ShowEngineNotice(const std::u16string& message, const std::string& symbol);
// A selection the person asked to translate. Crest shows the system's
// translation panel rather than Chromium's partial-translate bubble.
void TranslateSelection(const std::u16string& text);
// A page's site state changed — the engine blocked a pop-up, for one. Crest
// relays what its own Site Controls show.
void UpdateSiteIndicators(content::WebContents* contents);
// The link under the pointer changed; an empty URL means it left the link.
void UpdateTargetURL(content::WebContents* contents, const GURL& url);
// Extension side panels are cards in Crest's own page row, so this build never
// creates Chrome's Views side-panel UI. `chrome.sidePanel.open()`, `close()`
// and an action click that toggles a panel are routed to the card that belongs
// to `contents`. Both return false when no Crest page owns `contents`, which
// leaves Chromium's own behavior in place.
bool OpenExtensionSidePanel(content::WebContents* contents, const std::string& extension_id);
bool CloseExtensionSidePanel(content::WebContents* contents, const std::string& extension_id);
// DevTools. Crest is a single-window browser, so a docked inspector belongs
// inside the page card it inspects rather than in a window of its own. This
// build never creates Chrome's Views contents container, so its
// `DevtoolsUIController` — which is what normally answers both of these — does
// not exist; these answer in its place for a WebContents a Crest page owns.
//
// `CanDockDevTools` decides whether the frontend may dock at all.
// `UpdateDockedDevTools` offers, relayouts or withdraws the docked frontend and
// returns true when a Crest page owns `inspected`. `OnDevToolsClosing` reports
// an inspector that is going away by any route — its own close button, an
// undocked window close, or the inspected page closing — so the core's
// developer-panel selection cannot go stale.
bool CanDockDevTools(content::WebContents* inspected);
bool UpdateDockedDevTools(content::WebContents* inspected);
void OnDevToolsClosing(content::WebContents* inspected);
// Applies semantic policy after Chromium validates a renderer's original request.
bool RouteModifiedLink(content::WebContents* source, content::OpenURLParams& params);
#ifdef __OBJC__
// Consumes an external open: a link from another app, a document, or the
// default-browser role. Crest applies its own routing policy.
bool OpenExternalURLs(NSArray<NSURL*>* urls);
// An app's system sign-in (`ASWebAuthenticationSession`). Crest runs it in a
// Quick Window of the Space the app's links route to, instead of Chromium's
// Views popup in a profile no Space owns. Both return false only when Crest is
// not hosting, which leaves Chromium's own handling in place.
bool BeginAuthenticationSession(ASWebAuthenticationSessionRequest* request);
bool CancelAuthenticationSession(ASWebAuthenticationSessionRequest* request);
NSWindow* WindowForBrowser(Browser* browser);
void AppendLinkMenuItem(NSMenu* menu, content::WebContents* contents, const GURL& url);
#endif
}  // namespace crest

#endif
