# Rotas Acessíveis — cada pessoa, a sua rota

> Tech4Change 2026 (FIAP) · Tema: *Potencializando o ser humano com Inteligência Artificial*

## 1. Descrição da solução

Mapa 3D de eventos (feiras, congressos, shows) que calcula **a melhor rota para cada pessoa** de acordo com o
perfil de deslocamento — cadeirante, mobilidade reduzida, neurodivergente/sensível a estímulos ou sem restrição.

- Evita **escadas e degraus** para quem não pode usá-los; evita **barulho e aglomeração** para quem sofre com eles.
- **Saída de emergência por perfil**: sugere a saída viável para a pessoa e mostra as alternativas e as interditadas.
- **Tempo real**: público e equipe reportam *cheio / barulho / bloqueado* e as rotas são recalculadas no banco.
- **Chat com a assistente do evento**: responde "que evento é esse", "o que tem aqui", "onde fica a praça de alimentação",
  "o que está acontecendo agora", "onde está cheio", "quais as saídas" com dados ao vivo do banco e oferece "Traçar rota".
- **Entendimento de pedidos**: "estou no stand da Oracle, o barulho está insuportável" → perfil, origem,
  destino e rota. A interpretação é feita **dentro do Oracle** com modelo **ONNX de embedding** + **AI Vector Search**.
- **Princípio de design:** a IA **informa e explica**; **quem decide é a pessoa** (botões "Vou seguir esta rota" /
  "Ver outras opções", perfil sugerido sempre editável).
- **Perguntas frequentes do evento** (Wi-Fi, achados e perdidos, Libras, cão-guia, criança perdida, "você decide por mim?",
  "meus dados ficam salvos?") respondidas por Vector Search sobre a base de FAQ do organizador.
- **Painel do organizador**: lotação ao vivo, reportes, **Acionar evacuação** (todos os celulares entram no modo saída segura),
  % de pessoas que seguiram a sugestão e **"Ensinar a assistente"** (curadoria humana das perguntas não entendidas).
- **Acessibilidade do próprio app**: alto contraste, letra maior, linguagem simples, leitura automática em voz alta, menos movimento.
- **Kit de validação com usuários**: termo LGPD, tarefas cronometradas com e sem o app, questionário e coleta das frases reais.
- **Modo offline**: se a rede não alcança o Oracle, o site continua funcionando com uma cópia do mapa e um motor
  local idêntico ao do banco (validado em 158 consultas).

Cenários de demonstração (dados **sintéticos**, plantas ilustrativas): `NEXT26` (FIAP NEXT 2026) e `EXPO26`.

## 2. Tecnologias, linguagens e frameworks

| Camada | Tecnologia |
|---|---|
| Banco de dados | **Oracle Autonomous AI Database 26ai** (OCI, região São Paulo) |
| IA in-database | **ONNX Runtime no Oracle** (`DBMS_VECTOR.LOAD_ONNX_MODEL_CLOUD`), **AI Vector Search** (`VECTOR`, `VECTOR_EMBEDDING`, `VECTOR_DISTANCE`) |
| Lógica de negócio | **PL/SQL** (packages `AC_ROTAS`, `AC_ASSISTENTE`, `AC_CONVERSA`, `AC_OPERACAO`), SQL/JSON (`JSON_OBJECT`, `JSON_ARRAYAGG`, `JSON_OBJECT_T`) |
| API | **Oracle REST Data Services (ORDS)** embutido no Autonomous — módulo `rotas.v1` |
| Front-end | **React 19** + **Vite 8**, **three.js** / **@react-three/fiber** / **@react-three/drei** (mapa 3D), `qrcode` |
| Voz | Web Speech API do navegador (reconhecimento e síntese pt-BR) |
| Hospedagem da demo | GitHub Pages (site estático) |
| Ferramentas | Node.js 22 (scripts de carga, simulação e validação), Git/GitHub |

## 3. Arquitetura geral

