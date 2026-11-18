#!/usr/bin/env node
// Builds the test dApp (dapp/app.js with Midnight.js 5, bundled by esbuild
// like the extension) into build/dapp and serves it on localhost only:
//
//   npm run dapp            -> http://localhost:5190
//   node dapp/serve.mjs --port 5191
//   node dapp/serve.mjs --build-only
//
// The contract's compiled artifacts (dapp/contract/managed, see
// compile.mjs) are served under /managed, the layout Midnight.js's
// FetchZkConfigProvider reads: /managed/keys/<circuit>.prover,
// /managed/zkir/<circuit>.bzkir and /managed/compiler/contract-manifest.json.
// The dApp's own packages live in dapp/node_modules (npm install --prefix
// dapp), apart from the extension's, so its ledger copy never meets the
// wallet's.
import { build } from 'esbuild';
import { createServer } from 'node:http';
import { createReadStream, copyFileSync, existsSync, mkdirSync, rmSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { wasmPlugin } from '../scripts/esbuild-plugins.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.dirname(here);
const out = path.join(root, 'build/dapp');
const managed = path.join(here, 'contract/managed');
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, arg, i, all) => {
  if (arg.startsWith('--')) acc.push([arg.slice(2), all[i + 1]?.startsWith('--') ? 'true' : (all[i + 1] ?? 'true')]); return acc;
}, []));
const port = Number(args.port ?? 5190);

if (!existsSync(path.join(here, 'node_modules/@midnight-ntwrk/midnight-js-contracts'))) {
  throw new Error('Install the test dApp\'s packages first: npm install --prefix dapp');
}
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
await build({
  entryPoints: { app: path.join(here, 'app.js') },
  outdir: out,
  bundle: true,
  splitting: true,
  format: 'esm',
  platform: 'browser',
  target: 'es2022',
  sourcemap: 'linked',
  logLevel: 'warning',
  define: { 'process.env.NODE_ENV': '"production"', global: 'globalThis' },
  // Midnight.js and its GraphQL client use Node's Buffer and process.
  inject: [path.join(root, 'extension/src/buffer-shim.js'), path.join(root, 'extension/src/process-shim.js')],
  plugins: [wasmPlugin({ sync: false, out })],
});
copyFileSync(path.join(here, 'index.html'), path.join(out, 'index.html'));
console.log(`Test dApp built: ${path.relative(root, out)}`);
if (args['build-only']) process.exit(0);

const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.map': 'application/json', '.json': 'application/json', '.wasm': 'application/wasm' };
createServer((request, response) => {
  const url = new URL(request.url, 'http://localhost');
  const [base, rest] = url.pathname.startsWith('/managed/') ? [managed, url.pathname.slice('/managed/'.length)] : [out, url.pathname.slice(1) || 'index.html'];
  const file = path.resolve(base, decodeURIComponent(rest));
  if (!file.startsWith(base + path.sep) || !existsSync(file) || !statSync(file).isFile()) {
    response.writeHead(404, { 'content-type': 'text/plain' }).end('Not found');
    return;
  }
  response.writeHead(200, { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-store' });
  createReadStream(file).pipe(response);
}).listen(port, '127.0.0.1', () => console.log(`Test dApp: http://localhost:${port}`));
