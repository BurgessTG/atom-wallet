// Wallet persistence in IndexedDB (extension origin). Offscreen documents and
// their workers only get chrome.runtime, so everything durable lives here,
// not in chrome.storage.
//
// One database per network (mdwa-<network>), so each network has its own
// wallet. Its one object store, `meta`, holds:
//   wallet:   { network, sealed, addresses, createdAt } (sealed: vault.js)
//   snapshot: the SDK wallets' serialized state, the transaction history and
//             the lifecycle records, encrypted with the seed's record key
//   txmeta:   what the wallet knows about transactions it made itself (kind,
//             dApp origin), encrypted the same way; kept across a rescan
//   tokenLabels: the user's names for custom tokens (tokens.js), in the
//             clear so they read the same locked or unlocked
// Settings shared by all networks live in mdwa-settings.
const SETTINGS_DB = 'mdwa-settings';
const opened = new Map();

function openDb(name) {
  if (!opened.has(name)) {
    opened.set(name, new Promise((resolve, reject) => {
      const request = indexedDB.open(name, 1);
      request.onupgradeneeded = () => request.result.createObjectStore('meta');
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    }));
  }
  return opened.get(name);
}

const done = request => new Promise((resolve, reject) => {
  request.onsuccess = () => resolve(request.result);
  request.onerror = () => reject(request.error);
});
const committed = t => new Promise((resolve, reject) => { t.oncomplete = resolve; t.onerror = () => reject(t.error); });

function metaStore(name) {
  const store = async (mode = 'readonly') => (await openDb(name)).transaction('meta', mode).objectStore('meta');
  return {
    get: async key => done((await store()).get(key)),
    put: async (key, value) => done((await store('readwrite')).put(value, key)),
    delete: async key => done((await store('readwrite')).delete(key)),
    async clear() {
      const t = (await openDb(name)).transaction('meta', 'readwrite');
      t.objectStore('meta').clear();
      return committed(t);
    },
  };
}

/** The store of one network. */
export function forNetwork(network) {
  return { network, ...metaStore(`mdwa-${network}`) };
}

// ------------------------------------------------------------- settings ---
const settingsStore = metaStore(SETTINGS_DB);

export async function getSettings() {
  return (await settingsStore.get('settings')) ?? {};
}

export async function putSettings(settings) {
  return settingsStore.put('settings', settings);
}
