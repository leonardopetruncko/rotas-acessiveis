import { useState } from 'react';

const OPCOES = [
  ['contraste', 'Alto contraste', 'Cores fortes, fundo preto'],
  ['fonteGrande', 'Letra maior', 'Aumenta textos e botões'],
  ['simples', 'Linguagem simples', 'Respostas curtas e diretas'],
  ['lerAuto', 'Ler respostas em voz alta', 'A assistente fala sozinha'],
  ['semAnimacao', 'Menos movimento', 'Para animações do mapa'],
];

export default function MenuAcessibilidade({ prefs, alternar }) {
  const [aberto, setAberto] = useState(false);
  const ativas = OPCOES.filter(([k]) => prefs[k]).length;
  return (
    <div className="a11y-menu">
      <button className="btn-icone" onClick={() => setAberto(a => !a)} aria-expanded={aberto} aria-controls="a11y-painel"
        title="Opções de acessibilidade">
        ♿ Acessibilidade{ativas ? ` · ${ativas}` : ''}
      </button>
      {aberto && (
        <div id="a11y-painel" className="a11y-painel" role="group" aria-label="Opções de acessibilidade">
          {OPCOES.map(([k, rotulo, dica]) => (
            <label key={k} className="a11y-opcao">
              <input id={`a11y-${k}`} type="checkbox" checked={prefs[k]} onChange={() => alternar(k)} />
              <span><b>{rotulo}</b><small>{dica}</small></span>
            </label>
          ))}
          <button className="btn btn-sm btn-ghost" onClick={() => setAberto(false)}>Fechar</button>
        </div>
      )}
    </div>
  );
}
