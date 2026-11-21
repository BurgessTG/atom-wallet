import { createUnprovenDeployTx, createUnprovenCallTx } from '@midnight-ntwrk/midnight-js-contracts';
import { CompiledContract } from '@midnight-ntwrk/midnight-js-protocol/v9/compact-js';
import { ContractState } from '@midnight-ntwrk/compact-runtime';
import { CostModel, Transaction, rawTokenType } from '@midnight-ntwrk/midnight-js-protocol/v9';
import { ZKConfigRegistry, zkConfigToProvingKeyMaterial } from '@midnight-ntwrk/midnight-js-types';
import { FetchZkConfigProvider } from '@midnight-ntwrk/midnight-js-fetch-zk-config-provider';
import { indexerPublicDataProvider } from '@midnight-ntwrk/midnight-js-indexer-public-data-provider';
import * as token from '../contracts/managed/contract/index.js';
import * as counter from '../../dapp/contract/managed/contract/index.js';
import { dappProver, addressesOf } from '../../extension/src/midnight.js';

function defineContract(name, module, readValue) {
  const path = '/' + name + '-contract';
  return {
    compiledContract: CompiledContract.make(name, module.Contract).pipe(
      CompiledContract.withVacantWitnesses, CompiledContract.withCompiledFileAssets(path)),
    assets: new FetchZkConfigProvider(new URL(path, self.location.origin).href, {
      fetchFunc: (url, init) => fetch(url, init),
    }),
    value: state => readValue(module.ledger(state.data)).toString(),
  };
}
const contracts = {
  token: defineContract('token', token, state => state.mintCount),
  counter: defineContract('counter', counter, state => state.round),
};
const registry = new ZKConfigRegistry(Object.values(contracts).map(c => c.assets));
async function lookupKey(location) {
  const config = await registry.resolveKeyLocation(location);
  return config && zkConfigToProvingKeyMaterial(config);
}


export function tokenTypes(address) {
  const type = name => {
    const domain = new Uint8Array(32);
    domain.set(new TextEncoder().encode(name));
    return rawTokenType(domain, address);
  };
  return { shielded:type('mdwa-preview-shielded'), unshielded:type('mdwa-preview-public') };
}

function networkData(run, urls) {
  return run.contractData ??= indexerPublicDataProvider({
    queryURL: urls.indexerHttp, subscriptionURL: urls.indexerWs, webSocket: WebSocket,
  });
}

export function watchContract(run, urls, kind, address, notify) {
  run.contractFeeds ??= new Map();
  if (run.contractFeeds.has(address)) return run.contractFeeds.get(address).value;
  const feed = { value:null };
  run.contractFeeds.set(address, feed);
  feed.subscription = networkData(run, urls).contractStateObservable(address).subscribe({
    next({ value, blockHeight }) {
      if (run.stopped) return;
      try {
        const state = value.contractState.deserialize({ v9:ContractState });
        feed.value = { count:contracts[kind].value(state), block:blockHeight };
      } catch (error) {
        feed.value = { error:'Could not decode contract state: ' + error.message };
      }
      notify();
    },
    error() { run.contractFeeds.delete(address); },
  });
  return feed.value;
}

export async function preparePreviewContract({ run, wallet, state, urls, action, amount, address, kind }) {
  if (wallet.networkId !== 'preview') throw Error('Test token contracts require Midnight Preview');
  // Initialize the shared Compact effect runtime before entering the SDK's lazy era adapters.
  await import('@midnight-ntwrk/midnight-js-protocol/v9/compact-js/effect');
  const { compiledContract, assets } = contracts[kind];
  const keys = addressesOf(state, 'preview');
  const providers = {
    config: { networkId:'preview', ttlSeconds:1800 },
    walletProvider: { getCoinPublicKey: () => keys.coinPublicKey, getEncryptionPublicKey: () => keys.encryptionPublicKey },
    zkConfigProvider: assets, publicDataProvider:networkData(run, urls),
  };
  let built;
  let tokenType;
  if (action === 'deploy') {
    built = await createUnprovenDeployTx(providers, { compiledContract, args:[] });
    address = built.public.contractAddress;
  } else {
    if (!address) throw Error('Deploy the contract first');
    let args;
    if (kind === 'counter' && action === 'increment') {
      args = [];
    } else if (kind === 'token' && ['mintShielded','mintUnshielded'].includes(action)) {
      if (!/^[1-9][0-9]{0,19}$/.test(amount) || BigInt(amount) > 0xffffffffffffffffn) throw Error('Enter a positive 64-bit whole amount');
      const shielded = action === 'mintShielded';
      const recipient = shielded ? crypto.getRandomValues(new Uint8Array(32)) : { bytes:Uint8Array.from(state.unshielded.address.data) };
      tokenType = tokenTypes(address)[shielded ? 'shielded' : 'unshielded'];
      args = [BigInt(amount), recipient];
    } else {
      throw Error('Unknown contract action');
    }
    built = await createUnprovenCallTx(providers, { compiledContract, contractAddress:address, circuitId:action, args });
  }
  const unproven = built.private.unprovenTx.deserialize({ v9:Transaction });
  globalThis.mdwaProgress?.stage('Proving contract');
  const prover = { ...dappProver(urls.prover, lookupKey), lookupKey };
  const proven = await unproven.prove(prover, CostModel.initialCostModel());
  const handle = wallet.facade.adoptTransaction(proven.serialize(), 'Unbound');
  globalThis.mdwaProgress?.stage('Balancing');
  const recipe = await wallet.facade.balanceUnboundTransaction(handle, {
    ttl:new Date(Date.now()+1800000), tokenKindsToBalance:'all',
  });
  return { recipe, address, tokenType, signingKey:built.private.signingKey };
}
