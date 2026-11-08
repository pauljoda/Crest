//! Crest's content filter: Brave's adblock engine behind the C interface that
//! `include/crest_content_filter.h` declares and the native core links.
//!
//! Every export catches panics and answers `FAILED` instead, so a list the
//! engine cannot digest fails one call rather than ending the browser. Texts
//! the caller passes are borrowed for the call; buffers the library returns
//! are released with `crest_content_filter_buffer_free`.

use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::{Arc, RwLock};

use adblock::Engine;
use adblock::content_blocking::{CbRule, CbType};
use adblock::filters::network::NetworkFilterMaskHelper;
use adblock::lists::{FilterSet, ParseOptions, ParsedLine, parse_filter};
use adblock::request::Request;
use adblock::resources::{PermissionMask, Resource};
use serde::{Deserialize, Serialize};

// MARK: - Interface

/// Bumped with every change to the header's functions or records.
pub const ABI_VERSION: u32 = 3;

pub const OK: i32 = 0;
pub const INVALID_ARGUMENT: i32 = 1;
pub const UNREADABLE: i32 = 2;
pub const FAILED: i32 = 3;

pub const ALLOW: u8 = 0;
pub const BLOCK: u8 = 1;
/// Blocked, with a replacement resource to serve in its place.
pub const REDIRECT: u8 = 2;

/// UTF-8 bytes borrowed for one call.
#[repr(C)]
pub struct Text {
    bytes: *const u8,
    length: usize,
}

/// Bytes the library allocated, released with `crest_content_filter_buffer_free`.
#[repr(C)]
pub struct Buffer {
    bytes: *mut u8,
    length: usize,
}

/// One network request a page makes.
#[repr(C)]
pub struct RequestInfo {
    url: Text,
    /// The document that makes the request: the frame's URL, or the URL itself
    /// for a top-level navigation.
    source_url: Text,
    kind: u8,
    method: u8,
}

/// What a request check decided: `ALLOW` or `BLOCK`.
#[repr(C)]
pub struct Decision {
    verdict: u8,
}

// MARK: - Filters

/// A compiled set of filter lists. Handed out as an `Arc`, so a slot can keep
/// one alive while its creator lets go.
pub struct Filter(Engine);

/// Where the core installs the filter in force, for an engine to check
/// requests against from any thread.
pub struct Slot(RwLock<Option<Arc<Filter>>>);

const _: fn() = || {
    fn shared<T: Send + Sync>() {}
    shared::<Filter>();
    shared::<Slot>();
};

/// The permission uBlock's trusted scriptlets require, which only the first
/// lists a build names, the ones Crest itself chooses, parse with. Lists the
/// person added and their own filters parse with none, so they can run only
/// the scriptlets that need no permission.
const TRUSTED: PermissionMask = PermissionMask::from_bits(1);

impl Filter {
    /// Compiles `lists`, the first `trusted` of them with the permission
    /// trusted scriptlets require. With `resources`, scriptlets and redirects
    /// can use them, so a filter that blocks to serve a replacement stays in;
    /// without, it is left out and the request is allowed.
    fn build(lists: &[String], trusted: usize, resources: Option<Vec<Resource>>) -> Filter {
        let mut set = FilterSet::new(false);
        for (index, list) in lists.iter().enumerate() {
            let options = ParseOptions {
                permissions: if index < trusted { TRUSTED } else { PermissionMask::default() },
                ..ParseOptions::default()
            };
            match resources {
                Some(_) => set.add_filter_list(list.clone(), options),
                None => set.add_filter_list(admitted(list), options),
            };
        }
        let mut engine = Engine::new_with_filter_set(set);
        if let Some(resources) = resources {
            engine.use_resources(resources);
        }
        Filter(engine)
    }

    fn check(&self, request: &RequestInfo) -> Result<Decision, i32> {
        Ok(self.check_with_redirect(request)?.0)
    }

    /// The decision for `request`, and the data URL of the resource to serve
    /// in its place when the filter redirects it.
    fn check_with_redirect(&self, request: &RequestInfo) -> Result<(Decision, Option<String>), i32> {
        let url = text(&request.url)?;
        let source = text(&request.source_url)?;
        let kind = request_kind(request.kind).ok_or(INVALID_ARGUMENT)?;
        let method = request_method(request.method).ok_or(INVALID_ARGUMENT)?;
        // A URL the engine cannot parse matches no filter.
        let Ok(request) = Request::new(url, source, kind, method) else {
            return Ok((Decision { verdict: ALLOW }, None));
        };
        let result = self.0.check_network_request(&request);
        if !result.should_block() {
            return Ok((Decision { verdict: ALLOW }, None));
        }
        Ok(match result.redirect {
            Some(redirect) => (Decision { verdict: REDIRECT }, Some(redirect)),
            None => (Decision { verdict: BLOCK }, None),
        })
    }

