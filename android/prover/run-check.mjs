import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { fileURLToPath } from 'node:url';

export async function nativeProof(request) {
  const child = spawn(fileURLToPath(new URL('./target/release/proof-check', import.meta.url)), {
    stdio: ['pipe', 'pipe', 'inherit']
  });
  const chunks = [];
  child.stdout.on('data', data => chunks.push(data));
  const done = once(child, 'close');
  child.stdin.on('error', () => {}); // An early exit is reported below.
  child.stdin.end(request);
  const [code, signal] = await done;
  if (code !== 0) throw Error(`Vulkan prover exited with ${signal ?? code}`);
  return Buffer.concat(chunks);
}
