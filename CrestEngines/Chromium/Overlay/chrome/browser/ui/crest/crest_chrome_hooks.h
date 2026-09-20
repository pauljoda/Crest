#ifndef CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_
#define CHROME_BROWSER_UI_CREST_CREST_CHROME_HOOKS_H_

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#endif

class Browser;
namespace content { class WebContents; }

namespace crest {
// Enabled only by the explicitly selected Crest host command-line switch.
bool IsEnabled();
void OnBrowserWindowCreated(Browser* browser);
void OnBrowserWindowDestroyed(Browser* browser);
void EnsureCrestUIStarted(Browser* browser);
// Chrome's AppController retains its lifecycle role. A quit waits for core saves.
bool DeferQuit();
// Consumes the result of a native close preflight without destroying the page.
bool CompletePageClosePreparation(content::WebContents* contents, bool proceed);
#ifdef __OBJC__
NSWindow* WindowForBrowser(Browser* browser);
#endif
}  // namespace crest

#endif
