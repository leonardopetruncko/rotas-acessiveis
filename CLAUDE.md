# CLAUDE.md — Contexto do projeto (leia isto primeiro, por inteiro)

Handoff de um projeto que começou noutra sessão. O dono é o **Leonardo**
(DBA/Data Architect), competindo no hackathon **Tech4Change 2026 (FIAP)**.
Objetivo: **1º lugar** (entre ~42 grupos).

---

## 1. O que é o projeto (uma frase)

Um app de **acessibilidade e rotas para eventos**: cada pessoa (cadeirante,
mobilidade reduzida, neurodivergente) recebe a **melhor rota pra ela** dentro do
evento — sem escadas pra quem não sobe, sem barulho/multidão pra quem não aguenta.
O mapa se adapta ao ambiente em tempo real. **O humano decide; a IA informa.**

## 2. O tema do hackathon (decide metade da nota)

"**Potencializando o ser humano com Inteligência Artificial**." A tecnologia deve
AMPLIAR o humano, não substituir. Inclusão bate no centro do tema.
⚠️ Enquadre sempre a IA como quem **informa/sugere**; quem decide é a pessoa. Não
caia no "a IA resolve por você".

## 3. Critérios oficiais de avaliação (do regulamento — otimize pra estes 5)

1. Alinhamento com o tema.
2. Viabilidade técnica e mercadológica.
3. Sustentabilidade financeira e operacional (modelo de negócio).
4. Originalidade e grau de inovação.
5. **Evidências de validação com usuários/clientes.**
Metade da nota NÃO é o app: é tema + negócio + validação. Não gastar 100% no código.

## 4. Datas (crítico)

- **20/09 (até 23:59):** entregar um PDF com link de um **vídeo de pitch de até 5
  min** no YouTube. O vídeo deve conter: **dor, solução, modelo de negócio,
  validação da dor/solução.** (Este é o 1º entregável — NÃO precisa de app perfeito.)
- 28/09 Top 10 · 06/10 banca Top 3 (ao vivo) · 24/10 final presencial no NEXT (SP).
- Prêmio 1º lugar: ingressos SXSW 2027.

## 5. Validação já conquistada (usar no pitch!)

- Mentoria com a mentora **Ana** (Ciência de Dados/IA): disse que é **a proposta
  mais legal que ela viu** entre as que a procuraram, e que temos **grandes chances
  de top 10**. Pesquisa de mercado validada como "incrível".
- Premissa validada: **cada ambiente é único → a solução é personalizada por
  evento** (destacar isso no pitch).

## 6. Definição do produto (MVP e futuro) — orientação da mentora

- **Foco do MVP: ROTAS DE SAÍDA / evacuação e rotas seguras** (é o recorte de maior
  impacto e o mais defensável). Priorizar isso.
- **Tecnologia base:** o sistema **recebe sempre um mapa novo do evento**, e usa
  **OCI Vision** pra analisar a imagem da planta e extrair os pontos/áreas.
- **Evolução (roadmap):** monitorar **concentração de pessoas em tempo real**
  (fluxo/lotação). Na Europa usam RFID no crachá + sensores — citar como roadmap,
  NÃO construir (é hardware, fora de escopo).

## 7. VIRADA DE STACK (o que muda agora)

Vamos migrar de "app APEX" para um **site em React**, mais bonito, fácil de
integrar e de projetar dentro de eventos fechados, mostrando um **percurso**.
- **Frontend:** React (site próprio). Visual caprichado, mobile-friendly (a pessoa
  usa no celular). Tela de mapa com a planta de fundo + pontos + rota desenhada
  (SVG por cima da imagem).
- **Backend/dados:** **Oracle Autonomous Database (Always Free serve)** — só o
  banco. Guarda o grafo do evento (pontos, trechos com atributos de acessibilidade
  e ruído/lotação) e o fluxo simulado.
- **Integração:** o React consome o banco via **ORDS (REST)** do Autonomous — expor
  as consultas de rota como endpoints REST e o React chama por fetch.
