// esbuild plugins shared by the extension build and the browser check.
import { existsSync, copyFileSync, mkdirSync, readFileSync } from 'node:fs';
import path from 'node:path';

// ------------------------------------------------------------ wasm ESM ---
// `import * as wasm from './x_bg.wasm'` becomes a module that loads the file
// from /wasm/ in the extension and re-exports the instance's exports by name.
// The module's own imports (the wasm-bindgen glue and its snippets) are read
// from the binary at build time and bundled as ordinary modules, so each
// package exists exactly once per bundle: a second instance of a ledger would
// make its objects fail every `instanceof` check of the first.
//
// In workers the module is instantiated synchronously (synchronous XHR and
// WebAssembly.Module are allowed there at any size). Top-level await would
// let the worker's event loop run before its message listener is installed,
// and the SDK's proof workers are posted their job right after construction,
// so a message could arrive with nobody listening. Pages use top-level await.
const isIdentifier = name => /^[A-Za-z_$][\w$]*$/.test(name);
export function wasmPlugin({ sync, out }) {
  return {
    name: 'wasm-esm',
    setup(b) {
      b.onResolve({ filter: /\.wasm$/ }, args => {
        if (args.namespace === 'wasm-esm') return null;
        return { path: path.resolve(args.resolveDir, args.path), namespace: 'wasm-esm' };
      });
      b.onLoad({ filter: /.*/, namespace: 'wasm-esm' }, args => {
        const bytes = readFileSync(args.path);
        const module = new WebAssembly.Module(bytes);
        // zkir-v2 and zkir-v3 both name their binary midnight_zkir_wasm_bg.wasm.
        const name = `${path.basename(path.dirname(args.path))}_${path.basename(args.path)}`;
        const target = path.join(out, 'wasm', name);
        mkdirSync(path.dirname(target), { recursive: true });
        if (!existsSync(target)) copyFileSync(args.path, target);
        const importModules = [...new Set(WebAssembly.Module.imports(module).map(i => i.module))];
        const exportNames = WebAssembly.Module.exports(module).map(e => e.name);
        const bad = exportNames.filter(n => !isIdentifier(n));
        if (bad.length) throw new Error(`${name} exports names that are not identifiers: ${bad.join(', ')}`);
        const lines = importModules.map((m, i) => `import * as i${i} from ${JSON.stringify(m)};`);
        lines.push(`const imports = { ${importModules.map((m, i) => `${JSON.stringify(m)}: i${i}`).join(', ')} };`);
        lines.push(`const url = new URL(${JSON.stringify(`/wasm/${name}`)}, import.meta.url).href;`);
        if (sync) {
          lines.push(
            'const request = new XMLHttpRequest();',
            'request.open(\'GET\', url, false);',
            'request.responseType = \'arraybuffer\';',
            'request.send();',
            `if (!(request.response instanceof ArrayBuffer) || !request.response.byteLength) throw new Error(${JSON.stringify(`Cannot load ${name}`)});`,
            'const instance = new WebAssembly.Instance(new WebAssembly.Module(request.response), imports);',
          );
        } else {
          lines.push('const { instance } = await WebAssembly.instantiateStreaming(fetch(url), imports);');
        }
        lines.push('const e = instance.exports;');
        for (const n of exportNames) lines.push(`export const ${n} = e.${n};`);
        return { contents: lines.join('\n'), resolveDir: path.dirname(args.path), loader: 'js' };
      });
    },
  };
}

// Node-only and test-only modules that must never reach a bundle. The SDK's
// indexer and utilities packages ship test helpers that pull in testcontainers.
export function forbidPlugin() {
  const forbidden = /^(testcontainers|tar-stream|dockerode|ssh2)(\/|$)/;
  return {
    name: 'forbid',
    setup(b) {
      b.onResolve({ filter: forbidden }, args => ({ errors: [{ text: `${args.path} must not be bundled (imported by ${args.importer})` }] }));
    },
  };
}
