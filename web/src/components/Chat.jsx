import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';
import { conversaLocal } from '../lib/conversaLocal.js';
import { calar, falar, ouvir, podeFalar, podeOuvir } from '../lib/voz.js';
import { simplificar } from '../lib/acessibilidade.js';

const METODO = {
  VECTOR_SEARCH: '🧠 Vector Search no Oracle',
  REGRA_SEGURANCA: '🛡️ Regra de segurança',
  PALAVRA_CHAVE: '🔤 Palavra-chave',
  REGRAS_LOCAIS: '📴 Offline',
};

// Conversa com a assistente do evento. Ela informa e sugere; ações só acontecem quando a pessoa toca.
export default function Chat({ ev, mapa, origem, perfil, onAcao, onContexto, onLugar, onErro, a11y = {} }) {
  const inicial = {
    de: 'ia',
    texto: `Oi! Sou a assistente do ${mapa.evento.nome}. Pergunte o que tem no evento, onde fica algum lugar, o que está acontecendo agora — ou me conte do que você precisa.`,
    sugestoes: ['Que evento é esse?', 'O que tem no evento?', 'Onde fica a praça de alimentação?'],
  };
  const [msgs, setMsgs] = useState([inicial]);
  const [texto, setTexto] = useState('');
  const [pensando, setPensando] = useState(false);
  const [ouvindo, setOuvindo] = useState(false);
  const rec = useRef(null);
  const fim = useRef(null);

  useEffect(() => { setMsgs([inicial]); }, [ev]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { fim.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); }, [msgs, pensando]);

  async function enviar(t) {
    const q = (t ?? texto).trim();
    if (!q || pensando) return;
    setTexto('');
    setMsgs(m => [...m, { de: 'eu', texto: q }]);
    setPensando(true);
    let r = null;
    try {
      r = await api.conversa(ev, { texto: q, origem, perfil });
    } catch { /* offline abaixo */ }
    if (!r || r.status === 'ERRO') r = conversaLocal(q, mapa, origem);
    setPensando(false);
    setMsgs(m => [...m, { de: 'ia', texto: r.resposta, acao: r.acao, sugestoes: r.sugestoes, explicacao: r.explicacao }]);
    if (r.contexto) onContexto?.(r.contexto);
    if (r.lugar?.codigo) onLugar?.(r.lugar.codigo);
    if (r.acao?.automatica) onAcao?.(r.acao);
    if (a11y.lerAuto) falar(a11y.simples ? simplificar(r.resposta) : r.resposta);
  }

  function microfone() {
    if (ouvindo) { rec.current?.stop(); return; }
    calar();
    setOuvindo(true);
    rec.current = ouvir({
      onTexto: (t, final) => { setTexto(t); if (final) enviar(t); },
      onFim: () => setOuvindo(false),
      onErro: () => { setOuvindo(false); onErro?.('Não consegui ouvir. Verifique a permissão do microfone.'); },
    });
  }

  const ultimaIa = [...msgs].reverse().find(m => m.de === 'ia');

  return (
    <div className="card chat">
      <div className="card-tit">💬 Assistente do evento <small>informa — você decide</small></div>
      <div className="chat-msgs" role="log" aria-live="polite">
        {msgs.map((m, i) => (
          <div key={i} className={`bolha ${m.de}`}>
            <p>{m.de === 'ia' && a11y.simples ? simplificar(m.texto) : m.texto}</p>
            {m.de === 'ia' && (m.acao || (podeFalar && i > 0)) && (
              <div className="bolha-acoes">
                {m.acao && !m.acao.automatica && (
                  <button className="btn btn-sm btn-pri" onClick={() => onAcao?.(m.acao)}>
                    {m.acao.tipo === 'SAIDA' ? '🚪' : '🧭'} {m.acao.rotulo}
                  </button>
                )}
                {podeFalar && i > 0 && <button className="btn btn-sm btn-ghost" onClick={() => falar(m.texto)} aria-label="Ouvir resposta">🔊</button>}
              </div>
            )}
            {m.explicacao?.metodo && (
              <small className="explica">
                {METODO[m.explicacao.metodo] || m.explicacao.metodo}
                {m.explicacao.confianca != null && ` · confiança ${Math.round(m.explicacao.confianca * 100)}%`}
                {m.explicacao.frase_parecida && ` · parecido com “${m.explicacao.frase_parecida}”`}
              </small>
            )}
          </div>
        ))}
        {pensando && <div className="bolha ia digitando"><span /><span /><span /></div>}
        <div ref={fim} />
      </div>
      {!pensando && ultimaIa?.sugestoes?.length > 0 && (
        <div className="chips">
          {ultimaIa.sugestoes.map(s => <button key={s} className="chip" onClick={() => enviar(s)}>{s}</button>)}
        </div>
      )}
      <form className="pergunta" onSubmit={e => { e.preventDefault(); enviar(); }}>
        <input id="chat-texto" value={texto} onChange={e => setTexto(e.target.value)}
          placeholder={ouvindo ? 'Ouvindo…' : 'Pergunte qualquer coisa sobre o evento'} aria-label="Mensagem para a assistente" />
        {podeOuvir && <button type="button" className={`btn-icone ${ouvindo ? 'gravando' : ''}`} onClick={microfone} aria-label="Falar">🎤</button>}
        <button className="btn-icone btn-pri" aria-label="Enviar" disabled={pensando}>➤</button>
      </form>
    </div>
  );
}
