# Link opening

General settings contains one focus preference, **Focus new tabs opened from links**.
Its stored key and default remain unchanged. Existing users keep their saved choice;
payloads without the key use `false`.

| WebKit intent | Focus off | Focus on | Loading owner |
| --- | --- | --- | --- |
| Command-click or middle-click link | Background tab | Selected tab | Crest starts the original request immediately |
| Same gesture with Shift | Selected tab | Background tab | Crest starts the original request immediately |
| Accepted scripted new window with the same modifier/button intent | Background tab | Selected tab | WebKit drives its supplied view immediately |
| Direct link or scripted same-page navigation | Current page | Current page | WebKit |
| Unmodified `target=_blank`, form target, or accepted `window.open` | Selected tab | Selected tab | WebKit |
| Explicit window, download, Peek, Quick Window, or Space destination action | Existing action semantics | Existing action semantics | Existing action owner |

The Command/Option preference for Peek still determines which modifier means
"new tab". Shift reverses the focus choice only for a reported new-tab gesture.
The same shared decision applies on macOS and iPadOS. A script that does not
preserve a link or new-window gesture cannot be classified from the appearance
of its card. Crest does not rewrite sites or infer missing input intent.

Popup permissions remain WebKit's decision. Selection policy is evaluated only
after WebKit accepts the new-window request. Crest adopts the supplied configuration
and leaves its first navigation to WebKit, preserving opener identity, writable
blank windows, request bodies, and the source profile.

## Loading and residency

Intentionally opened background links start immediately. Their initial navigation
is protected from Crest's idle eviction until it finishes or fails; normal page
residency applies afterward. Selecting the new tab reuses that page.

Entering a Space is a separate action. An existing unloaded tab remains unloaded
on mere Space entry, and the Mac shows Start Page until explicit tab selection.
Resident and in-flight pages retain their existing behavior.

There is no deferred-loading preference. Public WebKit requires an accepted native
window's view to be returned synchronously, and its opener may immediately write
to or message it. Cancelling that navigation and replaying a URL later would lose
those semantics and can discard request data. A switch that delays ordinary anchors
but still runs scripted windows would give the two paths different loading behavior.
Supporting a broader deferred mode would require a separate, explicit capability
contract before exposing that choice.

## Public API references

- [WKNavigationAction](https://developer.apple.com/documentation/webkit/wknavigationaction)
- [Creating a new WebKit view](https://developer.apple.com/documentation/webkit/wkuidelegate/webview(_:createwebviewwith:for:windowfeatures:))
- [Safari tab settings](https://support.apple.com/guide/safari/tabs-ibrw1045/mac)

Delegate tests cover supplied navigation intent. Site-specific event handling
and physical keyboard or pointer behavior also need validation in the running
browser.
