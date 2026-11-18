#!/usr/bin/env node
// Try the wallet in Helium: opens Helium with its own profile
// (.helium-profile/) and the unpacked extension from build/extension. Your
// normal Helium profile is not touched.
//
//   npm run helium [-- --helium /path/to/Helium]
//
// A second wallet (e.g. to send funds between two), in its own profile
// (.helium-profile-2/):
//
//   node scripts/helium.mjs --profile 2
import { existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const args = Object.fromEntries(process.argv.slice(2).reduce((acc, arg, i, all) => {
  if (arg.startsWith('--')) acc.push([arg.slice(2), all[i + 1] ?? 'true']); return acc;
}, []));
const helium = args.helium ?? '/Applications/Helium.app/Contents/MacOS/Helium';
const extension = path.join(root, 'build/extension');
if (!existsSync(path.join(extension, 'manifest.json'))) throw new Error('Build the extension first: npm run build:extension');
if (!existsSync(helium)) throw new Error(`Helium not found at ${helium} (pass --helium /path/to/Helium)`);

// Unpacked extensions get an ID derived from their absolute path.
const id = [...createHash('sha256').update(extension).digest('hex').slice(0, 32)]
  .map(c => String.fromCharCode(97 + parseInt(c, 16))).join('');

const profile = path.join(root, args.profile ? `.helium-profile-${args.profile}` : '.helium-profile');
spawn(helium, [
  `--user-data-dir=${profile}`, `--load-extension=${extension}`, '--no-first-run', '--no-default-browser-check',
  `chrome-extension://${id}/popup.html`,
], { detached: true, stdio: 'ignore' }).unref();
console.log(`Helium opened with profile ${path.relative(root, profile)}/ and extension ${id}`);
console.log('Pin "mdwa" from the puzzle-piece menu to open the popup from the toolbar.');
