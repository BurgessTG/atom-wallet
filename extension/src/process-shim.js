// Node's process for the browser bundles. esbuild injects this module
// wherever a bundled file uses the free identifier process: the assert and
// util polyfills that the SDK's address codec dependency (@subsquid/scale-codec)
// needs read process.env.
import process from 'process/browser.js';

export { process };
