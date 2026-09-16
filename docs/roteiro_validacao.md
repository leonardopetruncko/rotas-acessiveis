# Roteiro de validação com usuários — Rotas Acessíveis

Objetivo: gerar **evidência de validação** (critério 5 do Tech4Change) medindo se o app ajuda pessoas reais a se
orientar num evento, e coletar **como elas perguntam** para treinar a assistente.

Ferramenta: `#/validacao?evento=NEXT26` (cronômetro, questionário, dados no Oracle) · resultados em `#/organizador`.

---

## 1. Quem recrutar (5 a 8 pessoas já dão evidência)

| Perfil | Quantas | Onde encontrar |
|---|---|---|
| Usa cadeira de rodas ou carrinho de bebê | 1–2 | colegas, família, grupos de acessibilidade da faculdade |
| Mobilidade reduzida (muleta, idoso, gestante) | 1–2 | família, vizinhos |
| Autista / TDAH / sensível a barulho (ou mãe/pai de criança autista) | 1–2 | grupos de pais, coletivos neurodivergentes |
| Sem restrição (grupo de comparação) | 1–2 | colegas |
| Organizador de evento / produtor / segurança de evento | 1 | entrevista, não faz as tarefas (ver seção 6) |

Evite testar só com a equipe do projeto: quem construiu sabe onde está tudo.

## 2. Antes de começar (5 min)

1. Abra `#/validacao` num notebook (mediador) e tenha um celular para o participante.
2. Leia o **termo de participação** da tela em voz alta. Só marque o consentimento se a pessoa concordar.
3. Use **apelido** (ex.: "Participante 03"). Nunca nome, foto de rosto ou contato.
4. Se for gravar vídeo para o pitch, peça autorização **separada**, por escrito, e filme mãos/tela, não o rosto, a menos que a pessoa queira aparecer.
5. Clique **Resetar cenário** no modo apresentação do app para todos começarem nas mesmas condições.

## 3. Tarefas (já cadastradas no banco)

| Código | Tarefa | O que mede |
|---|---|---|
| T1 | Está no Stand Oracle, barulho insuportável: encontre um lugar calmo | rota sensorial |
| T2 | Cadeirante no Stand AWS: chegue ao banheiro adaptado sem degraus | rota sem barreiras |
| T3 | Alarme tocou, está na Arena de muletas: por qual saída sair? | saída de emergência por perfil |
| T4 | Descubra o que está acontecendo agora e onde fica | conversa com a assistente |

Cada tarefa é feita **sem o app** (planta impressa, `#/planta`) e **com o app**. A tela alterna a ordem entre participantes
(pares começam com o app, ímpares sem) para que "aprender o mapa na 1ª vez" não favoreça nenhum lado.

## 4. Durante a tarefa

- Leia a tarefa e toque **Começar** (abre a planta ou o app já na origem e no perfil certos).
- **Não ajude.** Se a pessoa travar por mais de 3 minutos, encerre e marque "não concluiu".
- Toque **Terminou** quando a pessoa disser a resposta ou apontar o destino.
- Pergunte e registre:
  - **Confiança** (1–5): "quão seguro você ficou de que estava no caminho certo?"
  - **Facilidade** (1–5)
  - **Frase**: "se você fosse pedir ajuda pra isso, o que escreveria ou falaria?" — anote **exatamente** como a pessoa falou.
  - Comentário livre (o que confundiu, o que gostou).

## 5. Depois do teste (2 min)

Perguntas abertas (anote no comentário da última tarefa):
1. "Você usaria isso num evento? Em qual?"
2. "O que faltou pra você se sentir seguro(a)?"
3. "Você sentiu que o app decidiu por você ou que você decidiu?" ← evidência direta do tema

## 6. Entrevista com organizador (15 min)

1. "Como vocês tratam hoje acessibilidade e evacuação para PcD?"
2. "Quem é cobrado quando algo dá errado?" (responsabilidade, legislação)
3. Mostre `#/organizador`: mapa de lotação, reportes, **Acionar evacuação**, decisões do público.
4. "Isso substituiria ou complementaria o quê? Quanto vale por evento?"
5. Peça, se possível, uma **carta de intenção** ("temos interesse em pilotar no evento X").

## 7. Treinar a assistente com as frases coletadas

As frases ficam em `ac_val_execucao.frase`. Para cada uma, no `#/organizador` → **Ensinar a assistente**,
ou via API `POST /eventos/NEXT26/treino/ensinar` com o rótulo correto. Meça antes e depois:

```bash
node db/avaliacao/avaliar_conversa.mjs antes_frases_reais
# ensinar as frases reais
node db/avaliacao/avaliar_conversa.mjs depois_frases_reais
```

O ideal é montar um **novo conjunto de avaliação só com frases de usuários reais** (que nunca foram ensinadas) —
esse é o número mais honesto para o pitch.

## 8. Como apresentar no pitch

- "Testamos com **N pessoas** (X cadeirantes, Y neurodivergentes…)."
- "Para achar um lugar calmo, o tempo médio caiu de **A s** (planta) para **B s** (app), e a confiança subiu de **C** para **D**."
- "**Z%** das pessoas seguiram a rota sugerida; as demais escolheram outra — a decisão é delas."
- Uma frase real de participante (com autorização).
- Com poucas pessoas, apresente como **evidência inicial**, não como estatística conclusiva.
