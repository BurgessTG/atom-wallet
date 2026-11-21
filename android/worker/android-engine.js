import { proofRequest } from './proof-request.mjs';

async function nativeProof(...args) {
  const bytes = await proofRequest(...args);
  const channel = new MessageChannel();
  return new Promise((resolve, reject) => {
    channel.port1.onmessage = ({ data }) => {
      channel.port1.close();
      if (data.error) reject(Error(data.error));
      else resolve(data.proof);
    };
    self.postMessage({ nativeProof: bytes }, [bytes.buffer, channel.port2]);
  });
}
globalThis.mdwaNativeProof = async (...args) => {
  const done = globalThis.mdwaProgress?.proof(args[3]);
  try { const result = await nativeProof(...args); done?.(false); return result; }
  catch (error) { done?.(true); throw error; }
};
await import('/engine-worker.js');
