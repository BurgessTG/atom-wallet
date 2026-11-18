// The networks the wallet supports. Each one has its own wallet (recovery
// phrase, password, database, dApp approvals); nothing is shared.
//
// Endpoints are defaults: every one is editable per network in Settings.
// Blockfrost hosts Mainnet and Preprod and wants a project id, which the user
// types in Settings and which is appended as `?project_id=` to all three URLs
// at connection time only. The id is a credential: it is never stored inside
// a URL and never handed to a dApp (see publicEndpoints).
export const NETWORKS = {
  mainnet: {
    name: 'Mainnet', networkId: 'mainnet', blockfrost: true,
    node: 'wss://rpc.midnight-mainnet.blockfrost.io',
    indexerHttp: 'https://midnight-mainnet.blockfrost.io/api/v0',
    indexerWs: 'wss://midnight-mainnet.blockfrost.io/api/v0/ws',
  },
  preprod: {
    name: 'Preprod', networkId: 'preprod', blockfrost: true,
    node: 'wss://rpc.midnight-preprod.blockfrost.io',
    indexerHttp: 'https://midnight-preprod.blockfrost.io/api/v0',
    indexerWs: 'wss://midnight-preprod.blockfrost.io/api/v0/ws',
  },
  preview: {
    name: 'Preview', networkId: 'preview',
    node: 'wss://rpc.preview.midnight.network',
    indexerHttp: 'https://indexer.preview.midnight.network/api/v4/graphql',
    indexerWs: 'wss://indexer.preview.midnight.network/api/v4/graphql/ws',
  },
  undeployed: {
    name: 'Undeployed', networkId: 'undeployed',
    node: 'ws://localhost:9944',
    indexerHttp: 'http://localhost:8088/api/v4/graphql',
    indexerWs: 'ws://localhost:8088/api/v4/graphql/ws',
  },
};

export const NETWORK_IDS = Object.keys(NETWORKS);
export const DEFAULT_NETWORK = 'preview';
export const DEFAULT_PROOF_SERVER = 'http://localhost:6300';

// NIGHT is the unshielded native token: 6 decimals (smallest unit STAR).
// DUST pays fees: 15 decimals (smallest unit SPECK).
export const NIGHT_TOKEN = '0'.repeat(64);
export const NIGHT_DECIMALS = 6;
export const DUST_DECIMALS = 15;

export function network(id) {
  const n = NETWORKS[id];
  if (!n) throw new Error(`Unknown network ${id}`);
  return n;
}

/** The endpoints a network starts with, before the user edits any. */
export function defaultEndpoints(id) {
  const n = network(id);
  return {
    node: n.node, indexerHttp: n.indexerHttp, indexerWs: n.indexerWs, projectId: '',
    prover: { kind: 'wasm', url: DEFAULT_PROOF_SERVER },
  };
}

/** Stored endpoints merged over the defaults, so a partial record still works. */
export function endpointsOf(id, stored) {
  const d = defaultEndpoints(id);
  const s = stored ?? {};
  return {
    node: s.node || d.node, indexerHttp: s.indexerHttp || d.indexerHttp, indexerWs: s.indexerWs || d.indexerWs,
    projectId: (s.projectId ?? '').trim(),
    prover: { kind: s.prover?.kind === 'server' ? 'server' : 'wasm', url: s.prover?.url || d.prover.url },
  };
}

/** The URLs to connect with: the Blockfrost project id goes onto all three.
 *  Throws the message the sync status shows when a Blockfrost network has no id. */
export function connectionUrls(id, endpoints) {
  const n = network(id);
  const e = endpointsOf(id, endpoints);
  if (n.blockfrost && !e.projectId) throw new Error('Add a Blockfrost project id in Settings');
  const withId = url => {
    if (!e.projectId) return url;
    const u = new URL(url);
    u.searchParams.set('project_id', e.projectId);
    return u.toString();
  };
  return { node: withId(e.node), indexerHttp: withId(e.indexerHttp), indexerWs: withId(e.indexerWs), prover: e.prover };
}

/** What a dApp may see of the endpoints: the base URLs, never the project id. */
export function publicEndpoints(id, endpoints) {
  const e = endpointsOf(id, endpoints);
  return { node: e.node, indexerHttp: e.indexerHttp, indexerWs: e.indexerWs, prover: e.prover };
}
