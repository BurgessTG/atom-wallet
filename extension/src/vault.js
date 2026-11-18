// Password encryption of the wallet seed with Web Crypto: PBKDF2-SHA-256
// (600k iterations) -> AES-256-GCM. The plaintext is the 64-byte BIP-39 seed;
// the mnemonic itself is never stored.
//
// Everything else the wallet keeps about itself (SDK snapshots, transaction
// history, notes on its own transactions) says which coins it owns, so it is
// encrypted too, with an AES-GCM key derived from the seed by HKDF: readable
// only while the wallet is unlocked, and no password check per save.
const ITERATIONS = 600000;
const enc = new TextEncoder();
const dec = new TextDecoder();
export const toHex = bytes => Array.from(bytes, b => b.toString(16).padStart(2, '0')).join('');
export const fromHex = hex => Uint8Array.from(hex.match(/../g) ?? [], b => parseInt(b, 16));

async function deriveKey(password, salt, iterations) {
  const material = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
    material, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

export async function seal(seedHex, password) {
  if (!password || password.length < 8) throw new Error('Use a password of at least 8 characters');
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(password, salt, ITERATIONS);
  const data = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, fromHex(seedHex)));
  return { kdf: 'PBKDF2-SHA256', iterations: ITERATIONS, salt: toHex(salt), iv: toHex(iv), data: toHex(data) };
}

export async function open(sealed, password) {
  const key = await deriveKey(password ?? '', fromHex(sealed.salt), sealed.iterations);
  try {
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromHex(sealed.iv) }, key, fromHex(sealed.data));
    return toHex(new Uint8Array(plain));
  } catch { throw new Error('Wrong password'); }
}

/** The key that encrypts a network's private records, derived from the seed.
 *  The network is part of the derivation, so records never move between
 *  networks even though they could share a seed. */
export async function recordKey(seedHex, network) {
  const material = await crypto.subtle.importKey('raw', fromHex(seedHex), 'HKDF', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt: enc.encode('mdwa records'), info: enc.encode(network) },
    material, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
}

/** Encrypt a JSON value with a record key. */
export async function encryptJson(key, value) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(JSON.stringify(value))));
  return { iv: toHex(iv), data };
}

/** Decrypt what encryptJson wrote; null when it was written with another key. */
export async function decryptJson(key, box) {
  if (!box) return null;
  try {
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: fromHex(box.iv) }, key, box.data);
    return JSON.parse(dec.decode(plain));
  } catch { return null; }
}