```
┌──────────────────────── Navegador (celular / PC) ────────────────────────┐
│ React + three.js  ── mapa 3D, perfis, assistente, emergência, reportes   │
│   └─ modo offline: public/dados/*.json + motorLocal.js (espelho AC_ROTAS)│
└───────────────┬──────────────────────────────────────────────────────────┘
                │ HTTPS/JSON (fetch, timeout 5s, CORS)
┌───────────────▼──────────── OCI · Autonomous AI Database 26ai ───────────┐
│ ORDS  /ords/acesso_app/api/v1/eventos/...                                 │
│   │                                                                       │
│   ├─ AC_ROTAS (PL/SQL) ── Dijkstra ponderado por perfil, rota de saída,   │
│   │                       comparação de perfis, reportes, reset           │
│   ├─ AC_CONVERSA (PL/SQL) ── chat: tipo de pergunta por vetor + resposta com dados ao vivo
│   └─ AC_ASSISTENTE (PL/SQL)                                               │
│        ├─ VECTOR_EMBEDDING(DOC_MODEL) ── modelo ONNX all_MiniLM_L12_v2    │
│        ├─ VECTOR_DISTANCE(..., COSINE) ── k-NN sobre frases de exemplo    │
│        └─ guarda-corpo de segurança + palavras-chave (busca híbrida)      │
│                                                                           │
│ Dados: AC_EVENTO · AC_AREA · AC_PONTO(+embedding) · AC_TRECHO · AC_PERFIL │
│        AC_REPORTE · AC_INTENCAO · AC_INTENCAO_FRASE(embedding VECTOR(384))│
└───────────────────────────────────────────────────────────────────────────┘
        ▲ carga única do modelo: Object Storage público da Oracle (.onnx, 127 MB)
```

- **Nenhum texto do usuário sai do banco para gerar embedding** (modelo roda in-database → LGPD por design).
- **Regra de rota auditável**: custo do trecho = `distância × (1 + (ruído−1)·peso_ruído/10 + (lotação−1)·peso_lotação/10)`;
  escada é intransponível para perfis que evitam escada; ponto/trecho bloqueado é intransponível.

## 4. APIs, modelos de IA e bases de dados

### API REST (ORDS) — base `https://<host>/ords/acesso_app/api/v1/`

| Método | Caminho | Descrição |
|---|---|---|
| GET | `eventos` | Lista de eventos |
| GET | `eventos/{evento}` | Mapa: evento, perfis, áreas, pontos, trechos (ruído/lotação atuais), reportes |
| GET | `eventos/{evento}/rota?perfil=&origem=&destino=` | Rota sugerida + instruções + alertas + explicação |
| GET | `eventos/{evento}/comparar?origem=&destino=` | Mesmo trajeto para todos os perfis |
| GET | `eventos/{evento}/saida?perfil=&origem=` | Saída mais segura + alternativas + saídas indisponíveis |
| POST | `eventos/{evento}/conversa` | `{"texto","origem","perfil"}` → resposta em linguagem natural com dados do banco, ação sugerida (rota/saída), explicação (método, confiança) |
| POST | `eventos/{evento}/assistente` | `{"texto": "..."}` → necessidade, perfil, origem, destino, confiança, frase parecida, método |
| GET | `eventos/{evento}/painel` | Painel do organizador (KPIs, corredores, reportes, decisões, perguntas para revisar, resultados do teste) |
| POST | `eventos/{evento}/evacuacao` | `{"ativa":true\|false,"mensagem","pin"}` — aciona/encerra evacuação (exige PIN) |
| POST | `eventos/{evento}/decisoes` | `{"perfil","origem","destino","modo","caminho","decisao":"SEGUIU\|OUTRA_OPCAO\|TROCOU_PERFIL"}` |
| POST | `eventos/{evento}/treino/ensinar` | `{"log_id"\|"texto","rotulo","pin"}` — frase vira exemplo vetorizado (intenção ou FAQ) |
| GET | `rotulos` | Intenções e FAQs disponíveis para ensinar |
| GET | `eventos/{evento}/validacao/tarefas` | Tarefas do teste com usuários |
| POST | `eventos/{evento}/validacao/participantes` | `{"apelido","perfil","faixa_etaria","consentimento":true}` |
| POST | `eventos/{evento}/validacao/execucoes` | `{"participante_id","tarefa","condicao":"SEM_APP\|COM_APP","segundos","concluiu","confianca","facilidade","frase"}` |
| POST | `eventos/{evento}/reportes` | `{"ponto","tipo":"CHEIO\|BARULHO\|BLOQUEIO\|LIBERADO","usuario"}` |
| POST | `eventos/{evento}/reset` | Restaura o cenário de demonstração |

### Modelo de IA

