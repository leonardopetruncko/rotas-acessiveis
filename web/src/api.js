const BASE = (import.meta.env.VITE_API_BASE ||
  'https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1').replace(/\/$/, '');

async function req(path, opt = {}) {
  const r = await fetch(BASE + path, { cache: 'no-store', ...opt });
  const j = await r.json().catch(() => ({ mensagem: `HTTP ${r.status}` }));
  if (!r.ok) throw new Error(j.mensagem || `HTTP ${r.status}`);
  return j;
}

const qs = o => new URLSearchParams(Object.entries(o).filter(([, v]) => v)).toString();
const post = body => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) });

export const api = {
  eventos: () => req('/eventos'),
  mapa: ev => req(`/eventos/${ev}`),
  rota: (ev, p) => req(`/eventos/${ev}/rota?${qs(p)}`),
  comparar: (ev, p) => req(`/eventos/${ev}/comparar?${qs(p)}`),
  saida: (ev, p) => req(`/eventos/${ev}/saida?${qs(p)}`),
  reportar: (ev, body) => req(`/eventos/${ev}/reportes`, post(body)),
  reset: ev => req(`/eventos/${ev}/reset`, { method: 'POST' }),
};

// parâmetros vêm do ?query (QR code) ou do #/app?query
export function lerParams() {
  const p = new URLSearchParams(window.location.search);
  const h = window.location.hash.split('?')[1];
  if (h) new URLSearchParams(h).forEach((v, k) => p.set(k, v));
  return p;
}