    fn page_resources(&self, url: &str) -> Result<Vec<u8>, i32> {
        serde_json::to_vec(&self.0.url_cosmetic_resources(url)).map_err(|_| FAILED)
    }

    fn hidden_selectors(&self, query: &SelectorQuery) -> Result<Vec<u8>, i32> {
        let exceptions = query.exceptions.iter().cloned().collect();
        let selectors = self
            .0
            .hidden_class_id_selectors(&query.classes, &query.ids, &exceptions);
        serde_json::to_vec(&selectors).map_err(|_| FAILED)
    }
}

/// The classes and ids a page shows, and the exceptions its page resources
/// named, as `crest_content_filter_hidden_selectors` reads them.
#[derive(Deserialize)]
struct SelectorQuery {
    classes: Vec<String>,
    ids: Vec<String>,
    exceptions: Vec<String>,
}

/// Lists converted to WebKit content rules: the rules that block or hide, and
/// the `ignore-previous-rules` exceptions that must follow every one of them
/// in the same compiled list.
#[derive(Serialize)]
struct ContentRules {
    rules: Vec<CbRule>,
    exceptions: Vec<CbRule>,
}

impl ContentRules {
    fn convert(lists: &[String]) -> Result<ContentRules, i32> {
        let mut set = FilterSet::new(true);
        for list in lists {
            set.add_filter_list(admitted(list), ParseOptions::default());
        }
        let (converted, _) = set.into_content_blocking().map_err(|_| FAILED)?;
        let (exceptions, rules) = converted
            .into_iter()
            .partition(|rule| matches!(rule.action.typ, CbType::IgnorePreviousRules));
        Ok(ContentRules { rules, exceptions })
    }
}

/// A list without the filters that block in order to serve a replacement
/// resource. No resources are loaded, and such a filter must then allow the
/// request rather than leave the page without what it expects.
fn admitted(list: &str) -> String {
    let mut kept = String::with_capacity(list.len());
    for line in list.lines().filter(|line| !blocks_for_redirect(line)) {
        kept.push_str(line);
        kept.push('\n');
    }
    kept
}

fn blocks_for_redirect(line: &str) -> bool {
    if !line.contains("redirect=") {
        return false;
    }
    matches!(parse_filter(line, false, ParseOptions::default()),
             Ok(ParsedLine::Network(filter)) if filter.is_redirect() && filter.also_block_redirect() && !filter.is_exception())
}

fn request_kind(kind: u8) -> Option<&'static str> {
    Some(match kind {
        0 => "other",
        1 => "document",
        2 => "sub_frame",
        3 => "script",
        4 => "stylesheet",
        5 => "image",
        6 => "font",
        7 => "media",
        8 => "xmlhttprequest",
        9 => "websocket",
        10 => "ping",
        11 => "object",
        12 => "csp_report",
        _ => return None,
    })
}

fn request_method(method: u8) -> Option<&'static str> {
    Some(match method {
        0 => "",
        1 => "get",
        2 => "head",
        3 => "post",
        4 => "put",
        5 => "delete",
        6 => "connect",
        7 => "options",
        8 => "patch",
        9 => "other",
        _ => return None,
    })
}

// MARK: - Boundary

fn guarded(body: impl FnOnce() -> i32) -> i32 {
    catch_unwind(AssertUnwindSafe(body)).unwrap_or(FAILED)
}

fn bytes(text: &Text) -> Result<&[u8], i32> {
    if text.length == 0 {
        return Ok(&[]);
    }
    if text.bytes.is_null() {
        return Err(INVALID_ARGUMENT);
    }
    // SAFETY: the caller lends `length` readable bytes for the call.
    Ok(unsafe { std::slice::from_raw_parts(text.bytes, text.length) })
}

fn text(text: &Text) -> Result<&str, i32> {
    std::str::from_utf8(bytes(text)?).map_err(|_| INVALID_ARGUMENT)
}

