// Gerador de cenários: simula rotas (mesma fórmula do AC_ROTAS) e gera o seed SQL.
import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

export const perfis = [
  ['PADRAO', 'Sem restrição', 'N', 1, 1, 1.3, 'Caminho mais curto, evitando só o que está muito cheio.'],
  ['CADEIRANTE', 'Cadeirante / carrinho de bebê', 'S', 1, 4, 1.0, 'Sem escadas nem degraus; foge de multidão, onde a cadeira não passa.'],
  ['MOBILIDADE', 'Muletas / mobilidade reduzida', 'S', 1, 3, 0.7, 'Sem escadas; prefere trechos com menos gente.'],
  ['NEURODIVERGENTE', 'Neurodivergente / sensível a estímulos', 'N', 6, 5, 1.2, 'Prioriza silêncio e pouca gente, mesmo que o caminho seja mais longo.'],
];

export function cenario(c, importMetaUrl) {
  const P = Object.fromEntries(c.pontos.map(p => [p[0], p]));
  for (const [a, b] of c.trechos) if (!P[a] || !P[b]) throw new Error(`trecho com ponto inexistente: ${a}-${b}`);
  const dist = (a, b) => Math.round(Math.hypot(P[a][3] - P[b][3], P[a][4] - P[b][4]) * c.evento.escala_m_px * 10) / 10;

  function rota(perfil, origem, destinos) {
    const [, , evita, pr, pl] = perfis.find(p => p[0] === perfil);
    const d = {}, prev = {}, vis = new Set();
    c.pontos.forEach(p => (d[p[0]] = Infinity));
    d[origem] = 0;
    for (;;) {
      let u = null;
      for (const k in d) if (!vis.has(k) && d[k] < (u ? d[u] : Infinity)) u = k;
      if (!u) break;
      vis.add(u);
      for (const [a, b, , esc, r, l] of c.trechos) {
        if (a !== u && b !== u) continue;
        const v = a === u ? b : a;
        if (evita === 'S' && esc === 'S') continue;
        const cst = d[u] + dist(a, b) * (1 + (r - 1) * pr / 10 + (l - 1) * pl / 10);
        if (cst < d[v]) { d[v] = cst; prev[v] = u; }
      }
    }
    const alvo = destinos.filter(x => d[x] < Infinity).sort((x, y) => d[x] - d[y])[0];
    if (!alvo) return 'SEM ROTA';
    const cam = [];
    for (let k = alvo; k; k = prev[k]) cam.unshift(k);
    return `${Math.round(d[alvo])}  ${cam.join(' > ')}`;
  }

  if (process.argv.includes('--sql')) {
    const q = s => (s === null || s === undefined ? 'NULL' : `'${String(s).replace(/'/g, "''")}'`);
    const cod = c.evento.codigo;
    const ev = `(SELECT id FROM ac_evento WHERE codigo='${cod}')`;
    const pid = k => `(SELECT id FROM ac_ponto WHERE evento_id=${ev} AND codigo=${q(k)})`;
    const e = c.evento;
    const L = [];
    L.push(`-- GERADO por db/seed/${c.arquivo} — não edite à mão. Cenário ILUSTRATIVO / dados sintéticos.`);
    L.push('SET DEFINE OFF');
    L.push(`DECLARE v_ev NUMBER; BEGIN
  SELECT MAX(id) INTO v_ev FROM ac_evento WHERE codigo = '${cod}';
  IF v_ev IS NOT NULL THEN
    DELETE FROM ac_reporte WHERE evento_id = v_ev;
    DELETE FROM ac_programacao WHERE evento_id = v_ev;
    DELETE FROM ac_trecho  WHERE evento_id = v_ev;
    DELETE FROM ac_ponto   WHERE evento_id = v_ev;
    DELETE FROM ac_area    WHERE evento_id = v_ev;
    DELETE FROM ac_evento  WHERE id = v_ev;
  END IF;
  COMMIT;
END;
/`);
    L.push(`MERGE INTO ac_perfil t USING (${perfis.map(p =>
      `SELECT ${q(p[0])} codigo, ${q(p[1])} nome, ${q(p[2])} evita_escada, ${p[3]} peso_ruido, ${p[4]} peso_lotacao, ${p[5]} velocidade_ms, ${q(p[6])} descricao FROM dual`).join('\n  UNION ALL ')}) s
ON (t.codigo = s.codigo)
WHEN MATCHED THEN UPDATE SET t.nome=s.nome, t.evita_escada=s.evita_escada, t.peso_ruido=s.peso_ruido, t.peso_lotacao=s.peso_lotacao, t.velocidade_ms=s.velocidade_ms, t.descricao=s.descricao
WHEN NOT MATCHED THEN INSERT (codigo,nome,evita_escada,peso_ruido,peso_lotacao,velocidade_ms,descricao) VALUES (s.codigo,s.nome,s.evita_escada,s.peso_ruido,s.peso_lotacao,s.velocidade_ms,s.descricao);`);
    L.push(`INSERT INTO ac_evento (codigo, nome, local, largura_px, altura_px, escala_m_px, descricao, origem_padrao) VALUES (${q(cod)}, ${q(e.nome)}, ${q(e.local)}, ${e.largura_px}, ${e.altura_px}, ${e.escala_m_px}, ${q(e.descricao)}, ${q(e.origem_padrao)});`);
    for (const [k, n, t, x, y, w, h, cor = null, sub = null, desc = null] of c.areas)
      L.push(`INSERT INTO ac_area (evento_id,codigo,nome,tipo,x,y,largura,altura,cor,subtitulo,descricao) VALUES (${ev},${q(k)},${q(n)},${q(t)},${x},${y},${w},${h},${q(cor)},${q(sub)},${q(desc)});`);
    for (const [ponto, titulo, ini, fim, ruido = null] of c.programacao || [])
      L.push(`INSERT INTO ac_programacao (evento_id,ponto,titulo,inicio,fim,ruido_prev) VALUES (${ev},${q(ponto)},${q(titulo)},${q(ini)},${q(fim)},${ruido ?? 'NULL'});`);
    for (const [k, n, t, x, y] of c.pontos)
      L.push(`INSERT INTO ac_ponto (evento_id,codigo,nome,tipo,x,y) VALUES (${ev},${q(k)},${q(n)},${q(t)},${x},${y});`);
    for (const [a, b, via, esc, r, l] of c.trechos)
      L.push(`INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,via,distancia,tem_escada,acessivel,ruido,lotacao,ruido_base,lotacao_base) VALUES (${ev},${pid(a)},${pid(b)},${q(via)},${dist(a, b)},${q(esc)},${q(esc === 'S' ? 'N' : 'S')},${r},${l},${r},${l});`);
    L.push('COMMIT;');
    const out = resolve(dirname(fileURLToPath(importMetaUrl)), `../../sql/${c.sql}`);
    writeFileSync(out, L.join('\n') + '\n');
    console.log('gerado', out);
  } else {
    const saidas = c.pontos.filter(p => p[2] === 'SAIDA').map(p => p[0]);
    for (const [o, dst] of c.testes) {
      console.log(`== ${o} -> ${dst}`);
      const alvos = dst === 'SAIDA' ? saidas : [dst];
      perfis.forEach(p => console.log(p[0].padEnd(16), rota(p[0], o, alvos)));
    }
  }
}
