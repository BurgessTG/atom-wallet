// The Token page: name a custom token (name, symbol, decimals) and check it
// against the contract that mints it. Opened from a token row on Home, or
// from "Add a token" with no token yet, to register one before receiving it
// (the check then says which token type the contract and domain separator
// give, and the label applies once coins of that type arrive).
//
// The check proves which contract mints the type, not that the contract's
// name is honest, so a name read from a contract comes with a warning and a
// label saved after a check keeps the contract address, shown here.
import { useEffect, useMemo, useRef, useState } from 'react';
import { CheckCircleIcon, CheckIcon, CopyIcon, WarningCircleIcon } from '@phosphor-icons/react';
import { Badge } from '@cloudflare/kumo/components/badge';
import { Banner } from '@cloudflare/kumo/components/banner';
import { useKumoToastManager } from '@cloudflare/kumo/components/toast';
import {
  ActionFooter, DetailRow, ListCard, Notice, PageHeader, PrimaryButton, Screen, SecondaryButton, Section, TextField, TokenAvatar, Viewport, useCopy,
} from './components.jsx';
import { ui } from './api.js';
import { networkName, shortType } from './format.js';
import {
  describeToken, formatUnits, refreshTokenLabels, shortContract, tokenAmount, tokenLetters, tokenUnit, useTokenLabels,
} from './tokens.js';

const LIMITS = { name: 32, symbol: 8, decimals: 18 };
const capital = text => `${text[0].toUpperCase()}${text.slice(1)}`;
const chars = text => [...text].length;

/** The form's own checks; the engine also refuses reserved and duplicate names and says why. */
function formErrors({ name, symbol, decimals }) {
  const errors = {};
  const n = name.trim(), s = symbol.trim(), d = decimals.trim();
  if (chars(n) > LIMITS.name) errors.name = `At most ${LIMITS.name} characters`;
  if (chars(s) > LIMITS.symbol) errors.symbol = `At most ${LIMITS.symbol} characters`;
  if (d && (!/^\d+$/.test(d) || Number(d) > LIMITS.decimals)) errors.decimals = `A whole number from 0 to ${LIMITS.decimals}`;
  return { errors, complete: !!n && !!s && !Object.keys(errors).length };
}

/** The token as a row: avatar, name, kind and contract badges, balance. */
function TokenSummary({ type, kind, desc, balance }) {
  const [copied, copy] = useCopy();
  const unnamed = !desc.labelled;
  return (
    <ListCard>
      <div className="flex items-center gap-3 px-4 py-3">
        <TokenAvatar letters={tokenLetters(desc, type)} size={40} />
        <div className="flex min-w-0 flex-1 flex-col gap-0.5">
          <span className="flex min-w-0 items-center gap-1.5">
            <span className={`truncate text-[15px] font-semibold ${unnamed ? 'text-kumo-subtle' : 'text-kumo-default'}`}>{unnamed ? 'Unnamed token' : desc.name}</span>
            <Badge variant="secondary" className="shrink-0 text-[11px]">{capital(kind)}</Badge>
            {desc.source === 'contract' && <Badge variant="secondary" className="shrink-0 text-[11px]">contract</Badge>}
          </span>
          <span className="truncate font-mono text-[11px] text-kumo-subtle" title={desc.contract?.address}>
            {desc.contract ? `Contract ${shortContract(desc.contract.address)}` : shortType(type)}
          </span>
        </div>
        <div className="flex shrink-0 flex-col items-end gap-0.5">
          <span className="text-sm font-semibold text-kumo-default tabular-nums">{tokenAmount(desc, balance)}</span>
          <span className="text-[11px] text-kumo-subtle">{tokenUnit(desc)}</span>
        </div>
      </div>
      <div className="flex flex-col gap-1 px-4 py-[11px]">
        <span className="flex items-center justify-between text-[13px] text-kumo-subtle">
          Token type
          <button type="button" aria-label="Copy token type" title="Copy token type" onClick={() => copy(type)}
            className="-m-1 inline-flex items-center gap-1 rounded p-1 text-xs outline-none hover:text-kumo-default focus-visible:ring-2 focus-visible:ring-kumo-focus/50">
            {copied ? <><CheckIcon size={12} className="text-kumo-success" />Copied</> : <><CopyIcon size={12} />Copy</>}
          </button>
        </span>
        {/* Two even lines of 32 characters read better than a ragged wrap. */}
        <span className="font-mono text-[12px] leading-[1.5] text-kumo-default">
          <span className="block">{type.slice(0, 32)}</span>
          <span className="block">{type.slice(32)}</span>
        </span>
      </div>
    </ListCard>
  );
}

