// Motor de rotas LOCAL — espelho do package AC_ROTAS (sql/12_pkg_ac_rotas.sql).
// Usado quando o navegador não alcança o Oracle (rede do evento caiu, operadora bloqueou...).
// Mesma fórmula, mesmas mensagens: a pessoa continua recebendo rota e saída segura offline.
const INF = 1e12;
const ORDEM_PERFIL = { PADRAO: 1, CADEIRANTE: 2, MOBILIDADE: 3 };

const PESOS_PADRAO = {
  PADRAO: [1, 1, 1.3], CADEIRANTE: [1, 4, 1.0], MOBILIDADE: [1, 3, 0.7], NEURODIVERGENTE: [6, 5, 1.2],
};

function erro(status, mensagem) {
  const e = new Error(mensagem);
  e.status = status;
  return e;
}

export function criarMotor(mapaOriginal) {
  const m = structuredClone(mapaOriginal);
  m.reportes = m.reportes || [];
  const P = () => Object.fromEntries(m.pontos.map(p => [p.codigo, p]));

  function perfil(cod) {
    if (!cod) throw erro(400, 'Parâmetro obrigatório: perfil');
    const p = m.perfis.find(x => x.codigo === String(cod).toUpperCase());
    if (!p) throw erro(404, `Perfil não encontrado: ${cod}`);
    const d = PESOS_PADRAO[p.codigo] || [1, 1, 1.2];
    return { codigo: p.codigo, nome: p.nome, evita: p.evita_escada, pr: p.peso_ruido ?? d[0], pl: p.peso_lotacao ?? d[1], vel: p.velocidade_ms ?? d[2] };
  }

  function ponto(cod, param) {
    if (!cod) throw erro(400, `Parâmetro obrigatório: ${param}`);
    const p = P()[String(cod).toUpperCase()];
    if (!p) throw erro(404, `Ponto não encontrado (${param}): ${cod}`);
    return p.codigo;
  }

  const pontoObj = cod => {
    const p = P()[cod];
    return { codigo: p.codigo, nome: p.nome, tipo: p.tipo, x: p.x, y: p.y };
  };
  const nome = cod => P()[cod]?.nome;

  function buscar(pf, origem) {
    const bloq = new Set(m.pontos.filter(p => p.bloqueado === 'S').map(p => p.codigo));
    const adj = {}, tr = {};
    for (const t of m.trechos) {
      if (t.bloqueado === 'S') continue;
      tr[t.id] = t;
      if (pf.evita === 'S' && t.escada === 'S') continue;
      (adj[t.a] ||= []).push({ t: t.id, v: t.b });
      (adj[t.b] ||= []).push({ t: t.id, v: t.a });
    }
    const dist = {}, prev = {}, prevt = {}, vis = new Set();
    for (const p of m.pontos) dist[p.codigo] = INF;
    dist[origem] = 0;
    for (;;) {
      let u = null, best = INF;
      for (const k in dist) if (!vis.has(k) && dist[k] < best - 1e-9) { best = dist[k]; u = k; }
      if (u === null) break;
      vis.add(u);
      for (const { t, v } of adj[u] || []) {
        if (bloq.has(v)) continue;
        const e = tr[t];
        const c = dist[u] + e.distancia_m * (1 + ((e.ruido - 1) * pf.pr) / 10 + ((e.lotacao - 1) * pf.pl) / 10);
        if (c < dist[v] - 1e-9) { dist[v] = c; prev[v] = u; prevt[v] = t; } // tolerância: Oracle soma em decimal exato
      }
    }
    return { dist, prev, prevt, tr, origem };
  }

  function resumir(b, destino) {
    const r = { ok: false, metros: 0, max_r: 0, max_l: 0, escada: false, pts: [], trs: [] };
    if (!(destino in b.dist) || b.dist[destino] >= INF) return r;
    r.ok = true;
    r.custo = b.dist[destino];
    for (let cur = destino; cur !== b.origem; cur = b.prev[cur]) { r.pts.unshift(cur); r.trs.unshift(b.prevt[cur]); }
    r.pts.unshift(b.origem);
    for (const id of r.trs) {
      const t = b.tr[id];
      r.metros += t.distancia_m;
      r.max_r = Math.max(r.max_r, t.ruido);
      r.max_l = Math.max(r.max_l, t.lotacao);
      if (t.escada === 'S') r.escada = true;
    }
    return r;
  }

  const minutos = (metros, vel) => Math.max(1, Math.ceil(metros / vel / 60));
  const r1 = n => Math.round(n * 10) / 10;

  function rotaObj(pf, b, r, destino, ref) {
    const o = { perfil: { codigo: pf.codigo, nome: pf.nome }, origem: pontoObj(b.origem), destino: pontoObj(destino) };
    if (!r.ok) {
      o.status = 'SEM_ROTA';
      o.mensagem = `Não encontrei um caminho sem barreiras para o perfil ${pf.nome} até ${nome(destino)}. Procure a equipe de apoio mais próxima.`;
      return o;
    }
    Object.assign(o, {
      status: 'OK', distancia_m: Math.round(r.metros), tempo_min: minutos(r.metros, pf.vel), custo: r1(r.custo),
      tem_escada: r.escada, ruido_max: r.max_r, lotacao_max: r.max_l,
      pontos: r.pts.map(pontoObj),
    });
    const trechos = [], instrucoes = [], alertas = [], vistos = new Set();
    let via = null, acum = 0;
    r.trs.forEach((id, i) => {
      const t = b.tr[id];
      trechos.push({ id, via: t.via, distancia_m: t.distancia_m, escada: t.escada === 'S', ruido: t.ruido, lotacao: t.lotacao });
      if (via !== null && t.via !== via) {
        instrucoes.push(`Siga por ${via} (~${Math.round(acum)} m) até ${nome(r.pts[i])}.`);
        acum = 0;
      }
      via = t.via;
      acum += t.distancia_m;
      if (t.ruido >= 4 && !vistos.has(`R:${via}`)) { alertas.push(`Barulho alto em ${via} (nível ${t.ruido}/5).`); vistos.add(`R:${via}`); }
      if (t.lotacao >= 4 && !vistos.has(`L:${via}`)) { alertas.push(`Muita gente em ${via} (lotação ${t.lotacao}/5).`); vistos.add(`L:${via}`); }
    });
    if (via !== null) instrucoes.push(`Siga por ${via} (~${Math.round(acum)} m) até ${nome(destino)}.`);
    const evita = [];
    if (ref?.ok && pf.codigo !== 'PADRAO') {
      if (ref.escada && !r.escada) evita.push('escadas e degraus');
      if (ref.max_r > r.max_r) evita.push(`barulho (nível ${ref.max_r} → ${r.max_r})`);
      if (ref.max_l > r.max_l) evita.push(`aglomeração (lotação ${ref.max_l} → ${r.max_l})`);
    }
    let msg = `Sugestão para ${pf.nome}: ${Math.round(r.metros)} m, cerca de ${minutos(r.metros, pf.vel)} min.`;
    if (evita.length) msg += ` Comparada à rota mais direta, evita ${evita.join(', ')}.`;
    if (ref?.ok && r.metros - ref.metros >= 5) msg += ` É ${Math.round(r.metros - ref.metros)} m mais longa.`;
    if (alertas.length) msg += ` Atenção: ${alertas[0]}`;
    Object.assign(o, { instrucoes, trechos, alertas, evita, mensagem: `${msg} Você decide se segue.` });
    return o;
  }

  const perfisOrdenados = () => [...m.perfis].sort((a, b) => (ORDEM_PERFIL[a.codigo] || 4) - (ORDEM_PERFIL[b.codigo] || 4));

  return {
    mapa: () => structuredClone(m),

    rota({ perfil: pc, origem, destino }) {
      const pf = perfil(pc), o = ponto(origem, 'origem'), d = ponto(destino, 'destino');
      const b = buscar(pf, o);
      return rotaObj(pf, b, resumir(b, d), d, resumir(buscar(perfil('PADRAO'), o), d));
    },

    comparar({ origem, destino }) {
      const o = ponto(origem, 'origem'), d = ponto(destino, 'destino');
      const ref = resumir(buscar(perfil('PADRAO'), o), d);
      return { rotas: perfisOrdenados().map(p => { const pf = perfil(p.codigo); const b = buscar(pf, o); return rotaObj(pf, b, resumir(b, d), d, ref); }) };
    },

    saida({ perfil: pc, origem }) {
      const pf = perfil(pc), o = ponto(origem, 'origem');
      const b = buscar(pf, o);
      const ids = [], indisponiveis = [];
      for (const s of m.pontos.filter(p => p.tipo === 'SAIDA')) {
        if (s.bloqueado === 'S' || b.dist[s.codigo] >= INF) {
          indisponiveis.push({ codigo: s.codigo, nome: s.nome, motivo: s.bloqueado === 'S' ? 'interditada' : 'sem caminho viável para este perfil' });
        } else ids.push(s.codigo);
      }
      ids.sort((x, y) => b.dist[x] - b.dist[y]);
      if (!ids.length) {
        return { status: 'SEM_ROTA', perfil: pf.codigo, origem: pontoObj(o), indisponiveis,
          mensagem: 'Nenhuma saída alcançável sem barreiras a partir daqui. Permaneça em local seguro e chame a brigada.' };
      }
      const bRef = buscar(perfil('PADRAO'), o);
      let refId = null;
      for (const s of m.pontos.filter(p => p.tipo === 'SAIDA' && p.bloqueado !== 'S')) {
        if (bRef.dist[s.codigo] < INF && (refId === null || bRef.dist[s.codigo] < bRef.dist[refId])) refId = s.codigo;
      }
      const ref = refId ? resumir(bRef, refId) : null;
      const o2 = rotaObj(pf, b, resumir(b, ids[0]), ids[0], ref);
      const alternativas = ids.slice(1).map(id => {
        const r = resumir(b, id);
        return { ...pontoObj(id), distancia_m: Math.round(r.metros), tempo_min: minutos(r.metros, pf.vel), custo: r1(r.custo),
          tem_escada: r.escada, ruido_max: r.max_r, lotacao_max: r.max_l, caminho: r.pts };
      });
      const txt = alternativas.slice(0, 2).map(a => `${a.nome} (${a.distancia_m} m)`).join('; ');
      const { mensagem, ...resto } = o2; // Oracle devolve "mensagem" no fim
      return { ...resto, saida_sugerida: pontoObj(ids[0]), alternativas, indisponiveis,
        mensagem: `Saída sugerida: ${nome(ids[0])}. ${mensagem}${txt ? ` Outras opções: ${txt}.` : ''}` };
    },

    reportar({ ponto: pc, tipo, usuario }) {
      const cod = ponto(pc, 'ponto');
      const t = String(tipo || '').toUpperCase();
      const adj = m.trechos.filter(x => x.a === cod || x.b === cod);
      const p = P()[cod];
      let msg;
      if (t === 'CHEIO') { adj.forEach(x => { x.lotacao = Math.min(x.lotacao + 1, 5); }); msg = 'Lotação aumentada perto de '; }
      else if (t === 'BARULHO') { adj.forEach(x => { x.ruido = Math.min(x.ruido + 1, 5); }); msg = 'Barulho aumentado perto de '; }
      else if (t === 'BLOQUEIO') { p.bloqueado = 'S'; msg = 'Passagem interditada: '; }
      else if (t === 'LIBERADO') { p.bloqueado = 'N'; adj.forEach(x => { x.ruido = x.ruido_base; x.lotacao = x.lotacao_base; }); msg = 'Situação normalizada em '; }
      else throw erro(400, 'tipo deve ser CHEIO, BARULHO, BLOQUEIO ou LIBERADO');
      m.reportes.unshift({ ponto: cod, nome: p.nome, tipo: t, por: usuario || 'anonimo', em: new Date().toISOString() });
      m.reportes = m.reportes.slice(0, 20);
      return { status: 'OK', tipo: t, ponto: pontoObj(cod), mensagem: `Obrigado! ${msg}${p.nome}. As rotas já consideram isso.` };
    },

    reset() {
      m.trechos.forEach(x => { x.ruido = x.ruido_base; x.lotacao = x.lotacao_base; x.bloqueado = 'N'; });
      m.pontos.forEach(p => { p.bloqueado = 'N'; });
      m.reportes = [];
      return { status: 'OK', mensagem: 'Cenário da demo restaurado.' };
    },
  };
}
