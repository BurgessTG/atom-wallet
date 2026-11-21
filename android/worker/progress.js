// All timestamps are observed in this worker. The UI only interpolates the running stopwatch.
const preparations = new Set(['previewSend', 'dustPreview', 'prepareTokenAction']);
const approvals = new Set(['send', 'dustApply', 'submitTokenAction']);
let active;
const drafts = new Map();

function emit() {
  if (active) self.postMessage({ type:'transaction', at:Date.now(), trace:active });
}
function closeStep(at) {
  const last = active?.steps.at(-1);
  if (last && last.end == null) last.end = at;
}
export function stage(name, extra = {}) {
  if (!active || active.end) return;
  Object.assign(active, extra);
  if (active.steps.at(-1)?.name !== name) {
    const at = Date.now();
    closeStep(at);
    active.steps.push({ name, start:at });
  }
  emit();
}
function finish(status) {
  if (!active) return;
  closeStep(Date.now());
  active.status = status;
  active.end = Date.now();
  emit();
}
export function proof(location) {
  if (!active || active.end) return () => {};
  const trace = active;
  const name = location.startsWith('midnight/') ? location.split('/').filter(Boolean).at(-1)
    : (trace.action === 'increment' ? 'increment' : trace.action);
  const row = { name, start:Date.now() };
  const parent = trace.steps.at(-1);
  (parent.proofs ??= []).push(row);
  emit();
  return failed => {
    row.end = Date.now();
    if (failed) row.failed = true;
    if (active === trace) emit();
  };
}
export function bind(tx) {
  if (!active) return;
  active.hash = tx.transactionHash();
  active.ids = tx.identifiers();
  emit();
}
export function recorded(ids) {
  return active?.ids?.some(id => ids.includes(id)) || ids.includes(active?.hash) ? structuredClone(active) : undefined;
}
export function discard(id) { drafts.delete(String(id)); }
export function clear() { active = null; drafts.clear(); }
export async function run(method, params, id, execute) {
  if (method === 'cancel') drafts.delete(String(params.id));
  if (method === 'lock' || method === 'resetWallet') clear();
  const prepare = preparations.has(method);
  if (!prepare && !approvals.has(method)) return execute();
  if (active?.status === 'running') throw Error('A transaction is already in progress');
  if (prepare) {
    const action = method === 'previewSend' ? 'send' : params.action;
    active = { key:String(id), action, start:Date.now(), status:'running', steps:[] };
    stage('Preparing');
  } else {
    active = drafts.get(String(params.id));
    drafts.delete(String(params.id));
    if (!active) return execute(); // The engine owns expiry and returns the appropriate error.
    delete active.end;
    if (active.steps.at(-1)?.name === 'Awaiting approval') delete active.steps.at(-1).end;
    active.status = 'running';
    stage('Approved');
  }
  try {
    const result = await execute();
    if (prepare) {
      stage('Awaiting approval');
      finish('review');
      drafts.set(String(result.id), active);
    } else if (!active.end) finish('complete');
    return result;
  } catch (error) {
    if (active) {
      active.error = String(error?.message ?? error);
      finish('error');
    }
    throw error;
  }
}
export function nodeEvent(event) {
  if (!active || active.end) return;
  const extra = event.blockHeight == null ? {} : { block:Number(event.blockHeight) };
  if (event._tag === 'Submitted') {
    if (active.steps.at(-1)?.name === 'In block') { delete active.block; stage('Returned to pool'); }
    stage('Submitted');
  } else if (event._tag === 'InBlock') {
    stage('In block', extra);
  } else if (event._tag === 'Finalized') {
    stage('Finalized', extra);
    finish('finalized');
  }
}
