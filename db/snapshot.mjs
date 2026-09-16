// Gera web/public/dados/*.json (cópia do mapa pra modo offline) e confere se o motor local
// dá exatamente as mesmas respostas que o AC_ROTAS no Oracle.
//   node db/snapshot.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { criarMotor } from '../web/src/lib/motorLocal.js';

const BASE = 'https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1';
const out = resolve(dirname(fileURLToPath(import.meta.url)), '../web/public/dados');
mkdirSync(out, { recursive: true });

const get = async p => (await fetch(BASE + p)).json();
const { eventos } = await get('/eventos');
writeFileSync(`${out}/eventos.json`, JSON.stringify({ eventos }));

let falhas = 0;
const igual = (nome, a, b) => {
  const sa = JSON.stringify(a), sb = JSON.stringify(b);
  if (sa !== sb) {
    falhas++;
    let i = 0;
    while (sa[i] === sb[i]) i++;
    if (falhas <= 5) console.log(`✗ ${nome}\n  oracle: …${sb.slice(Math.max(0, i - 120), i + 120)}\n  local : …${sa.slice(Math.max(0, i - 120), i + 120)}`);
  }
};

for (const e of eventos) {
  await fetch(`${BASE}/eventos/${e.codigo}/reset`, { method: 'POST' });
  const mapa = await get(`/eventos/${e.codigo}`);
  mapa.reportes = [];
  writeFileSync(`${out}/${e.codigo}.json`, JSON.stringify(mapa));

  const motor = criarMotor(mapa);
  const lugares = mapa.pontos.filter(p => !['CRUZAMENTO', 'RAMPA'].includes(p.tipo)).map(p => p.codigo);
  const origens = lugares.slice(0, 8);
  const destinos = lugares.slice(-6);
  let n = 0;
  for (const o of origens) {
    for (const pf of mapa.perfis.map(p => p.codigo)) {
      igual(`${e.codigo} saida ${pf} ${o}`, motor.saida({ perfil: pf, origem: o }), await get(`/eventos/${e.codigo}/saida?perfil=${pf}&origem=${o}`));
      n++;
    }
    for (const d of destinos) {
      if (d === o) continue;
      igual(`${e.codigo} comparar ${o}->${d}`, motor.comparar({ origem: o, destino: d }), await get(`/eventos/${e.codigo}/comparar?origem=${o}&destino=${d}`));
      n++;
    }
  }
  console.log(`${e.codigo}: ${mapa.pontos.length} pontos, ${n} consultas comparadas`);
}
console.log(falhas ? `${falhas} divergência(s)` : '✓ motor local idêntico ao Oracle');
process.exit(falhas ? 1 : 0);
