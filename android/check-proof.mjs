// Make and verify a Preview transaction entirely locally. Fetch public keys
// and SRS via the SDK's checksum-verified provider. Never submit a transaction.
import assert from 'node:assert/strict';
import { nativeProof } from './prover/run-check.mjs';
import { sampleOutput, verifyOutput } from '../wallet/sample-output.mjs';
import { WasmProver } from '@midnightntwrk/wallet-sdk/prover-client/effect';
import { proofRequest } from './worker/proof-request.mjs';

const v8 = process.argv.includes('--v8');
const ledger = await (v8 ? import('@midnightntwrk/ledger-v8') : import('@midnightntwrk/ledger-v9'));
const keys = v8 ? WasmProver.makeV8KeyMaterialProvider() : WasmProver.makeV9KeyMaterialProvider();
const runtime = ir => new TextDecoder().decode(ir.subarray(0, 31)).startsWith('midnight:ir-source[v3-generic]:')
  ? import('@midnightntwrk/zkir-v3') : import('@midnightntwrk/zkir-v2');
const unsigned = sampleOutput(ledger);
let originalProof;
const prove = async (...args) => {
  const request = await proofRequest(keys, runtime, ...args);
  originalProof = new Uint8Array(await nativeProof(request));
  return originalProof;
};
const provider = {
  prove, lookupKey: keys.lookupKey, check: async (preimage, location) => {
    const material = await keys.lookupKey(location);
    return (await runtime(material.ir)).check(preimage, keys);
  }
};
const cost = ledger.CostModel.initialCostModel();
const proven = await unsigned.prove(provider, cost);
verifyOutput(ledger, proven);
const bytes = Buffer.from(proven.serialize());
const tail = Buffer.from(originalProof.subarray(-64));
const start = bytes.indexOf(tail);
assert.ok(start >= 0 && start === bytes.lastIndexOf(tail));
bytes[start + tail.length - 1] ^= 1;
const altered = ledger.Transaction.deserialize('signature', 'proof', 'pre-binding', bytes);
assert.throws(() => verifyOutput(ledger, altered));
console.log(`Stock ledger-v${v8 ? 8 : 9} accepted the shielded-output proof and rejected a one-bit alteration.`);
