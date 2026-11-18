// Chromium keeps an unpacked extension's background service worker across
// browser restarts while the manifest version is unchanged, so after a
// rebuild the old background can keep running next to new pages and a new
// engine. Pages carry their build id; when the background runs another
// build (or predates this check and does not answer), reload the extension
// once for this build.
export async function ensureCurrentBuild() {
  let running = null;
  try { running = await chrome.runtime.sendMessage({ type: 'build' }); } catch { /* no answer */ }
  if (running === __BUILD_ID__) return true;
  const { reloadedForBuild } = await chrome.storage.local.get('reloadedForBuild');
  if (reloadedForBuild === __BUILD_ID__) return true;
  await chrome.storage.local.set({ reloadedForBuild: __BUILD_ID__ });
  chrome.runtime.reload();
  return false;
}
