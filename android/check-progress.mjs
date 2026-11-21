import assert from 'node:assert/strict';
import { Effect, Stream } from 'effect';
import * as progress from './worker/progress.js';
import { observedSubmission } from './worker/submission.js';

const packets = [];
globalThis.self = { postMessage: packet => packets.push(structuredClone(packet)) };
const tx = {
  transactionHash: () => 'a'.repeat(64),
  identifiers: () => ['coin-id'],
  serialize: () => new Uint8Array([19, 3, 7]),
};

function submission(events) {
  let broadcasts = 0;
  const node = {
    sendMidnightTransaction(bytes) {
      assert.deepEqual(bytes, tx.serialize());
      broadcasts++;
      return Stream.fromIterable(events);
    },
  };
  return { service:observedSubmission(Effect.succeed(node)), broadcasts:() => broadcasts };
}

function event(tag, height) {
  return height == null ? { _tag:tag } : { _tag:tag, blockHeight:BigInt(height) };
}

await progress.run('previewSend', {}, 'one', async () => {
  progress.stage('Balancing');
  return { id:'recipe' };
});
const chain = submission([
  event('Submitted'), event('InBlock', 202300), event('Submitted'), event('InBlock', 202301), event('Finalized', 202301),
]);
await progress.run('send', { id:'recipe' }, 'two', async () => {
  progress.stage('Signing');
  progress.stage('Proving');
  const done = progress.proof('midnight/zswap/10/output');
  done(false);
  progress.bind(tx);
  progress.stage('Submitting');
  const final = await chain.service.submitTransaction(tx, 'Finalized');
  assert.equal(final._tag, 'Finalized');
  return { txId:'coin-id' };
});
assert.equal(chain.broadcasts(), 1);
const record = progress.recorded(['coin-id']);
assert.equal(record.status, 'finalized');
assert.equal(record.block, 202301);
assert.equal(record.hash, tx.transactionHash());
assert.deepEqual(record.steps.map(step => step.name), [
  'Preparing', 'Balancing', 'Awaiting approval', 'Approved', 'Signing', 'Proving',
  'Submitting', 'Submitted', 'In block', 'Returned to pool', 'Submitted', 'In block', 'Finalized',
]);
assert.equal(record.steps.find(step => step.name === 'Proving').proofs[0].name, 'output');
assert.ok(record.steps.every(step => step.end >= step.start));
assert.ok(packets.every(packet => packet.type === 'transaction' && Number.isFinite(packet.at)));
await chain.service.close();

const interrupted = submission([event('Submitted')]);
await assert.rejects(interrupted.service.submitTransaction(tx, 'Finalized'), /Transaction submission error/);
assert.equal(interrupted.broadcasts(), 1);
await interrupted.service.close();

await progress.run('dustPreview', { action:'register' }, 'three', async () => ({ id:'dust-recipe' }));
await progress.run('cancel', { id:'dust-recipe' }, 'four', async () => ({}));
await progress.run('lock', {}, 'five', async () => ({}));
assert.equal(progress.recorded(['coin-id']), undefined);
console.log('Single submission, SDK finality, block retraction, timestamps, proof events, failure and cancellation passed.');
