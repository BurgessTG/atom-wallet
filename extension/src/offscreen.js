// The offscreen document only hosts the engine worker and relays: requests
// from the background (over its Port, see background.js) -> worker, and the
// worker's state -> every extension view. Offscreen documents get
// chrome.runtime and nothing else, which is all this needs.
const worker = new Worker(new URL('engine-worker.js', import.meta.url), { type: 'module' });
let next = 0;
const waiting = new Map();
let failed = null, started = false;

worker.onmessage = ({ data }) => {
  started = true;
  if (data.type === 'state') {
    chrome.runtime.sendMessage({ type: 'state', state: data.state }).catch(() => {});
    return;
  }
  const done = waiting.get(data.id);
  if (done) { waiting.delete(data.id); done(data); }
};

// A worker that fails to load (a bundle or WASM error) never answers; say so
// instead of leaving every request pending. Errors after it has started are
// the engine's own and are answered per request.
worker.onerror = event => {
  if (started) return;
  const message = `The wallet engine failed to start: ${event.message || 'unknown error'}`;
  for (const [id, done] of waiting) { waiting.delete(id); done({ id, error: { message, code: null, locked: false } }); }
  failed = message;
};

// Only the background connects here, under this name. The greeting tells it
// that this document is listening; answers carry the background's own id.
// Other Ports (a page's connector Port to the background) reach this
// listener too, since a runtime Port goes to every extension page that
// listens: they are left alone, because disconnecting one here would close
// it for the background as well.
chrome.runtime.onConnect.addListener(port => {
  if (port.name !== 'mdwa-engine' || port.sender?.id !== chrome.runtime.id || port.sender?.tab) return;
  let open = true;
  port.onDisconnect.addListener(() => { open = false; });
  const answer = body => { if (open) { try { port.postMessage(body); } catch { /* the background went away */ } } };
  port.onMessage.addListener(({ id: request, kind, method, params }) => {
    if (failed) { answer({ id: request, error: { message: failed, code: null, locked: false } }); return; }
    const id = ++next;
    waiting.set(id, ({ result, error }) => answer({ id: request, ...(error ? { error } : { result }) }));
    worker.postMessage({ id, kind, method, params });
  });
  port.postMessage({ ready: true });
});