- **IA:** OCI Vision (ler a planta) como diferencial; a "consulta em linguagem
  natural" pode ser um assistente que INFORMA a rota (a pessoa decide seguir).

## 8. Lógica que já foi construída e validada (reaproveitar)

Rodou e funcionou no Autonomous 26ai (schema ACESSO_APP / workspace ACESSIBILIDADE):
- Grafo: `ac_ponto` (nós: entrada, rampa, escada, banheiro adaptado, sala de
  acolhimento, palco, stands, cruzamentos; com x,y na planta) e `ac_trecho`
  (arestas: distancia, tem_escada, acessivel, ruido 1-5, lotacao 1-5).
- `ac_perfil`: CADEIRANTE (evita escada), NEURODIVERGENTE (penaliza ruído/lotação),
  MOBILIDADE, PADRAO — cada um com pesos.
- `ac_calcular_rota(evento, perfil, origem, destino)`: **Dijkstra ponderado por
  perfil** (PL/SQL). VALIDADO: 3 perfis → 3 rotas diferentes (cadeirante desvia da
  escada; neurodivergente foge do palco barulhento).
- `ac_reportar(ponto, tipo, usuario)` (crowdsourcing): sobe ruído/lotação nos
  trechos vizinhos e recalcula a rota → simula o "tempo real".
- Custo do trecho = distancia + ruido*peso_ruido + lotacao*peso_lotacao; escada
  bloqueada se o perfil evita escada.
- Planta do evento gerada por IA (imagem PNG 1385x1136) usada como fundo do mapa.
- Os SQLs completos estão nos arquivos do projeto (pasta sql/ — poc + crowdsourcing).

> Importante: a rota hoje vai reta entre pontos (atravessa parede). Para ficar
> realista, adicionar pontos de corredor/canto e ligar só vizinhos com caminho
> livre. Priorizar isso só na rota da demo, não no mapa todo.

## 9. Plano de validação para o pitch (sem evento real)

Cenário fechado: pegar a planta de um pavilhão conhecido (ex.: São Paulo Expo),
definir palco e "Sala de Acolhimento". Gravar a jornada em vídeo:
- Cena 1: celular — usuário diz "estou no estande X, o barulho está insuportável,
  preciso ir pra sala de descompressão".
- Cena 2: o sistema consulta o banco (fluxo/lotação) + a planta.
- Cena 3: responde em segundos "o corredor principal está lotado; siga a rota azul
  à direita, livre e silenciosa" + mostra o mapa/rota.
Mostrar a interface Oracle no vídeo é um bônus com os jurados.

## 10. Modelo de negócio (para o pitch)

Quem paga: organizador de evento / venue / patrocinador / poder público (acessibilidade
é exigência legal). Vende-se "inclusão + segurança (rotas de saída) + analytics de
fluxo". Personalizado por evento = receita recorrente por evento.

## 11. Como o Leonardo trabalha

Paste-ready, português BR informal, direto. Pouca explicação salvo troubleshooting.
Entregas completas. Ele é DBA — SQL/PL-SQL real, sem simplificar demais. Já tem
Autonomous no ar (workload APEX, região SP). O workload APEX **não** permite
conexão externa por wallet/TLS — então, para o React consumir o banco, usar **ORDS
REST**, não conexão direta de driver.

## 12. Próximos passos sugeridos (ordem)

1. Scaffold do site React (Vite), tema escuro, mobile-first.
2. Página Home (hero + dor + solução) — vira metade do vídeo.
3. Tela do mapa: planta de fundo + pontos + rota (SVG); seletor de perfil, origem,
   destino; botão de reportar (crowdsourcing).
4. Expor via ORDS as consultas de rota do Autonomous; React consome por REST.
5. (Diferencial) OCI Vision lendo uma planta nova → gera pontos.
6. Gravar o vídeo de 5 min no cenário São Paulo Expo.
