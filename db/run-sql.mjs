// Roda SQL no Autonomous via ORDS REST-Enabled SQL (/ords/<schema>/_/sql).
// Uso:
//   node db/run-sql.mjs arquivo.sql
//   node db/run-sql.mjs -e "select user from dual"
// Credenciais vêm do .env (ORDS_BASE_URL, DB_SCHEMA_PATH, DB_USER, DB_PASSWORD).
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const envFile = resolve(root, '.env');
if (existsSync(envFile)) {
  for (const line of readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, '');
  }
}

const { ORDS_BASE_URL, DB_SCHEMA_PATH, DB_USER, DB_PASSWORD } = process.env;
for (const [k, v] of Object.entries({ ORDS_BASE_URL, DB_SCHEMA_PATH, DB_USER, DB_PASSWORD })) {
  if (!v) { console.error(`Falta ${k} no .env`); process.exit(2); }
}

const args = process.argv.slice(2);
let sql;
if (args[0] === '-e') sql = args.slice(1).join(' ');
else if (args[0]) sql = readFileSync(resolve(args[0]), 'utf8');
else { console.error('Uso: node db/run-sql.mjs <arquivo.sql> | -e "<sql>"'); process.exit(2); }

const url = `${ORDS_BASE_URL.replace(/\/$/, '')}/ords/${DB_SCHEMA_PATH}/_/sql`;
const res = await fetch(url, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/sql',
    Authorization: 'Basic ' + Buffer.from(`${DB_USER}:${DB_PASSWORD}`).toString('base64'),
  },
  body: sql,
});

const text = await res.text();
if (!res.ok) {
  console.error(`HTTP ${res.status} em ${url}\n${text.slice(0, 2000)}`);
  process.exit(1);
}

let failed = false;
for (const it of JSON.parse(text).items ?? []) {
  const head = (it.statementText ?? '').replace(/\s+/g, ' ').slice(0, 90);
  if (it.errorCode) {
    failed = true;
    const msg = it.errorMessage ?? (it.response ?? []).join(' ').trim();
    console.log(`✗ [${it.statementId}] ${head}\n  ORA-${String(it.errorCode).padStart(5, '0')}: ${msg}`);
    continue;
  }
  if (/^--/.test(head) && !it.resultSet) continue; // comentário solto
  if (it.resultSet) {
    const cols = it.resultSet.metadata.map(c => c.columnName.toLowerCase());
    console.log(`▶ [${it.statementId}] ${head}`);
    console.table(it.resultSet.items.map(r => Object.fromEntries(cols.map(c => [c, r[c]]))));
  } else {
    const msg = (it.response ?? []).join(' ').trim();
    console.log(`✓ [${it.statementId}] ${head}${msg ? `  → ${msg}` : ''}`);
  }
}
process.exit(failed ? 1 : 0);
