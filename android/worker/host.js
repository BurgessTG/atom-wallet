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
    // Bound the size of each WebView IPC message on older Android releases.
    for (let start = 0; start < bytes.length; start += 32768) {
      prover.postMessage(btoa(String.fromCharCode(...bytes.subarray(start, start + 32768))));
    }
    prover.postMessage('end');
  };
  worker.onerror = () => reply({ type: 'fatal', message: 'Wallet engine could not start. Update Android System WebView and reopen MDWA.' });
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
