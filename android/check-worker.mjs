// Exercise the same web assets, MessagePort and SDK worker that the APK contains.
import assert from 'node:assert/strict';
import http from 'node:http';
import { Readable } from 'node:stream';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import puppeteer from 'puppeteer-core';
import { nativeProof } from './prover/run-check.mjs';

const assets = fileURLToPath(new URL('./app/build/generated/walletAssets/engine/', import.meta.url));
const server = http.createServer(async (req, res) => {
  const name = new URL(req.url, 'http://localhost').pathname.slice(1) || 'index.html';
  try {
    if (/^prover-material\/(bls_midnight_2p\d{1,2}|(zswap|dust)\/(9|10)\/(spend|output|sign)\.(prover|verifier|bzkir))$/.test(name)) {
      const upstream = await fetch(new URL(name.slice('prover-material/'.length), 'https://srs.midnight.network/'));
      res.writeHead(upstream.status, { 'Content-Type': 'application/octet-stream' });
      return Readable.fromWeb(upstream.body).pipe(res);
    }
    const data = await readFile(path.join(assets, name));
    res.setHeader('Content-Type', /\.m?js$/.test(name) ? 'application/javascript' : name.endsWith('.wasm') ? 'application/wasm' : 'text/html');
    res.end(data);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
let browser;
try {
  browser = await puppeteer.launch({ executablePath: process.env.CHROMIUM || '/usr/bin/chromium', headless: true });
  const page = await browser.newPage();
  page.setDefaultTimeout(90000);
  const testProof = process.argv.includes('--proof');
  if (testProof) {
    await page.exposeFunction('proveOnHost', async chunks => {
      const frame = Buffer.concat(chunks.map(chunk => Buffer.from(chunk, 'base64')));
      return (await nativeProof(frame)).toString('base64');
    });
  }
  async function connect() {
    await page.goto(`http://127.0.0.1:${server.address().port}/`);
    await page.evaluate(testProof => {
      const channel = new MessageChannel();
      const calls = new Map();
      let next = 0;
      channel.port1.onmessage = ({ data }) => {
        const message = JSON.parse(data);
        if (message.type === 'state') window.wallet = message.state;
        if (message.type === 'fatal') window.fatal = message.message;
        const resolve = calls.get(message.id);
        if (resolve) { calls.delete(message.id); resolve(message); }
      };
      window.ask = (method, params) => new Promise(resolve => {
        const id = String(++next);
        calls.set(id, resolve);
        channel.port1.postMessage(JSON.stringify({ id, method, params }));
      });
      const ports = [channel.port2];
      if (testProof) {
        const prover = new MessageChannel();
        let chunks;
        prover.port1.onmessage = async ({ data }) => {
          if (data.startsWith('begin ')) chunks = [];
          else if (data === 'end') {
            try {
              const proof = await window.proveOnHost(chunks);
              prover.port1.postMessage(JSON.stringify({ proof }));
            } catch (e) {
              prover.port1.postMessage(JSON.stringify({ error: e.message }));
            }
          } else chunks.push(data);
        };
        ports.push(prover.port2);
      }
      window.postMessage('connect', location.origin, ports);
    }, testProof);
    await page.waitForFunction(() => window.wallet || window.fatal);
    assert.equal(await page.evaluate(() => window.fatal), undefined);
  }
  await connect();
  if (testProof) {
    const { result, error } = await page.evaluate(() => window.ask('checkAndroidProver', {}));
    if (error) throw Error(error.message);
    assert.ok(result.seconds > 0);
    console.log('APK wallet worker generated and verified a proof through both private ports.');
  }
  const before = await page.evaluate(() => window.wallet);
  assert.equal(before.hasWallet, false);
  const live = process.argv.includes('--live');
  const created = await page.evaluate(async live => {
    const { result } = await window.ask('generateMnemonic', {});
    // A fresh live wallet starts at the chain tip. Offline restore needs no tip lookup.
    const wallet = await window.ask('createWallet', {
      mnemonic: result.words.join(' '), password: 'temporary-test-password', restore: !live
    });
    if (wallet.error) throw Error(wallet.error.message);
    const address = wallet.result.addresses.unshielded;
    const qr = await window.ask('qr', { address });
    const check = await window.ask('checkAddress', { address });
    return { address, valid: check.result.valid, modules: qr.result.rows.length };
  }, live);
  if (live) {
    await page.waitForFunction(() => window.wallet?.sync.status === 'synced', { timeout: 180000 });
    const read = await page.evaluate(async () => {
      const overview = await window.ask('overview', {});
      const history = await window.ask('history', {});
      return { night: overview.result.night.available, total: history.result.total };
    });
    assert.deepEqual(read, { night: '0', total: 0 });
    console.log('New Preview wallet synced and returned zero balances and empty history.');
  }
  assert.ok(created.valid && created.modules >= 21);
  await connect();
  assert.equal(await page.evaluate(() => window.wallet.locked), true);
  const unlock = await page.evaluate(async () => {
    const wrong = await window.ask('unlock', { password: 'incorrect-password' });
    const right = await window.ask('unlock', { password: 'temporary-test-password' });
    const locked = await window.ask('lock', {});
    return { wrong: !!wrong.error, right: right.result?.addresses.unshielded, locked: locked.result?.locked };
  });
  assert.deepEqual(unlock, { wrong: true, right: created.address, locked: true });
  console.log('Wallet worker passed create/restore, address validation, QR, reload, unlock and lock.');
} finally {
  await browser?.close();
  server.close();
}