/// Each list's text; a list that is not valid UTF-8 keeps what it can.
fn lists(lists: *const Text, count: usize) -> Result<Vec<String>, i32> {
    if count == 0 {
        return Ok(Vec::new());
    }
    if lists.is_null() {
        return Err(INVALID_ARGUMENT);
    }
    // SAFETY: the caller lends `count` texts for the call.
    let lists = unsafe { std::slice::from_raw_parts(lists, count) };
    lists
        .iter()
        .map(|list| Ok(String::from_utf8_lossy(bytes(list)?).into_owned()))
        .collect()
}

fn hand_over(bytes: Vec<u8>, out: *mut Buffer) {
    let boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    // SAFETY: the caller checked `out`; `buffer_free` rebuilds the box.
    unsafe {
        *out = Buffer {
            bytes: Box::into_raw(boxed).cast(),
            length,
        };
    }
}

fn filter<'a>(filter: *const Filter) -> Result<&'a Filter, i32> {
    // SAFETY: a non-null filter came from `build` or `load` and is still retained.
    unsafe { filter.as_ref() }.ok_or(INVALID_ARGUMENT)
}

fn slot<'a>(slot: *const Slot) -> Result<&'a Slot, i32> {
    // SAFETY: a non-null slot came from `slot_create` and is not destroyed.
    unsafe { slot.as_ref() }.ok_or(INVALID_ARGUMENT)
}

fn answer(result: Result<(), i32>) -> i32 {
    result.err().unwrap_or(OK)
}

// MARK: - Exports

#[unsafe(no_mangle)]
pub extern "C" fn crest_content_filter_abi_version() -> u32 {
    ABI_VERSION
}

/// Compiles `count` filter lists into one filter, retained once for the caller.
///
/// # Safety
/// `lists` holds `count` readable texts; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_build(lists: *const Text, count: usize, out: *mut *const Filter) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let built = Filter::build(&self::lists(lists, count)?, 0, None);
            // SAFETY: checked above.
            unsafe { *out = Arc::into_raw(Arc::new(built)) };
            Ok(())
        })())
    })
}

/// The resources in `text`, a JSON array in adblock-rust's resource format,
/// or none for an empty text.
fn resources(text: &Text) -> Result<Option<Vec<Resource>>, i32> {
    let json = self::text(text)?;
    if json.trim().is_empty() {
        return Ok(None);
    }
    serde_json::from_str(json).map(Some).map_err(|_| INVALID_ARGUMENT)
}

/// `crest_content_filter_build` with the resources scriptlets and redirects
/// use, as JSON in adblock-rust's resource format; an empty text loads none.
/// The first `trusted` lists may run the scriptlets that need permission.
///
/// # Safety
/// `lists` holds `count` readable texts; `resources` is lent for the call;
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_build_with_resources(
    lists: *const Text,
    count: usize,
    trusted: usize,
    resources: Text,
    out: *mut *const Filter,
) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let built = Filter::build(&self::lists(lists, count)?, trusted, self::resources(&resources)?);
            // SAFETY: checked above.
            unsafe { *out = Arc::into_raw(Arc::new(built)) };
            Ok(())
        })())
    })
}

/// `crest_content_filter_load` with the resources the saved filter's
/// scriptlets and redirects use, which a saved filter does not keep.
///
/// # Safety
/// `bytes` holds `length` readable bytes; `resources` is lent for the call;
/// `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_load_with_resources(
    bytes: *const u8,
    length: usize,
    resources: Text,
    out: *mut *const Filter,
) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let lent = Text { bytes, length };
            let data = self::bytes(&lent)?;
            let mut engine = Engine::default();
            engine.deserialize(data).map_err(|_| UNREADABLE)?;
            if let Some(resources) = self::resources(&resources)? {
                engine.use_resources(resources);
            }
            // SAFETY: checked above.
            unsafe { *out = Arc::into_raw(Arc::new(Filter(engine))) };
            Ok(())
        })())
    })
}

/// Loads a filter `crest_content_filter_save` wrote with this same library.
/// The file's checksum is checked, but a file another version or program wrote
/// must never be passed: same-version data is trusted without verification.
///
/// # Safety
/// `bytes` holds `length` readable bytes; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_load(bytes: *const u8, length: usize, out: *mut *const Filter) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let lent = Text { bytes, length };
            let data = self::bytes(&lent)?;
            let mut engine = Engine::default();
            engine.deserialize(data).map_err(|_| UNREADABLE)?;
            // SAFETY: checked above.
            unsafe { *out = Arc::into_raw(Arc::new(Filter(engine))) };
            Ok(())
        })())
    })
}

