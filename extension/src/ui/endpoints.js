// Reading and writing one network's endpoints in the engine's settings.
// `settings` returns an endpoints entry per network; both helpers also accept
// a single flat entry so the screens do not depend on which of the two the
// engine sends.

const isEntry = value => value && typeof value === 'object' && ('node' in value || 'indexerHttp' in value);

/** The entry for `network`, or an empty one while settings have not loaded. */
export const entryFor = (map, network) => (isEntry(map) ? map : map?.[network]) ?? {};

/** `map` with the entry for `network` replaced, in the same shape it came in. */
export const withEntry = (map, network, entry) => (isEntry(map) ? entry : { ...map, [network]: entry });
