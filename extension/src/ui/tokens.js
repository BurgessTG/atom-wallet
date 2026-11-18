// How a token is shown, everywhere it appears: Home, Send, Activity, the
// Token page and the approval window. NIGHT and DUST
// keep their fixed names and decimals; a custom token shows the label the
// user saved for it (engine: tokenLabels), or "Token" with its raw quantity.
//
// Labels are per network and per (type, kind); the engine's state push does
// not carry them, so every hook instance re-reads them when the network
// changes or when a page here saves or removes one (refreshTokenLabels).
import { useEffect, useState } from 'react';
import { ui } from './api.js';
import { DUST_DECIMALS, NIGHT_DECIMALS, isNight, parseUnits, shortType } from './format.js';

const listeners = new Set();

/** Tells every mounted useTokenLabels to read the labels again. */
export function refreshTokenLabels() {
  for (const l of listeners) l();
}

/**
 * The selected network's labels, keyed `${kind}:${type}`; null until they
 * arrive (describeToken then shows tokens unnamed for a moment rather than
 * blocking the page). `network` re-reads them when it changes.
 */
export function useTokenLabels(network) {
  const [labels, setLabels] = useState(null);
  useEffect(() => {
    let live = true;
    const load = () => ui('tokenLabels').then(list => {
      if (live) setLabels(new Map((list ?? []).map(l => [`${l.kind}:${l.type}`, l])));
    }, () => {});
    load();
    listeners.add(load);
    return () => { live = false; listeners.delete(load); };
  }, [network]);
  return labels;
}

/**
 * What to call a token: `{ name, symbol, decimals, labelled, source,
 * contract }`. `symbol` is null for an unlabelled custom token (its unit is
 * "units" and its amounts are raw quantities). `kind` is 'shielded',
 * 'unshielded' or 'dust'.
 */
export function describeToken(labels, type, kind) {
  if (kind === 'dust') return { name: 'Dust', symbol: 'DUST', decimals: DUST_DECIMALS, labelled: false, source: 'network', contract: null, fixed: true };
  if (isNight(kind, type)) return { name: 'Night', symbol: 'NIGHT', decimals: NIGHT_DECIMALS, labelled: false, source: 'network', contract: null, fixed: true };
  const l = labels?.get(`${kind}:${type}`);
  if (!l) return { name: 'Token', symbol: null, decimals: 0, labelled: false, source: null, contract: null, fixed: false };
  return { name: l.name, symbol: l.symbol, decimals: l.decimals, labelled: true, source: l.source, contract: l.contract ?? null, fixed: false };
}

const group = digits => digits.replace(/\B(?=(\d{3})+(?!\d))/g, ',');

/**
 * A smallest-unit amount with `decimals` places, grouped; the fraction keeps
 * every digit for NIGHT (its fixed look) and drops trailing zeros otherwise,
 * so a labelled token reads "1,500" or "1,500.25". BigInt throughout.
 */
export function formatUnits(value, decimals, { trim = true } = {}) {
  const n = BigInt(value ?? 0);
  const abs = n < 0n ? -n : n;
  const scale = 10n ** BigInt(decimals);
  const whole = group((abs / scale).toString());
  let frac = decimals ? (abs % scale).toString().padStart(decimals, '0') : '';
  if (trim) frac = frac.replace(/0+$/, '');
  return `${n < 0n ? '-' : ''}${whole}${frac ? `.${frac}` : ''}`;
}

/** An amount of a described token as text: NIGHT with all 6 decimals, others trimmed. */
export const tokenAmount = (desc, value) => formatUnits(value, desc.decimals, { trim: desc.symbol !== 'NIGHT' });

/** The unit after an amount: the symbol, or "units" for an unlabelled token. */
export const tokenUnit = desc => desc.symbol ?? 'units';

/** The amount a user typed, in the smallest unit of a described token; throws a readable error. */
export function parseTokenAmount(desc, text) {
  if (desc.decimals === 0) {
    if (!/^\s*\d+\s*$/.test(text ?? '')) throw new Error(desc.symbol ? `${desc.symbol} has no decimals: enter a whole number` : 'Enter a whole number of units');
    return BigInt(text.trim()).toString();
  }
  return parseUnits(text, desc.decimals, desc.symbol ?? 'Amounts');
}

/** Two letters for the avatar: from the symbol when there is one, else from the type. */
export const tokenLetters = (desc, type) => (desc.symbol
  ? [...desc.symbol.replace(/[^\p{L}\p{N}]/gu, '') || desc.symbol].slice(0, 2).join('').toUpperCase()
  : (type ?? '').slice(0, 2).toUpperCase() || '?');

/** The name with the short type when there is no label: "Token 3f9a7c1d…5e8f". */
export const tokenTitle = (desc, type) => (desc.labelled || desc.fixed ? desc.name : `Token ${shortType(type)}`);

/** A contract address cut to its start and end. */
export const shortContract = address => (address && address.length > 16 ? `${address.slice(0, 8)}…${address.slice(-6)}` : address);
