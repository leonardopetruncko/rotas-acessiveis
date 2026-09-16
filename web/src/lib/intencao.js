// Assistente: entende pedidos em português e traduz em (perfil, origem, destino, modo).
// Regras transparentes (auditáveis). Ele SUGERE — a pessoa confirma/troca na tela.
import { ehDestino } from './tema.js';

const norm = s => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
const GENERICAS = new Set(['stand', 'sala', 'de', 'da', 'do', 'das', 'dos', 'e', 'a', 'o', 'cloud', 'saida', 'emergencia',
  'principal', 'fiap', 'area', 'praca', 'banheiro', 'adaptado', 'entrada', 'corredor', 'interno', 'rua', 'sul', 'norte', 'leste', 'oeste']);

function chaves(nome) {
  const n = norm(nome).replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
  const semStand = n.replace(/^stand /, '');
  const tokens = semStand.split(' ').filter(t => t.length >= 3 && !GENERICAS.has(t));
  return [semStand, ...tokens];
}

const PERFIS = [
  ['CADEIRANTE', ['cadeira de rodas', 'cadeirante', 'carrinho de bebe', 'carrinho']],
  ['MOBILIDADE', ['muleta', 'andador', 'bengala', 'mobilidade', 'nao consigo andar', 'dor na perna', 'idoso', 'gravida']],
  ['NEURODIVERGENTE', ['autis', 'autismo', 'tdah', 'neurodiver', 'sensorial', 'ansiedade', 'crise', 'sobrecarga', 'barulho',
    'muito som', 'multidao', 'lotado', 'calmo', 'silencio', 'tranquil', 'insuportavel']],
];

const DESTINOS = [
  ['SAIDA', ['emergencia', 'incendio', 'fogo', 'fumaca', 'evacua', 'sair daqui', 'sair do evento', 'saida', 'socorro', 'perigo', 'alarme', 'ir embora']],
  ['BANHEIRO_ADAP', ['banheiro', 'sanitario', 'toalete', 'wc']],
  ['SERVICO', ['enfermaria', 'medico', 'passando mal', 'desmai', 'machuc', 'brigada', 'primeiros socorros']],
  ['ACOLHIMENTO', ['barulho', 'calmo', 'silencio', 'descomprim', 'descompress', 'acolhimento', 'sensorial', 'crise',
    'ansiedade', 'sobrecarga', 'tranquil', 'respirar', 'insuportavel']],
  ['ALIMENTACAO', ['comer', 'fome', 'comida', 'lanche', 'alimentacao', 'beber']],
];

export function interpretar(texto, pontos, perfis) {
  const t = ' ' + norm(texto) + ' ';
  const tem = ws => ws.some(w => t.includes(w));
  const out = {};

  for (const [cod, ws] of PERFIS) if (tem(ws)) { out.perfil = cod; break; }
  for (const [tipo, ws] of DESTINOS) if (tem(ws)) { out.destinoTipo = tipo; break; }

  // menções a lugares do evento
  const mencoes = [];
  for (const p of pontos.filter(ehDestino)) {
    let melhor = -1;
    for (const k of chaves(p.nome)) {
      const m = new RegExp(`(^|[^a-z0-9])${k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^a-z0-9]|$)`).exec(t);
      if (m && (melhor < 0 || m.index < melhor)) melhor = m.index;
    }
    if (melhor >= 0) mencoes.push({ p, idx: melhor });
  }
  mencoes.sort((a, b) => a.idx - b.idx);
  for (const { p, idx } of mencoes) {
    const antes = t.slice(Math.max(0, idx - 28), idx);
    const ehOrigem = /(estou|to |ta |tou |aqui |perto d|lado d|saindo d|frente d|dentro d)/.test(antes);
    const ehDest = /(para |pra |ate |ir |chegar|levar|onde fica|quero|preciso)/.test(antes);
    if (ehOrigem && !out.origem) out.origem = p.codigo;
    else if (ehDest && !out.destino) out.destino = p.codigo;
    else if (!out.origem && /estou|to no|to na/.test(t)) out.origem = p.codigo;
    else if (!out.destino && p.codigo !== out.origem) out.destino = p.codigo;
  }

  if (out.destinoTipo === 'SAIDA') out.modo = 'saida';
  else if (!out.destino && out.destinoTipo) {
    const cands = pontos.filter(p => p.tipo === out.destinoTipo);
    const pref = cands.find(p => /brigada|enfermaria/i.test(p.nome)) || cands[0];
    if (pref) out.destino = pref.codigo;
  }
  if (out.destino) out.modo = out.modo || 'rota';

  // resposta em linguagem natural
  const nome = c => pontos.find(p => p.codigo === c)?.nome;
  const partes = [];
  if (out.origem) partes.push(`você está em ${nome(out.origem)}`);
  if (out.modo === 'saida') partes.push('precisa sair com segurança');
  else if (out.destino) partes.push(`quer chegar em ${nome(out.destino)}`);
  let resposta = partes.length ? `Entendi: ${partes.join(' e ')}.` : '';
  if (out.perfil) resposta += ` Sugeri o perfil ${perfis?.find(p => p.codigo === out.perfil)?.nome ?? out.perfil} — pode trocar se não for você.`;
  if (!out.origem && (out.destino || out.modo)) resposta += ' Usei a sua última localização; toque no mapa se estiver em outro lugar.';
  if (!partes.length && !out.perfil) {
    resposta = 'Não entendi ainda. Tente algo como: "estou no stand da Oracle, o barulho está insuportável" ou "onde fica o banheiro adaptado?".';
    out.naoEntendi = true;
  }
  out.resposta = resposta.trim();
  return out;
}
