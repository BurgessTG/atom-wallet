// Worker for scripts/browser-check.mjs: starts both of the SDK's proof
// workers directly, then proves a one-output shielded transaction with the
// SDK's WASM proving service (key material from srs.midnight.network).
import * as ledger from '@midnightntwrk/ledger-v9';
import { Cause, Runtime } from 'effect';
import { makeV9WasmProvingService } from '@midnightntwrk/wallet-sdk/capabilities/proving';

const construct = url => new Promise(resolve => {
  const worker = new Worker(new URL(url, import.meta.url), { type: 'module' });
  const timer = setTimeout(() => { worker.terminate(); resolve({ url, ok: true }); }, 3000);
  worker.onerror = event => { clearTimeout(timer); worker.terminate(); resolve({ url, ok: false, error: event.message || 'error' }); };
});

self.onmessage = async () => {
  const started = Date.now();
  try {
    const workers = await Promise.all(['/dist/proof-worker.js', '/dist/proof-worker-zkir-v3.js'].map(construct));
    const token = ledger.shieldedToken().raw;
    const coin = ledger.createShieldedCoinInfo(token, 1000n);
    const output = ledger.ZswapOutput.new(coin, 0, ledger.sampleCoinPublicKey(), ledger.sampleEncryptionPublicKey());
    const tx = ledger.Transaction.fromParts('preview', ledger.ZswapOffer.fromOutput(output, token, 1000n));
    const proven = await makeV9WasmProvingService().prove(tx);
    self.postMessage({ ok: true, workers, seconds: (Date.now() - started) / 1000, proven: proven.toString(true).slice(0, 160), bytes: proven.serialize().length });
  } catch (error) {
    const causes = [];
    if (Runtime.isFiberFailure(error)) {
      const cause = error[Runtime.FiberFailureCauseId];
      for (const f of [...Cause.failures(cause), ...Cause.defects(cause)]) {
        for (let e = f; e && causes.length < 8; e = e.cause) causes.push(`${e?._tag ?? e?.name ?? ''}: ${e?.message ?? String(e)}`);
      }
    }
    if (!causes.length) for (let e = error; e && causes.length < 6; e = e.cause) causes.push(`${e?.name ?? ''} ${e?._tag ?? ''} ${e?.message ?? e}`);
    self.postMessage({ ok: false, error: causes.join(' <- '), seconds: (Date.now() - started) / 1000 });
  }
};
