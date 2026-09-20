# Marca Rotas Acessíveis

Uma bússola cuja agulha é a própria rota: sai do ponto onde a pessoa está e aponta o caminho.
Abra `preview.html` para ver tudo junto, em fundo claro e escuro e em tamanhos pequenos.

## Arquivos

| Arquivo | Quando usar |
|---|---|
| `rotas-acessiveis-simbolo.svg` · `-512.png` · `-1024.png` | símbolo sozinho, fundo transparente (slide, adesivo, marca-d'água) |
| `rotas-acessiveis-horizontal.svg` · `-800.png` · `-1600.png` | logo com o nome — use como assinatura principal |
| `rotas-acessiveis-horizontal-fundo-escuro-1600.png` | mesma versão já com o azul-escuro atrás, para onde não pode transparência |
| `rotas-acessiveis-icone-app.svg` · `-512.png` · `-1024.png` | ícone quadrado de app, avatar de rede social, favicon grande |
| `rotas-acessiveis-simbolo-mono.svg` · `-mono-512.png` | uma cor só: carimbo, impressão em preto, bordado, fundo colorido |

SVG é vetor: escala sem perder qualidade e é o que deve ir para o Figma, Illustrator ou Canva.
PNG é para colar direto em slide, WhatsApp e documento.

## Cores da marca

| Uso | Hex |
|---|---|
| Turquesa principal | `#5eead4` |
| Ciano (gradiente) | `#22d3ee` |
| Verde-água (aro) | `#2dd4bf` |
| Fundo escuro | `#070b16` |
| Fundo dos cartões | `#0d1426` / `#111a2f` |
| Borda | `#22304f` |
| Texto | `#e6ecf8` |
| Texto secundário | `#8b9bbd` |

O gradiente do símbolo vai de `#5eead4` (canto inferior esquerdo) para `#22d3ee` (canto superior direito).

### Cores dos perfis (usadas nas rotas do app)

| Perfil | Hex |
|---|---|
| Sem restrição | `#60a5fa` |
| Cadeirante | `#facc15` |
| Mobilidade reduzida | `#fb923c` |
| Neurodivergente | `#e879f9` |

### Cores de estado (lotação e ruído, de 1 a 5)

`#2fd27f` tranquilo · `#9ad13a` ok · `#f0a92e` moderado · `#f97316` alto · `#ef4444` crítico
Apoio: emergência `#f43f5e` · saída `#22c55e` · alerta `#fbbf24`

## Tipografia

O app usa a fonte do sistema (Segoe UI no Windows, San Francisco no Mac). Para peças gráficas,
qualquer sans-serif geométrica combina — **Inter** e **Poppins** (Google Fonts, gratuitas) ficam próximas.
No logo horizontal o nome é bold e a assinatura "CADA PESSOA, A SUA ROTA" é maiúscula, peso médio,
com bastante espaçamento entre letras.

## Como não usar

- Não estique nem achate: segure Shift ao redimensionar.
- Não troque as cores do símbolo por outras; se precisar de uma cor só, use a versão `mono`.
- Não coloque o símbolo colorido sobre fundo turquesa: sem contraste. Use o `mono` em branco.
- Respire: deixe em volta do logo pelo menos a largura do círculo da bússola.
- Tamanho mínimo: 24 px para o símbolo e 120 px para o horizontal. Abaixo disso, use o ícone de app.

## Para gerar os PNGs de novo

```bash
cd web
node scripts/gerar-marca.mjs
```
