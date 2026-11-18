// Sites: the dApps this wallet has approved, what each may call, and a way to
// disconnect one.
import { useEffect, useState } from 'react';
import { GlobeHemisphereWestIcon, PlugsIcon } from '@phosphor-icons/react';
import { Badge } from '@cloudflare/kumo/components/badge';
import { Dialog } from '@cloudflare/kumo/components/dialog';
import { Empty } from '@cloudflare/kumo/components/empty';
import { Loader } from '@cloudflare/kumo/components/loader';
import { useKumoToastManager } from '@cloudflare/kumo/components/toast';
import { NetworkBadge } from './brand.jsx';
import { ListCard, PrimaryButton, SecondaryButton, Viewport } from './components.jsx';
import { ui } from './api.js';
import { dayOnly } from './format.js';

function SiteRow({ site, networkName, onForget }) {
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const forget = async () => {
    setBusy(true);
    try { await onForget(site); setOpen(false); } finally { setBusy(false); }
  };
  return (
    <div className="flex flex-col gap-2.5 px-4 py-3">
      <div className="flex items-center gap-2">
        <span className="min-w-0 flex-1 truncate font-mono text-[13px] font-medium text-kumo-default">{site.origin}</span>
        <NetworkBadge network={site.network} name={networkName} />
      </div>
      <span className="text-[11px] text-kumo-subtle">Connected {dayOnly(site.grantedAt)}</span>
      {site.permissions?.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {site.permissions.map(p => <Badge key={p} variant="secondary" className="font-mono text-[10px]">{p}</Badge>)}
        </div>
      )}
      <Dialog.Root open={open} onOpenChange={setOpen}>
        <Dialog.Trigger render={p => <SecondaryButton {...p} className="h-8 w-full text-[13px]" tone="danger" icon={PlugsIcon}>Disconnect</SecondaryButton>} />
        <Dialog size="sm" className="flex flex-col gap-4 p-6">
          <Dialog.Title className="text-base font-semibold text-kumo-default">Disconnect {site.origin}?</Dialog.Title>
          <Dialog.Description className="text-[13px] leading-normal text-kumo-subtle">The site will have to ask for your approval again before it can see this wallet or request anything.</Dialog.Description>
          <div className="flex gap-2">
            <Dialog.Close render={p => <SecondaryButton {...p} type="button">Cancel</SecondaryButton>} />
            <PrimaryButton variant="destructive" className="flex-1" loading={busy} onClick={forget}>Disconnect</PrimaryButton>
          </div>
        </Dialog>
      </Dialog.Root>
    </div>
  );
}

export function Sites({ state }) {
  const toasts = useKumoToastManager();
  const [sites, setSites] = useState(null);
  const [error, setError] = useState(null);
  const load = () => ui('sites').then(setSites, e => setError(e.message));
  useEffect(() => { setSites(null); load(); }, [state.network]);   // eslint-disable-line react-hooks/exhaustive-deps
  const forget = async ({ origin, network }) => {
    try {
      await ui('forgetSite', { origin, network });
      toasts.add({ title: 'Disconnected', description: origin, variant: 'success' });
      await load();
    } catch (e) { toasts.add({ title: 'Could not disconnect', description: e.message, variant: 'error' }); throw e; }
  };
  const nameOf = id => state.networks.find(n => n.id === id)?.name ?? id;
  return (
    <Viewport gap="gap-3">
      <div className="flex flex-col gap-1 px-1">
        <h2 className="text-lg font-bold text-kumo-default">Sites</h2>
        <p className="text-xs leading-normal text-kumo-subtle">Sites you have allowed to connect to this wallet.</p>
      </div>
      {!sites && !error && <div className="flex justify-center p-6"><Loader /></div>}
      {error && <p className="px-1 text-xs text-kumo-danger">{error}</p>}
      {sites && !sites.length && (
        <Empty size="sm" icon={<GlobeHemisphereWestIcon size={28} />} title="No connected sites"
          description="dApps appear here after you approve a connection." />
      )}
      {sites?.length > 0 && (
        <ListCard>
          {sites.map(s => <SiteRow key={`${s.network}.${s.origin}`} site={s} networkName={nameOf(s.network)} onForget={forget} />)}
        </ListCard>
      )}
    </Viewport>
  );
}
