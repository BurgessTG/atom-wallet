// Test page for scripts/browser-check.mjs (never part of the extension
// build): calls the engine as the popup does, and runs the prover check.
window.ui = async (method, params = {}) => {
  const reply = await chrome.runtime.sendMessage({ type: 'ui', method, params });
  if (reply?.error) throw Object.assign(new Error(reply.error.message), reply.error);
  return reply?.result;
};
window.states = [];
chrome.runtime.onMessage.addListener(message => { if (message?.type === 'state') window.states.push(message.state); });

// Proves a shielded output with the SDK's in-process WASM prover, from a
// worker at the extension root as the engine's is, so the SDK starts its
// proof worker from the same place.
window.prove = () => new Promise(resolve => {
  const worker = new Worker(new URL('check-worker.js', import.meta.url), { type: 'module' });
  worker.onmessage = ({ data }) => { worker.terminate(); resolve(data); };
  worker.onerror = event => { worker.terminate(); resolve({ ok: false, error: event.message || 'worker error' }); };
  worker.postMessage('prove');
});
