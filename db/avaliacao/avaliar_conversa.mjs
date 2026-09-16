// Avalia o chat (POST /conversa) contra db/avaliacao/conversa_holdout.json
// node db/avaliacao/avaliar_conversa.mjs [rotulo-da-rodada]
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const base = JSON.parse(readFileSync(resolve(aqui, 'conversa_holdout.json'), 'utf8'));
const URL = 'https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1/eventos/NEXT26/conversa';
const rodada = process.argv[2] || new Date().toISOString().slice(0, 16);

const resultados = [];
for (const [texto, esperado] of base.casos) {
  let j = null;
  for (let t = 0; t < 3 && !j; t++) {
    const r = await fetch(URL, { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ texto, origem: base.origem, perfil: base.perfil, registrar: false }) });
    if (r.ok) j = await r.json();
  }
  const obtido = !j ? 'ERRO_HTTP' : j.intencao === 'FAQ' ? `FAQ:${j.faq?.chave}` : (j.intencao ?? 'NAO_ENTENDEU');
  const alarme = j?.acao?.automatica && esperado !== 'EMERGENCIA';
  resultados.push({ texto, esperado, obtido, ok: obtido === esperado, metodo: j?.explicacao?.metodo, alarme_falso: !!alarme });
}

const cat = r => (r.esperado.startsWith('FAQ:') ? 'FAQ' : r.esperado.startsWith('Q_') ? 'Pergunta' : 'Necessidade');
const grupos = {};
for (const r of resultados) (grupos[cat(r)] ||= []).push(r);
const pct = a => Math.round((a.filter(r => r.ok).length / a.length) * 100);

console.log(`\nRodada: ${rodada}`);
for (const [g, a] of Object.entries(grupos)) console.log(`  ${g.padEnd(12)} ${pct(a)}%  (${a.filter(r => r.ok).length}/${a.length})`);
console.log(`  ${'TOTAL'.padEnd(12)} ${pct(resultados)}%  (${resultados.filter(r => r.ok).length}/${resultados.length})`);
console.log(`  Alarmes falsos de emergência: ${resultados.filter(r => r.alarme_falso).length}`);
console.log('\nErros:');
for (const r of resultados.filter(r => !r.ok)) console.log(`  ✗ ${r.texto.padEnd(48)} esperado ${r.esperado.padEnd(24)} obtido ${r.obtido}`);

mkdirSync(resolve(aqui, 'resultados'), { recursive: true });
writeFileSync(resolve(aqui, 'resultados', `conversa_${rodada.replace(/[^\w-]/g, '_')}.json`),
  JSON.stringify({ rodada, por_categoria: Object.fromEntries(Object.entries(grupos).map(([g, a]) => [g, pct(a)])), total: pct(resultados), resultados }, null, 2));
