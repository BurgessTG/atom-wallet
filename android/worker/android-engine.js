import { proofRequest } from './proof-request.mjs';

globalThis.mdwaNativeProof = async (...args) => {
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
};
await import('/engine-worker.js');
