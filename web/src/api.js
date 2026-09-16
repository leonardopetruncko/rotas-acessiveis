import { criarMotor } from './lib/motorLocal.js';

const BASE = (import.meta.env.VITE_API_BASE ||
  'https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1').replace(/\/$/, '');

export const API_BASE = BASE;
const TIMEOUT_MS = 5000;

// ------------------------------------------------------------------ modo offline
// Se o navegador não alcança o Oracle (rede do evento, operadora, firewall), o site segue
// funcionando com a cópia do mapa (public/dados) e o motor local — idêntico ao AC_ROTAS.
let offline = false;
const ouvintes = new Set();
export const emModoOffline = () => offline;
export function aoMudarModo(fn) {
  ouvintes.add(fn);
  return () => ouvintes.delete(fn);
}
function entrarOffline() {
  if (offline) return;
  offline = true;
  ouvintes.forEach(fn => fn(true));
}

const motores = {};
function motor(ev) {
  const cod = String(ev).toUpperCase();
  motores[cod] ||= fetch(`${import.meta.env.BASE_URL}dados/${cod}.json`)
    .then(r => { if (!r.ok) throw new Error(`Evento não encontrado: ${cod}`); return r.json(); })
    .then(criarMotor)
    .catch(e => { delete motores[cod]; throw e; });
  return motores[cod];
}

// ------------------------------------------------------------------ remoto
class ErroRede extends Error {}

async function req(path, opt = {}) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  let r;
  try {
    r = await fetch(BASE + path, { cache: 'no-store', ...opt, signal: ctrl.signal });
  } catch {
    throw new ErroRede('sem conexão com o Oracle');
  } finally {
    clearTimeout(t);
  }
  const j = await r.json().catch(() => ({ mensagem: `HTTP ${r.status}` }));
  if (r.status >= 500) throw new ErroRede(j.mensagem || `HTTP ${r.status}`);
  if (!r.ok) throw new Error(j.mensagem || `HTTP ${r.status}`);
  return j;
}

async function comFallback(remoto, local) {
  if (!offline) {
    try {
      return await remoto();
    } catch (e) {
      if (!(e instanceof ErroRede)) throw e;
      entrarOffline();
    }
  }
  return local();
}

const qs = o => new URLSearchParams(Object.entries(o).filter(([, v]) => v)).toString();
const post = body => ({ method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body ?? {}) });

export const api = {
  eventos: () => comFallback(() => req('/eventos'),
    () => fetch(`${import.meta.env.BASE_URL}dados/eventos.json`).then(r => r.json())),
  mapa: ev => comFallback(() => req(`/eventos/${ev}`), async () => (await motor(ev)).mapa()),
  rota: (ev, p) => comFallback(() => req(`/eventos/${ev}/rota?${qs(p)}`), async () => (await motor(ev)).rota(p)),
  comparar: (ev, p) => comFallback(() => req(`/eventos/${ev}/comparar?${qs(p)}`), async () => (await motor(ev)).comparar(p)),
  saida: (ev, p) => comFallback(() => req(`/eventos/${ev}/saida?${qs(p)}`), async () => (await motor(ev)).saida(p)),
  reportar: (ev, body) => comFallback(() => req(`/eventos/${ev}/reportes`, post(body)), async () => (await motor(ev)).reportar(body)),
  // assistente semântico (ONNX + Vector Search no Oracle); offline = null -> front usa regras locais
  assistente: (ev, texto) => comFallback(() => req(`/eventos/${ev}/assistente`, post({ texto })), async () => null),
  conversa: (ev, body) => comFallback(() => req(`/eventos/${ev}/conversa`, post(body)), async () => null),
  reset: ev => comFallback(() => req(`/eventos/${ev}/reset`, { method: 'POST' }), async () => (await motor(ev)).reset()),
};

// parâmetros vêm do ?query (QR code) ou do #/app?query
export function lerParams() {
  const p = new URLSearchParams(window.location.search);
  const h = window.location.hash.split('?')[1];
  if (h) new URLSearchParams(h).forEach((v, k) => p.set(k, v));
  return p;
}
