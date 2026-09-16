# Perguntas prováveis da banca / professor — e respostas

Respostas curtas, com os números medidos no projeto. Onde o dado ainda não existe, está marcado como **(a confirmar)**.

---

## Tema: "IA potencializando o ser humano"

**A IA decide o caminho pela pessoa?**
Não. Ela sugere, explica o motivo ("evita degraus", "foge do palco barulhento") e mostra alternativas. Nada acontece sem
toque da pessoa. A única ação automática é em alerta explícito de fogo/fumaça/alarme ou evacuação acionada pelo
organizador — e mesmo assim a pessoa vê as outras saídas. Medimos isso: cada "Vou seguir" ou "Ver outras opções" é
registrado (`ac_decisao`) e aparece no painel como % que seguiu a sugestão.

**Onde está a IA de verdade?**
1. Modelo de embedding ONNX (`all_MiniLM_L12_v2`) rodando **dentro** do Oracle Autonomous 26ai.
2. AI Vector Search para entender perguntas por significado (k-NN sobre ~250 frases de intenção e ~80 de FAQ).
3. O motor de rotas é um algoritmo clássico (Dijkstra ponderado por perfil) — de propósito: regra de segurança tem que ser auditável.

**Por que não usar um ChatGPT/LLM generativo?**
Em evento e emergência, **resposta inventada é perigosa**. Nossas respostas são montadas com dados reais do banco
(planta, programação, lotação ao vivo). O próximo passo é Select AI com modelo generativo da OCI só para reescrever a
resposta de forma mais natural — sempre sobre os dados do banco e com as mesmas travas de segurança.

**Isso não substitui funcionário do evento?**
Não. A assistente responde o repetitivo (onde fica, que horas é, tem rampa) e encaminha o que é humano: brigada,
criança perdida, mal-estar. O painel ajuda a equipe a saber onde agir. "A tecnologia encontra; uma pessoa acolhe."

## Técnica

**Qual a precisão da assistente?**
Conjunto de 60 perguntas escritas antes do treino (`db/avaliacao/conversa_holdout.json`):
- Antes do treino: **35%**
- Depois do treino (FAQ + mais exemplos): **80%**
- Depois de ajustes de desempate: **93%**, **0 alarmes falsos de emergência**

Limitação honesta: o mesmo time escreveu o conjunto e os ajustes olharam os erros — os 93% não são uma medida
independente. A medida independente vem das frases de usuários reais coletadas no kit de validação.

**E se a pessoa escrever algo que a IA não entende?**
Ela diz que não entendeu e sugere perguntas. A frase vai para "Ensinar a assistente" no painel do organizador; um
humano escolhe a resposta certa e a frase vira exemplo vetorizado na hora. Testado: "tem sorvete aqui?" ensinado
como comida → "vende sorvete?" passou a funcionar.

**Como evita alarme falso de emergência?**
Três camadas: (1) regra explícita (fogo, fumaça, alarme, desmaio, criança perdida); (2) vetor só abre emergência
com confiança muito alta; (3) caso contrário, mostra as saídas e **pergunta**. Teste de regressão em
`db/avaliacao/conversa_regressao.mjs`.

**E se a internet cair?**
O site tem modo offline: cópia do mapa + motor de rotas em JavaScript **idêntico** ao PL/SQL (158 consultas
comparadas, 100% iguais). A rota de saída continua funcionando no celular.

**Aguenta evento grande?**
Testamos 40 requisições simultâneas: todas OK em ~0,1 s. Para 50 mil pessoas, a lotação chega agregada por zona
(não por pessoa) e o Autonomous escala ECPU sob demanda. Carga real ainda **(a confirmar)** com teste de carga maior.

**Por que Oracle e não Firebase/Postgres?**
Dado, regra, IA e API no mesmo lugar: menos serviços, LGPD mais simples (texto do usuário não sai do banco para
gerar embedding), PL/SQL auditável e ORDS nativo para a API.

**Como a planta entra no sistema?**
Hoje: cadastro dos pontos/corredores (seed gerado por script). Roadmap: OCI Vision lendo a planta do organizador.
Cada evento é único — o modelo é o mesmo, muda a planta.

**Como sabem a lotação sem sensores?**
Reportes do público e da equipe ("muito cheio", "barulho", "bloqueado"). Roadmap barato: contagem das catracas já
existentes e câmeras do local com contagem anônima. Pulseira eletrônica fica como add-on, não produto base.

## Privacidade e ética (LGPD)

**Vocês rastreiam as pessoas?**
Não. Localização só é usada quando a pessoa informa onde está ou escaneia um QR. Perguntas são registradas sem
identificação, para melhorar a IA. No teste com usuários, participante usa apelido e dá consentimento (o banco
recusa registro sem consentimento).

**Deficiência é dado sensível. Como tratam?**
O perfil é escolhido pela pessoa, não é inferido nem obrigatório, e não fica ligado a identidade. A pessoa pode usar
"sem restrição" e ainda assim receber as informações de acessibilidade.

## Negócio

**Quem paga?**
Organizador, venue (centro de convenções) e patrocinador. Acessibilidade é exigência legal (Lei Brasileira de
Inclusão, 13.146/2015) e o organizador é responsabilizado por evacuação. Vendemos: rotas por perfil + saída segura
+ painel de lotação + relatório pós-evento.

**Quanto custa operar?**
Sem hardware obrigatório: QR impresso nos totens, site sem instalação, banco gerenciado. Preço por evento e custo
por evento **(a confirmar — montar planilha com preço do Autonomous e mapeamento da planta)**.

**Quem são os concorrentes?**
Apps de evento (agenda/mapa estático) e soluções de acessibilidade genéricas. Diferencial: rota **por perfil**
(corpo e sensorial), saída de emergência personalizada, tempo real por reportes e a IA dentro do banco.

**Por que alguém usaria em vez de perguntar a um segurança?**
Pessoa autista em crise muitas vezes não consegue interagir; cadeirante quer autonomia; em evacuação não há
segurança suficiente para todos. E o app aponta o segurança/brigada mais próximo quando é preciso.

## Validação

**Vocês testaram com usuários reais?**
Kit pronto em `#/validacao` (termo LGPD, tarefas cronometradas com e sem app, questionário). Resultados: **(preencher
após os testes: N participantes, tempo médio sem/com app, confiança, % concluiu)**. Validação com mentora FIAP:
proposta avaliada como uma das mais fortes que ela recebeu.