/// The filter in the form `crest_content_filter_load` reads back.
///
/// # Safety
/// `filter` is retained; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_save(filter: *const Filter, out: *mut Buffer) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            hand_over(self::filter(filter)?.0.serialize(), out);
            Ok(())
        })())
    })
}

/// Lets go of one retention of `filter`; the last one frees it.
///
/// # Safety
/// `filter` is null or retained by the caller, who no longer uses it.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_release(filter: *const Filter) {
    if !filter.is_null() {
        // SAFETY: the caller hands back one retention it owns.
        guarded(|| {
            drop(unsafe { Arc::from_raw(filter) });
            OK
        });
    }
}

/// Whether `filter` blocks `request`.
///
/// # Safety
/// `filter` is retained; `request` and `out` are valid for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_check(
    filter: *const Filter,
    request: *const RequestInfo,
    out: *mut Decision,
) -> i32 {
    guarded(|| {
        answer((|| {
            // SAFETY: the caller lends `request` for the call.
            let request = unsafe { request.as_ref() }.ok_or(INVALID_ARGUMENT)?;
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let decision = self::filter(filter)?.check(request)?;
            // SAFETY: checked above.
            unsafe { *out = decision };
            Ok(())
        })())
    })
}

/// What a page at `url` hides and runs, as JSON: `hide_selectors`,
/// `procedural_actions`, `exceptions`, `injected_script` and `generichide`.
///
/// # Safety
/// `filter` is retained; `url` is lent for the call; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_page_resources(
    filter: *const Filter,
    url: Text,
    out: *mut Buffer,
) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            hand_over(self::filter(filter)?.page_resources(text(&url)?)?, out);
            Ok(())
        })())
    })
}

/// The generic hide selectors for the classes and ids a page shows, as a JSON
/// array; `query` is JSON with `classes`, `ids` and `exceptions` arrays.
///
/// # Safety
/// `filter` is retained; `query` is lent for the call; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_hidden_selectors(
    filter: *const Filter,
    query: Text,
    out: *mut Buffer,
) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let query: SelectorQuery = serde_json::from_slice(bytes(&query)?).map_err(|_| INVALID_ARGUMENT)?;
            hand_over(self::filter(filter)?.hidden_selectors(&query)?, out);
            Ok(())
        })())
    })
}

/// `count` filter lists as WebKit content rules: JSON with `rules`, the
/// rules that block or hide, and `exceptions`, which must follow the rules in
/// every compiled list they are split into.
///
/// # Safety
/// `lists` holds `count` readable texts; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_content_rules(lists: *const Text, count: usize, out: *mut Buffer) -> i32 {
    guarded(|| {
        answer((|| {
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let rules = ContentRules::convert(&self::lists(lists, count)?)?;
            hand_over(serde_json::to_vec(&rules).map_err(|_| FAILED)?, out);
            Ok(())
        })())
    })
}

/// Frees a buffer the library returned, and empties it.
///
/// # Safety
/// `buffer` is null or holds what the library returned, freed once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_buffer_free(buffer: *mut Buffer) {
    // SAFETY: the caller hands back a buffer the library allocated.
    let Some(buffer) = (unsafe { buffer.as_mut() }) else {
        return;
    };
    if !buffer.bytes.is_null() {
        let slice = std::ptr::slice_from_raw_parts_mut(buffer.bytes, buffer.length);
        guarded(|| {
            // SAFETY: `hand_over` made this box from exactly these parts.
            drop(unsafe { Box::from_raw(slice) });
            OK
        });
    }
    *buffer = Buffer {
        bytes: std::ptr::null_mut(),
        length: 0,
    };
}

/// A slot that holds no filter: every request it checks is allowed.
#[unsafe(no_mangle)]
pub extern "C" fn crest_content_filter_slot_create() -> *mut Slot {
    Box::into_raw(Box::new(Slot(RwLock::new(None))))
}

