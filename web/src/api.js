const BASE = (import.meta.env.VITE_API_BASE ||
  'https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1').replace(/\/$/, '');

export const API_BASE = BASE;

// falha de rede ("Failed to fetch") não é erro do banco: é o navegador sem chegar no Oracle
// (firewall da rede, bloqueador, oscilação). Tenta de novo antes de desistir.
async function buscar(url, opt, tentativas = 3) {
  for (let i = 0; ; i++) {
    try {
      return await fetch(url, opt);
    } catch (e) {
      if (i >= tentativas - 1) {
        const err = new Error('Sem conexão com o banco de dados do evento. Se estiver numa rede corporativa/faculdade, com VPN ou bloqueador de anúncios, tente pelo 4G ou desative o bloqueador.');
        err.rede = true;
        throw err;
      }
      await new Promise(r => setTimeout(r, 600 * (i + 1)));
    }
  }
}

async function req(path, opt = {}) {
  const r = await buscar(BASE + path, { cache: 'no-store', ...opt }, opt.method ? 1 : 3);
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