| Item | Valor |
|---|---|
| Modelo | `all_MiniLM_L12_v2` (sentence-transformers), versão ONNX pré-empacotada pela Oracle |
| Nome no banco | `DOC_MODEL` — `MINING_FUNCTION = EMBEDDING`, `ALGORITHM = ONNX`, 127 MB |
| Saída | `VECTOR(384, FLOAT32)` |
| Carga | `DBMS_VECTOR.LOAD_ONNX_MODEL_CLOUD` (download direto do Object Storage pelo banco) |
| Uso | `VECTOR_EMBEDDING(doc_model USING :texto AS data)` + `VECTOR_DISTANCE(..., COSINE)` |

**Avaliação do chat** (`AC_CONVERSA`, 60 perguntas escritas antes do treino — `db/avaliacao/conversa_holdout.json`,
rodar com `node db/avaliacao/avaliar_conversa.mjs <rodada>`):

| Rodada | Perguntas sobre o evento | Necessidades | FAQ | Total | Alarmes falsos |
|---|---|---|---|---|---|
| Antes do treino | 50% | 83% | 0% | **35%** | 1 |
| Treino (FAQ + ~110 frases novas) | 59% | 92% | 92% | **80%** | 0 |
| Ajustes de desempate* | 82% | 100% | 100% | **93%** | 0 |

\*Ajustes feitos olhando os erros da rodada anterior; o conjunto foi escrito pelo mesmo time. Medida independente:
frases de usuários reais coletadas no kit de validação (`docs/roteiro_validacao.md`).

**Avaliação do assistente de rotas** (evento NEXT26, 20 frases *não usadas* no ajuste — `db/avaliacao/assistente_holdout.sql`):

| Campo | Acerto (1ª medição) | Após ampliar vocabulário de segurança* |
|---|---|---|
| Necessidade | 55% | 75% |
| Perfil | 75% | 80% |
| Origem | 95% | 95% |
| Destino | 55% | 75% |

\*A 2ª coluna foi medida depois de ajustar regras usando esse mesmo conjunto — serve como referência, não como medida independente.

### Base de dados (schema `ACESSO_APP`)

| Tabela | Conteúdo |
|---|---|
| `AC_EVENTO` | evento, dimensões da planta, escala (m/px), origem padrão |
| `AC_AREA` | retângulos da planta (stands, palco, acolhimento…) com cor — o front desenha o 3D a partir daqui |
| `AC_PONTO` | nós do grafo (x, y, tipo, bloqueado) + `busca_texto` e `embedding VECTOR(384)` |
| `AC_TRECHO` | arestas (distância, escada, ruído, lotação, valores base, via/corredor, bloqueado) |
| `AC_PERFIL` | perfis e pesos (evita escada, peso ruído, peso lotação, velocidade) |
| `AC_REPORTE` | reportes do público/equipe (crowdsourcing) |
| `AC_INTENCAO` / `AC_INTENCAO_FRASE` | tipos de pergunta, necessidades e perfis + frases de exemplo em PT com `embedding VECTOR(384)` |
| `AC_PROGRAMACAO` | agenda por lugar (horário, ruído previsto) — ilustrativa |
| `AC_FAQ` / `AC_FAQ_PERGUNTA` | perguntas frequentes (globais ou do evento) com perguntas-exemplo vetorizadas |
| `AC_CONVERSA_LOG` | perguntas feitas ao chat, sem identificação, para curadoria e métricas |
| `AC_DECISAO` | sugestão da IA × escolha da pessoa |
| `AC_EVACUACAO` | evacuações acionadas pelo organizador |
| `AC_VAL_TAREFA` / `AC_VAL_PARTICIPANTE` / `AC_VAL_EXECUCAO` | teste com usuários (consentimento obrigatório) |
| `AC_ROTA` / `AC_ROTA_TRECHO` | legado (POC inicial em APEX, evento 1) |

## 5. Instalação e execução

### Banco (Autonomous 26ai)

1. Como **ADMIN**: `sql/00_admin_grants.sql` e habilitar REST no schema (`ORDS_ADMIN.ENABLE_SCHEMA`).
2. Copiar `.env.example` → `.env` (URL do Autonomous, usuário/senha do schema). **Nunca commitar o `.env`.**
3. Como **ACESSO_APP**, na ordem (via Database Actions ou `node db/run-sql.mjs <arquivo>`):

