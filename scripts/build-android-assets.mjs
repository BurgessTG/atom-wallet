// Gradle packages a Godot pack at the APK root and MDWA's worker under engine/.
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { build } from 'esbuild';

const root = fileURLToPath(new URL('../', import.meta.url));
const ui = path.join(root, 'android/ui');
const assets = path.join(root, 'android/app/build/generated/walletAssets');
const engine = path.join(assets, 'engine');
const extension = path.join(root, 'build/android-worker');
function run(bin, args) {
  const result = spawnSync(bin, args, { cwd: root, stdio: 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${bin} exited with ${result.status}`);
}

run(process.execPath, ['scripts/build-extension.mjs', '--android']);
rmSync(assets, { recursive: true, force: true });
mkdirSync(engine, { recursive: true });
mkdirSync(path.join(assets, 'licenses'));
cpSync(path.join(ui, 'Inter-LICENSE.txt'), path.join(assets, 'licenses/Inter.txt'));
for (const file of ['engine-worker.js', 'engine-worker.js.LEGAL.txt', 'LICENSE', 'wasm']) {
  cpSync(path.join(extension, file), path.join(engine, file), { recursive: true });
}
mkdirSync(path.join(engine, 'dist'));
for (const file of readdirSync(path.join(extension, 'dist')).filter(f => !f.endsWith('.map'))) {
  cpSync(path.join(extension, 'dist', file), path.join(engine, 'dist', file));
}
for (const file of ['android-engine.js', 'proof-request.mjs']) cpSync(path.join(root, 'android/worker', file), path.join(engine, file));
cpSync(path.join(root, 'android/worker/index.html'), path.join(engine, 'index.html'));
await build({ entryPoints: [path.join(root, 'android/worker/host.js')], bundle: true, format: 'esm',
  outfile: path.join(engine, 'host.js'), minify: true, legalComments: 'linked' });
run('godot', ['--headless', '--path', ui, '--import']);
run('godot', ['--headless', '--path', ui, '--export-pack', 'Wallet', path.join(assets, 'wallet.pck')]);