/** One line of the check's outcome. */
function Outcome({ tone, children }) {
  const good = tone === 'success';
  const Icon = good ? CheckCircleIcon : WarningCircleIcon;
  return (
    <p className={`flex items-start gap-1.5 px-1 text-xs leading-[1.45] ${good ? 'text-kumo-success' : tone === 'danger' ? 'text-kumo-danger' : 'text-kumo-subtle'}`}>
      <Icon size={14} weight={good ? 'fill' : 'regular'} className="mt-px shrink-0" />
      <span>{children}</span>
    </p>
  );
}

/** `target` is `{ token: { type, kind } }` from a row, or `{ addToken: kind }` from "Add a token". */
export function TokenPage({ state, overview, target, onBack }) {
  const toasts = useKumoToastManager();
  const labels = useTokenLabels(state.network);
  const kind = target.token?.kind ?? target.addToken;
  const adding = !target.token;
  const [check, setCheck] = useState({ address: '', domain: '', busy: false, result: null, error: null });
  // In add mode the token is whatever the check found.
  const type = target.token?.type ?? check.result?.type ?? null;
  const label = type ? labels?.get(`${kind}:${type}`) ?? null : null;
  const desc = describeToken(labels, type, kind);
  const [form, setForm] = useState({ name: '', symbol: '', decimals: '' });
  const [seeded, setSeeded] = useState(null);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  // The check's outcome sits below the fields; bring it into view when it lands.
  const outcome = useRef(null);
  useEffect(() => { if (check.result || check.error) outcome.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, [check.result, check.error]);

  // The form starts from the saved label once the labels have arrived.
  useEffect(() => {
    if (!type || !labels || seeded === type) return;
    if (label) setForm({ name: label.name, symbol: label.symbol, decimals: String(label.decimals) });
    setSeeded(type);
  }, [type, label, labels, seeded]);

  const balance = useMemo(() => {
    const list = (kind === 'shielded' ? overview?.shielded : overview?.unshielded) ?? [];
    return list.find(t => t.type === type)?.amount ?? check.result?.held?.find(h => h.kind === kind)?.amount ?? '0';
  }, [overview, kind, type, check.result]);

  const { errors, complete } = formErrors(form);
  const decimals = /^\d+$/.test(form.decimals.trim()) && Number(form.decimals) <= LIMITS.decimals ? Number(form.decimals) : 0;
  const preview = { ...desc, symbol: form.symbol.trim() || desc.symbol, decimals };

  // A check counts for saving only when it gave this very token.
  const r = check.result;
  const matches = r && (adding || r.type === type);
  const offered = matches && r.metadata && r.metadata.domainMatches !== false ? r.metadata : null;

  const runCheck = async () => {
    setCheck(c => ({ ...c, busy: true, result: null, error: null }));
    setError(null);
    try {
      const result = await ui('watchToken', { address: check.address, domainSeparator: check.domain });
      setCheck(c => ({ ...c, busy: false, result }));
      const fits = adding || result.type === target.token.type;
      if (fits && result.metadata && result.metadata.domainMatches !== false) {
        setForm({ name: result.metadata.name, symbol: result.metadata.symbol, decimals: String(result.metadata.decimals) });
        if (adding) setSeeded(result.type);
      }
    } catch (e) { setCheck(c => ({ ...c, busy: false, error: e.message })); }
  };

  const save = async () => {
    setBusy('save'); setError(null);
    try {
      await ui('setTokenLabel', {
        type, kind, name: form.name.trim(), symbol: form.symbol.trim(), decimals: form.decimals.trim() ? Number(form.decimals) : 0,
        ...(matches ? { contract: { address: r.address, domainSeparator: r.domainSeparator } } : {}),
      });
      refreshTokenLabels();
      toasts.add({ title: 'Saved', description: `${form.name.trim()} (${form.symbol.trim()})`, variant: 'success' });
      onBack();
    } catch (e) { setError(e.message); setBusy(null); }
  };
  const remove = async () => {
    setBusy('remove'); setError(null);
    try {
      await ui('removeTokenLabel', { type, kind });
      refreshTokenLabels();
      setForm({ name: '', symbol: '', decimals: '' });
      toasts.add({ title: 'Label removed', variant: 'success' });
    } catch (e) { setError(e.message); }
    setBusy(null);
  };
  const editCheck = patch => setCheck(c => ({ ...c, ...patch, result: null, error: null }));

  const held = r?.held ?? [];
  const heldText = held.length
    ? `This wallet holds ${held.map(h => `${formatUnits(h.amount, 0)} ${h.kind}`).join(' and ')} (raw quantity).`
    : r?.balancesKnown ? 'This wallet does not hold any of it yet.' : null;

  const contractSection = (
    <Section title="From its contract" gap="gap-3">
      <TextField label="Contract address" mono value={check.address} onChange={e => editCheck({ address: e.target.value })}
        placeholder="64 hex characters" spellCheck={false} autoComplete="off" />
      <TextField label="Domain separator" hint="Text or 64 hex characters" mono value={check.domain} onChange={e => editCheck({ domain: e.target.value })}
        placeholder="e.g. my:token" spellCheck={false} autoComplete="off"
        description="Leave it empty to use the one the contract stores, if it says." />
      <SecondaryButton className="w-full" loading={check.busy} disabled={check.busy || !check.address.trim()} onClick={runCheck}>Check</SecondaryButton>
      <div ref={outcome} className="flex flex-col gap-3 empty:hidden">
        {check.error && <Outcome tone="danger">{check.error}</Outcome>}
        {r && !matches && <Outcome tone="danger">This contract and domain separator do not produce this token</Outcome>}
        {matches && (
          <>
            <Outcome tone="success">{adding ? `This contract mints token ${shortType(r.type)}` : 'This contract mints this token'}</Outcome>
            {!r.contractFound && <Outcome>There is no contract at this address on {networkName(state)} yet.</Outcome>}
            {adding && heldText && <p className="px-1 text-xs text-kumo-subtle">{heldText}</p>}
            {r.metadata?.domainMatches === false && <Outcome>The contract's stored name is for another of its tokens, so it is not offered here.</Outcome>}
            {offered && <Notice>Names come from whoever deployed the contract. Check the contract address before trusting it.</Notice>}
          </>
        )}
      </div>
    </Section>
  );

  const labelSection = type && (
    <Section title="Label" gap="gap-3">
      <TextField label="Name" hint={`${chars(form.name.trim())}/${LIMITS.name}`} value={form.name} error={errors.name}
        onChange={e => setForm(f => ({ ...f, name: e.target.value }))} placeholder="e.g. Test Dollar" autoComplete="off" />
      <div className="grid grid-cols-[1fr_112px] gap-3">
        <TextField label="Symbol" hint={`${chars(form.symbol.trim())}/${LIMITS.symbol}`} value={form.symbol} error={errors.symbol}
          onChange={e => setForm(f => ({ ...f, symbol: e.target.value }))} placeholder="e.g. TUSD" autoComplete="off" />
        <TextField label="Decimals" value={form.decimals} error={errors.decimals} inputMode="numeric"
          onChange={e => setForm(f => ({ ...f, decimals: e.target.value }))} placeholder="0" autoComplete="off" />
      </div>
      <ListCard>
        <DetailRow label="Balance with these decimals" strong>{tokenAmount(preview, balance)} {tokenUnit(preview)}</DetailRow>
      </ListCard>
      {/* A refused save (a reserved or duplicate name) is about these fields: say so beside them. */}
      {error && <Banner size="sm" variant="error" description={error} />}
    </Section>
  );

  return (
    <Screen>
      <PageHeader title={adding ? 'Add a token' : 'Token'} onBack={onBack} />
      <Viewport>
        {adding && !type && <p className="px-1 text-xs leading-[1.45] text-kumo-subtle">Enter the contract that mints the token and its domain separator. The wallet works out the token type and keeps your name for it until it arrives.</p>}
        {type && <TokenSummary type={type} kind={kind} desc={desc} balance={balance} />}
        {adding ? <>{contractSection}{labelSection}</> : <>{labelSection}{contractSection}</>}
        {error && !type && <Banner size="sm" variant="error" description={error} />}
      </Viewport>
      <ActionFooter
        secondary={label ? <SecondaryButton disabled={!!busy} loading={busy === 'remove'} onClick={remove}>Remove label</SecondaryButton> : null}
        primary={<PrimaryButton loading={busy === 'save'} disabled={!!busy || !type || !complete} onClick={save}>Save</PrimaryButton>} />
    </Screen>
  );
}
