import qrcode from 'qrcode-generator';

// The Activity transfers a private MessagePort to this top-level page. The
// worker is the same bundle used by the extension, with its own sealed vault.
window.addEventListener('message', ({ ports }) => {
  const port = ports[0];
  if (!port) return;
  const worker = new Worker('/android-engine.js', { type: 'module' });
  const reply = value => port.postMessage(JSON.stringify(value, (_, v) => typeof v === 'bigint' ? v.toString() : v));
  const prover = ports[1];
  let pending;
  if (prover) prover.onmessage = ({ data }) => {
    if (!pending) return;
    const result = JSON.parse(data);
    if (result.error) pending.postMessage({ error: result.error });
    else {
      const proof = Uint8Array.from(atob(result.proof), c => c.charCodeAt(0));
      pending.postMessage({ proof }, [proof.buffer]);
    }
    pending.close();
    pending = undefined;
  };
  worker.onmessage = ({ data, ports: replies }) => {
    if (!data.nativeProof) return reply(data);
    const channel = replies[0];
    if (!prover || pending) {
      channel.postMessage({ error: 'Native Vulkan prover unavailable or busy' });
      channel.close();
      return;
    }
    pending = channel;
    const bytes = data.nativeProof;
    prover.postMessage('begin ' + bytes.length);
    // Keep IPC messages bounded and stay below the JS argument limit on older WebViews.
    const chunkSize = bytes.toBase64 ? 128 * 1024 : 32 * 1024;
    for (let start = 0; start < bytes.length; start += chunkSize) {
      const chunk = bytes.subarray(start, start + chunkSize);
      prover.postMessage(chunk.toBase64 ? chunk.toBase64() : btoa(String.fromCharCode(...chunk)));
    }
    prover.postMessage('end');
  };
  worker.onerror = () => reply({ type: 'fatal', message: 'Wallet engine could not start. Update Android System WebView and reopen Atom Wallet.' });
  port.onmessage = ({ data }) => {
    const { id, method, params } = JSON.parse(data);
    if (method === 'qr') {
      try {
        const code = qrcode(0, 'M');
        code.addData(params.address);
        code.make();
        const rows = Array.from({ length: code.getModuleCount() }, (_, y) =>
          Array.from({ length: code.getModuleCount() }, (_, x) => code.isDark(y, x) ? '1' : '0').join(''));
        reply({ id, result: { rows } });
      } catch (error) { reply({ id, error: { message: error.message } }); }
    } else {
      worker.postMessage({ id, kind: 'ui', method, params });
    }
  };
  port.start();
}, { once: true });
