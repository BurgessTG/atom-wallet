// Node's Buffer for the browser bundles. esbuild injects this module wherever
// a bundled file uses the free identifier Buffer (the SDK's address codecs and
// the polkadot node client do); code that looks it up on globalThis finds it
// there too.
import { Buffer } from 'buffer';

globalThis.Buffer ??= Buffer;
export { Buffer };
