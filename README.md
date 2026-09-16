# Rotas Acessíveis — Tech4Change 2026

Site React + Oracle Autonomous Database. Cada pessoa recebe a melhor rota pra ela
num evento (cadeirante evita escada; neurodivergente evita barulho/multidão),
adaptando em tempo real. Foco do MVP: rotas de saída/seguras.

**Leia o `CLAUDE.md` primeiro** — tem todo o contexto, a lógica já validada, os
critérios do hackathon e o plano.

## Stack
- React (Vite), tema escuro, mobile-first.
- Oracle Autonomous Database 26ai — grafo do evento + fluxo simulado.
- ORDS (REST) liga o React ao banco (o workload APEX não permite driver externo).
- OCI Vision (diferencial) para ler a planta do evento.

## Estrutura
- `CLAUDE.md` — contexto completo (handoff).
- `sql/` — scripts do banco (legado `poc_*`/`crowdsourcing` = evento 1 do APEX; `10+` = v2).
- `db/run-sql.mjs` — roda SQL no banco via ORDS REST-Enabled SQL (lê `.env`).
- `db/seed/lib.mjs` + `expo.mjs`/`next.mjs` — cenários; simulam rotas e geram `sql/11_seed_expo.sql` / `sql/14_seed_next.sql`.
- `web/` — site React (Vite) + mapa 3D (three.js / react-three-fiber).

## Banco
```
cp .env.example .env                           # preencher URL + senha
node db/run-sql.mjs -e "select user from dual" # testa conexão
node db/run-sql.mjs sql/10_modelo_v2.sql       # modelo v2 (aditivo)
node db/seed/expo.mjs --sql                    # (re)gera o seed
node db/run-sql.mjs sql/11_seed_expo.sql       # cenário EXPO26
node db/seed/next.mjs --sql && node db/run-sql.mjs sql/14_seed_next.sql   # FIAP NEXT (NEXT26)
node db/run-sql.mjs sql/12_pkg_ac_rotas.sql    # motor (package AC_ROTAS)
node db/run-sql.mjs sql/13_ords_api.sql        # API REST
```

## API (base `https://<host>/ords/acesso_app/api/v1/`)
| Método | Caminho | O quê |
|---|---|---|
| GET | `eventos` | lista de eventos |
| GET | `eventos/EXPO26` | mapa: evento, perfis, áreas, pontos, trechos, reportes |
| GET | `eventos/EXPO26/rota?perfil=&origem=&destino=` | rota sugerida + instruções + alertas + mensagem |
| GET | `eventos/EXPO26/comparar?origem=&destino=` | a mesma viagem para todos os perfis |
| GET | `eventos/EXPO26/saida?perfil=&origem=` | saída mais segura + alternativas + indisponíveis |
| POST | `eventos/EXPO26/reportes` | `{"ponto":"SS","tipo":"CHEIO\|BARULHO\|BLOQUEIO\|LIBERADO","usuario":"..."}` |
| POST | `eventos/EXPO26/reset` | restaura o cenário da demo |

Cenário do vídeo: `origem=EST42` (estande ao lado do palco) → `destino=ACOLH`
- PADRAO: corredor interno lotado (84 m) · CADEIRANTE: rampa leste (152 m) · NEURODIVERGENTE: degraus de serviço silenciosos (112 m)
- Saída: PADRAO → Leste (degraus) · CADEIRANTE → Sul · bloqueia `SS` → recalcula pra Norte.

## Site
```
cd web
npm install
npm run dev        # http://localhost:5173 (e o IP da rede, pra abrir no celular)
npm run build      # gera web/dist (estático: dá pra subir em Object Storage, Vercel, Netlify...)
```
- `#/` Home (pitch) · `#/app?evento=NEXT26&origem=ORACLE&destino=ACOLH&perfil=CADEIRANTE&modo=rota|comparar|saida`
- **Modo offline:** se o navegador não alcança o Oracle em 5s, o site usa `web/public/dados/*.json` e o motor local (`web/src/lib/motorLocal.js`, espelho do AC_ROTAS). Depois de mudar o banco: `node db/snapshot.mjs` (regera as cópias e confere que o motor local dá as mesmas respostas do Oracle).
- QR dos totens: botão **▦ QR** no mapa → imprime um QR por lugar (`?evento=..&origem=..#/app`).
- Roteiro NEXT26: origem `ORACLE` (ao lado do palco) → `ACOLH`. Emergência + reportar `SS` bloqueado → recalcula.
