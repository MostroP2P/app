//! Origin-wide mutual exclusion for the web store, through the Web Locks
//! API (`navigator.locks`).
//!
//! An IndexedDB database is shared by every tab and worker of the origin, so
//! a mutex inside one Rust instance cannot stop a second tab from reading a
//! document, patching a different field and writing the whole document back
//! over ours. The browser's lock manager can: a named lock is exclusive
//! across the origin, granted in request order and released when its holder
//! lets go. Where the API is missing (an insecure context, an old browser)
//! the caller falls back to its in-process mutex, which is all that context
//! can offer.
use std::cell::RefCell;
use std::rc::Rc;

use wasm_bindgen_futures::JsFuture;
use web_sys::js_sys::{Array, Function, Promise, Reflect};
use web_sys::wasm_bindgen::closure::Closure;
use web_sys::wasm_bindgen::{JsCast, JsValue};

/// An exclusive origin-wide lock, released on drop.
pub struct OriginLock {
    release: Function,
}

impl Drop for OriginLock {
    fn drop(&mut self) {
        let _ = self.release.call0(&JsValue::NULL);
    }
}

/// `navigator.locks`, when this context has it.
fn lock_manager() -> Option<JsValue> {
    let global = web_sys::js_sys::global();
    let navigator = Reflect::get(&global, &JsValue::from_str("navigator")).ok()?;
    let locks = Reflect::get(&navigator, &JsValue::from_str("locks")).ok()?;
    (!locks.is_undefined() && !locks.is_null()).then_some(locks)
}

/// A promise whose settlement the caller controls.
fn external_promise() -> (Promise, Function) {
    let resolver: Rc<RefCell<Option<Function>>> = Rc::new(RefCell::new(None));
    let slot = resolver.clone();
    let promise = Promise::new(&mut |resolve, _reject| {
        *slot.borrow_mut() = Some(resolve);
    });
    let resolve = resolver
        .borrow_mut()
        .take()
        .expect("the Promise executor runs synchronously");
    (promise, resolve)
}

/// Acquires the exclusive lock `name` for this origin. `None` when the
/// context has no lock manager or refuses the request, in which case the
/// caller keeps only its in-process serialisation.
///
/// The guard exists before anything is awaited, so a caller dropped while
/// still waiting for the grant releases the lock the moment it is granted
/// instead of holding the name for the rest of the page's life. The wait
/// itself races the grant against the request's own promise: a request the
/// manager rejects (an inactive document, a security error, an abort)
/// settles that promise and ends the wait, since a rejection never reaches
/// the callback.
pub async fn acquire(name: &str) -> Option<OriginLock> {
    let locks = lock_manager()?;
    let request = Reflect::get(&locks, &JsValue::from_str("request"))
        .ok()?
        .dyn_into::<Function>()
        .ok()?;
    // `granted` settles when the manager hands us the lock; `held` is what
    // we return to the manager, and the lock lasts until it settles.
    let (granted, grant) = external_promise();
    let (held, release) = external_promise();
    let lock = OriginLock { release };
    let callback = Closure::once_into_js(move |_lock: JsValue| -> Promise {
        let _ = grant.call0(&JsValue::NULL);
        held
    });
    let requested = match request.call2(&locks, &JsValue::from_str(name), &callback) {
        Ok(promise) => Promise::resolve(&promise),
        Err(e) => {
            log::warn!("[db] navigator.locks.request({name}) refused: {e:?}");
            return None;
        }
    };
    let outcome = Promise::race(&Array::of2(&granted, &requested));
    match JsFuture::from(outcome).await {
        Ok(_) => Some(lock),
        Err(e) => {
            log::warn!("[db] navigator.locks.request({name}) rejected before grant: {e:?}");
            None
        }
    }
}