/// Puts `filter` in force in `slot`, retaining it, or empties the slot for a
/// null filter. Checks already under way finish with the filter they began with.
///
/// # Safety
/// `slot` is live; `filter` is null or retained by the caller.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_slot_install(slot: *const Slot, filter: *const Filter) -> i32 {
    guarded(|| {
        answer((|| {
            let slot = self::slot(slot)?;
            let installed = if filter.is_null() {
                None
            } else {
                // SAFETY: the caller's retention keeps `filter` alive while the slot adds its own.
                unsafe {
                    Arc::increment_strong_count(filter);
                    Some(Arc::from_raw(filter))
                }
            };
            let previous = std::mem::replace(&mut *slot.0.write().map_err(|_| FAILED)?, installed);
            drop(previous);
            Ok(())
        })())
    })
}

/// Whether the filter in force in `slot` blocks `request`; an empty slot allows it.
///
/// # Safety
/// `slot` is live; `request` and `out` are valid for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_slot_check(
    slot: *const Slot,
    request: *const RequestInfo,
    out: *mut Decision,
) -> i32 {
    guarded(|| {
        answer((|| {
            let current = self::slot(slot)?.0.read().map_err(|_| FAILED)?.clone();
            // SAFETY: the caller lends `request` for the call.
            let request = unsafe { request.as_ref() }.ok_or(INVALID_ARGUMENT)?;
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let decision = match current {
                Some(filter) => filter.check(request)?,
                None => Decision { verdict: ALLOW },
            };
            // SAFETY: checked above.
            unsafe { *out = decision };
            Ok(())
        })())
    })
}

/// `crest_content_filter_slot_check` that also answers the resource to serve
/// in place of a request the filter redirects: `out` says `REDIRECT`, and
/// `redirect` receives the resource as a data URL, which the caller releases
/// with `crest_content_filter_buffer_free`. Otherwise `redirect` is left empty.
///
/// # Safety
/// `slot` is live; `request`, `out` and `redirect` are valid for the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_slot_check_redirect(
    slot: *const Slot,
    request: *const RequestInfo,
    out: *mut Decision,
    redirect: *mut Buffer,
) -> i32 {
    guarded(|| {
        answer((|| {
            let current = self::slot(slot)?.0.read().map_err(|_| FAILED)?.clone();
            // SAFETY: the caller lends `request` for the call.
            let request = unsafe { request.as_ref() }.ok_or(INVALID_ARGUMENT)?;
            if out.is_null() || redirect.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let (decision, replacement) = match current {
                Some(filter) => filter.check_with_redirect(request)?,
                None => (Decision { verdict: ALLOW }, None),
            };
            // SAFETY: checked above.
            unsafe {
                *out = decision;
                *redirect = Buffer { bytes: std::ptr::null_mut(), length: 0 };
            }
            if let Some(replacement) = replacement {
                hand_over(replacement.into_bytes(), redirect);
            }
            Ok(())
        })())
    })
}

/// `crest_content_filter_page_resources` for the filter in force in `slot`;
/// an empty slot hides and runs nothing.
///
/// # Safety
/// `slot` is live; `url` is lent for the call; `out` is writable.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_slot_page_resources(
    slot: *const Slot,
    url: Text,
    out: *mut Buffer,
) -> i32 {
    guarded(|| {
        answer((|| {
            let current = self::slot(slot)?.0.read().map_err(|_| FAILED)?.clone();
            if out.is_null() {
                return Err(INVALID_ARGUMENT);
            }
            let resources = match current {
                Some(filter) => filter.page_resources(text(&url)?)?,
                None => serde_json::to_vec(&adblock::cosmetic_filter_cache::UrlSpecificResources::empty())
                    .map_err(|_| FAILED)?,
            };
            hand_over(resources, out);
            Ok(())
        })())
    })
}

