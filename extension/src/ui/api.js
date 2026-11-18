// UI <-> background helpers shared by the popup and approval pages.
export async function ui(method, params = {}) {
  const reply = await chrome.runtime.sendMessage({ type: 'ui', method, params });
  if (reply?.error) throw Object.assign(new Error(reply.error.message), { code: reply.error.code, locked: !!reply.error.locked });
  return reply?.result;
}

export function onState(handler) {
  const listener = message => { if (message?.type === 'state') handler(message.state); };
  chrome.runtime.onMessage.addListener(listener);
  return () => chrome.runtime.onMessage.removeListener(listener);
}
