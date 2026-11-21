import { Effect, Layer, ManagedRuntime, Stream } from 'effect';
import { NodeClient, PolkadotNodeClient } from '@midnightntwrk/wallet-sdk-node-client/effect';
import { SubmissionError } from '@midnightntwrk/wallet-sdk-capabilities/submission';
import { nodeEvent } from './progress.js';

// Observe the SDK's single submission stream before its usual wait-for-status filter.
export function liveSubmission(config) {
  return observedSubmission(PolkadotNodeClient.make({ nodeURL:config.relayURL }));
}

export function observedSubmission(nodeClient) {
  const client = nodeClient.pipe(Effect.map(node => ({
    sendMidnightTransaction: bytes => node.sendMidnightTransaction(bytes).pipe(
      Stream.tap(event => Effect.sync(() => nodeEvent(event)))),
  })));
  const runtime = ManagedRuntime.make(Layer.scoped(NodeClient.NodeClient, client));
  return {
    submitTransaction(tx, waitFor = 'InBlock') {
      const submit = NodeClient.sendMidnightTransactionAndWait(tx.serialize(), waitFor).pipe(
        Effect.mapError(cause => new SubmissionError({ message:'Transaction submission error', cause })));
      return runtime.runPromise(submit);
    },
    close: () => runtime.dispose(),
  };
}