/// Destroys `slot`, letting go of the filter it holds.
///
/// # Safety
/// `slot` is null or live, and nothing uses it afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crest_content_filter_slot_destroy(slot: *mut Slot) {
    if !slot.is_null() {
        // SAFETY: the caller hands back the slot `slot_create` made.
        guarded(|| {
            drop(unsafe { Box::from_raw(slot) });
            OK
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(url: &'static str, source: &'static str, kind: u8) -> RequestInfo {
        RequestInfo {
            url: Text {
                bytes: url.as_ptr(),
                length: url.len(),
            },
            source_url: Text {
                bytes: source.as_ptr(),
                length: source.len(),
            },
            kind,
            method: 1,
        }
    }

    #[test]
    fn redirect_filters_allow_without_resources() {
        let filter = Filter::build(&["||ads.example^$script,redirect=noopjs\n||track.example^".to_owned()], 1, None);
        let page = "https://news.example/";
        assert_eq!(
            filter
                .check(&request("https://ads.example/a.js", page, 3))
                .unwrap()
                .verdict,
            ALLOW
        );
        assert_eq!(
            filter
                .check(&request("https://track.example/p.gif", page, 5))
                .unwrap()
                .verdict,
            BLOCK
        );
    }

    #[test]
    fn resources_serve_redirects_and_scriptlets() {
        let resources: Vec<Resource> = serde_json::from_str(
            r#"[{"name":"noop.js","aliases":["noopjs"],"kind":{"mime":"application/javascript"},"content":"KGZ1bmN0aW9uKCl7fSkoKTs="},
                {"name":"set-constant.js","aliases":["set.js"],"kind":{"mime":"application/javascript"},
                 "content":"ZnVuY3Rpb24gc2V0Q29uc3RhbnQoYSwgYikgeyB3aW5kb3dbYV0gPSBiOyB9"}]"#,
        )
        .unwrap();
        let filter = Filter::build(
            &["||ads.example^$script,redirect=noopjs\nnews.example##+js(set, adsOff, true)".to_owned()],
            1,
            Some(resources),
        );
        let page = "https://news.example/";
        let (decision, redirect) = filter
            .check_with_redirect(&request("https://ads.example/a.js", page, 3))
            .unwrap();
        assert_eq!(decision.verdict, REDIRECT);
        assert!(redirect.unwrap().starts_with("data:application/javascript;base64,"));
        let resources = filter.0.url_cosmetic_resources(page);
        assert!(resources.injected_script.contains("setConstant("));
        assert!(resources.injected_script.contains("adsOff"));
    }

    #[test]
    fn only_trusted_lists_run_scriptlets_that_need_permission() {
        let resources: Vec<Resource> = serde_json::from_str(
            r#"[{"name":"trusted-set-constant.js","aliases":["trusted-set.js"],"kind":{"mime":"application/javascript"},
                 "content":"ZnVuY3Rpb24gdHJ1c3RlZFNldChhLCBiKSB7IHdpbmRvd1thXSA9IGI7IH0=","permission":1}]"#,
        )
        .unwrap();
        let lists = [
            "chosen.example##+js(trusted-set, fromChosen, 1)".to_owned(),
            "added.example##+js(trusted-set, fromAdded, 1)".to_owned(),
        ];
        let filter = Filter::build(&lists, 1, Some(resources.clone()));
        assert!(filter.0.url_cosmetic_resources("https://chosen.example/").injected_script.contains("fromChosen"));
        assert!(!filter.0.url_cosmetic_resources("https://added.example/").injected_script.contains("fromAdded"));
        // A saved filter keeps each list's permission.
        let mut engine = Engine::default();
        engine.deserialize(&filter.0.serialize()).unwrap();
        engine.use_resources(resources);
        assert!(engine.url_cosmetic_resources("https://chosen.example/").injected_script.contains("fromChosen"));
        assert!(!engine.url_cosmetic_resources("https://added.example/").injected_script.contains("fromAdded"));
    }

    #[test]
    fn saved_filters_load_with_the_same_decisions() {
        let filter = Filter::build(&["||track.example^\n@@||track.example/ok^".to_owned()], 1, None);
        let saved = filter.0.serialize();
        let mut engine = Engine::default();
        engine.deserialize(&saved).unwrap();
        let loaded = Filter(engine);
        let page = "https://news.example/";
        assert_eq!(
            loaded
                .check(&request("https://track.example/p.gif", page, 5))
                .unwrap()
                .verdict,
            BLOCK
        );
        assert_eq!(
            loaded
                .check(&request("https://track.example/ok/p.gif", page, 5))
                .unwrap()
                .verdict,
            ALLOW
        );
    }

    #[test]
    fn content_rules_keep_exceptions_apart() {
        let rules = ContentRules::convert(&["||track.example^\n@@||track.example/ok^".to_owned()]).unwrap();
        assert!(!rules.rules.is_empty());
        assert!(
            rules
                .exceptions
                .iter()
                .all(|rule| matches!(rule.action.typ, CbType::IgnorePreviousRules))
        );
        assert!(
            rules
                .rules
                .iter()
                .all(|rule| !matches!(rule.action.typ, CbType::IgnorePreviousRules))
        );
    }
}
