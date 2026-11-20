import qrcode from 'qrcode-generator';

// The Activity transfers a private MessagePort to this top-level page. The
// worker is the same bundle used by the extension, with its own sealed vault.
window.addEventListener('message', ({ ports }) => {
  const port = ports[0];
  if (!port) return;
  const worker = new Worker('/engine-worker.js', { type: 'module' });
  const reply = value => port.postMessage(JSON.stringify(value, (_, v) => typeof v === 'bigint' ? v.toString() : v));
  worker.onmessage = ({ data }) => reply(data);
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