```bash
node db/run-sql.mjs sql/10_modelo_v2.sql          # modelo de dados v2 (idempotente)
node db/run-sql.mjs sql/16a_conversa_modelo.sql   # tabelas de descrição/programação (antes dos seeds)
node db/run-sql.mjs sql/12_pkg_ac_rotas.sql       # motor de rotas
node db/run-sql.mjs sql/11_seed_expo.sql          # cenário EXPO26
node db/run-sql.mjs sql/14_seed_next.sql          # cenário NEXT26 (FIAP NEXT)
node db/run-sql.mjs sql/13_ords_api.sql           # API REST
node db/run-sql.mjs sql/15a_onnx_modelo.sql       # carrega o modelo ONNX no banco
node db/run-sql.mjs sql/15b_vector_search.sql     # frases/lugares vetorizados  (rodar de novo após re-seed)
node db/run-sql.mjs sql/15c_pkg_ac_assistente.sql # assistente semântico + endpoint
node db/run-sql.mjs sql/16a_conversa_modelo.sql   # base de conhecimento (descrições, programação)
node db/run-sql.mjs sql/15d_treino_frases.sql     # treino: mais exemplos por intenção (depois do 15b)
node db/run-sql.mjs sql/17a_operacao_modelo.sql   # FAQ, log, decisões, evacuação, validação
node db/run-sql.mjs sql/16b_pkg_ac_conversa.sql   # chat do evento (RAG in-database) + endpoint
node db/run-sql.mjs sql/17b_pkg_ac_operacao.sql   # painel, evacuação, decisões, validação, ensinar + endpoints
node db/snapshot.mjs                              # cópia offline + prova de paridade motor local × Oracle
```

Os seeds são gerados por `db/seed/next.mjs --sql` e `db/seed/expo.mjs --sql` (a simulação sem `--sql` mostra as rotas por perfil antes de carregar).

### Site

```bash
cd web
npm install
npm run dev      # http://localhost:5173
npm run build    # site estático em web/dist
```

Telas: `#/app` (mapa + chat) · `#/organizador` (painel, evacuação, ensinar IA; PIN de demonstração `2026`) ·
`#/validacao` (teste com usuários) · `#/planta` (planta imprimível, `&aqui=ORACLE` marca "você está aqui").

Rotas úteis: `#/` (apresentação) · `#/app?evento=NEXT26&origem=ORACLE&destino=ACOLH&modo=comparar` · `#/app?evento=NEXT26&origem=ORACLE&modo=saida`.

## 6. Integrantes e contribuições

| Integrante | Contribuições |
|---|---|
| Leonardo Petruncko | Arquitetura de dados e infraestrutura OCI; Autonomous AI Database 26ai; motor de rotas em PL/SQL; carga do modelo ONNX e AI Vector Search; API ORDS |
| _(preencher)_ | _(preencher)_ |
| _(preencher)_ | _(preencher)_ |

## 7. Limitações conhecidas e próximos passos

**Limitações**
- O modelo de embedding é treinado em **inglês**; em português a busca semântica acerta menos (ver avaliação) e a
  solução depende de busca híbrida (regras de segurança + palavras-chave).
- Embeddings de `AC_PONTO` são gerados por script: após recarregar um cenário é preciso rodar `15b` de novo.
- Endpoints de escrita (`reportes`, `reset`, `decisoes`, validação) são **públicos**; evacuação e treino exigem um PIN
  simples de demonstração, não uma autenticação real. REST-Enabled SQL está
  habilitado no schema para administração.
- Ruído/lotação vêm de **reportes**; não há sensores. Reportes não decaem com o tempo.
- Plantas são **ilustrativas**; digitalização automática de planta (OCI Vision) ainda não implementada.
- Em modo offline, reportes ficam só no aparelho.

**Próximos passos (banco)**
1. Modelo de embedding **multilíngue** (convertido para ONNX com OML4Py) e ampliação das frases de exemplo.
2. **Segurança**: usuário de runtime separado do dono do schema, OAuth2 nos `POST`, desabilitar REST-Enabled SQL em produção.
3. **Re-embedding automático** (trigger/job) quando `AC_PONTO` muda; índice vetorial quando o volume crescer.
4. **Log de decisões humanas** (rota sugerida × rota escolhida) — evidência do "humano decide" e analytics para o organizador.
5. **Decaimento temporal** dos reportes e particionamento por evento/data.
6. **SQL Property Graph** (26ai) sobre `AC_PONTO`/`AC_TRECHO` para consultas de alcance e visualização do grafo.
7. Digitalização da planta com **OCI Vision** e integração com fluxo de pessoas (catracas, câmeras com contagem anônima).
