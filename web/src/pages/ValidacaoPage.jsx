import { useEffect, useMemo, useRef, useState } from 'react';
import { api, lerParams } from '../api.js';
import { PERFIS_UI } from '../lib/tema.js';

const PERFIS = ['PADRAO', 'CADEIRANTE', 'MOBILIDADE', 'NEURODIVERGENTE'];

// Kit de validação: cada participante faz a mesma tarefa sem o app e com o app.
// A ordem alterna entre participantes (contrabalanceamento) para não favorecer o app.
export default function ValidacaoPage() {
  const ev = useMemo(() => (lerParams().get('evento') || 'NEXT26').toUpperCase(), []);
  const [tarefas, setTarefas] = useState([]);
  const [participante, setParticipante] = useState(null);
  const [form, setForm] = useState({ apelido: '', perfil: 'PADRAO', faixa_etaria: '', consentimento: false });
  const [erro, setErro] = useState(null);
  const [feitos, setFeitos] = useState({});

  useEffect(() => { api.tarefas(ev).then(r => setTarefas(r.tarefas)).catch(e => setErro(e.message)); }, [ev]);

  const cadastrar = async e => {
    e.preventDefault();
    setErro(null);
    try {
      const r = await api.participante(ev, form);
      setParticipante({ ...form, id: r.id });
    } catch (x) { setErro(x.message); }
  };

  const ordem = participante && participante.id % 2 === 0 ? ['COM_APP', 'SEM_APP'] : ['SEM_APP', 'COM_APP'];

  return (
    <div className="pagina val">
      <header className="pag-topo">
        <a href={`#/app?evento=${ev}`} className="marca">🧭 <span>Rotas Acessíveis</span></a>
        <div>
          <h1>Teste com usuários</h1>
          <p className="muted small">Mesma tarefa sem e com o app · tempo, confiança e a frase que a pessoa usaria · dados anônimos</p>
        </div>
        <a className="btn btn-sm btn-ghost" href={`#/organizador?evento=${ev}`}>Ver resultados</a>
      </header>

      {!participante ? (
        <form className="card val-form" onSubmit={cadastrar}>
          <div className="card-tit">1. Participante</div>
          <p className="muted small">Leia o termo em voz alta antes de começar. Use um apelido — nunca o nome real.</p>
          <div className="termo">
            <b>Termo de participação (LGPD)</b>
            <p>Você vai fazer algumas tarefas num mapa de evento, com e sem um aplicativo. Vamos anotar o tempo, suas notas e a frase que você usaria para pedir ajuda.
              Não registramos seu nome, rosto nem localização real. Os dados servem apenas para avaliar e melhorar o projeto Rotas Acessíveis (Tech4Change 2026)
              e podem ser apagados a qualquer momento, é só pedir. Você pode parar quando quiser.</p>
          </div>
          <div className="grid2">
            <label className="campo"><span>Apelido</span>
              <input id="val-apelido" required value={form.apelido} onChange={e => setForm({ ...form, apelido: e.target.value })} placeholder="Ex.: Participante 03" /></label>
            <label className="campo"><span>Faixa etária</span>
              <select id="val-idade" value={form.faixa_etaria} onChange={e => setForm({ ...form, faixa_etaria: e.target.value })}>
                <option value="">Prefere não dizer</option>
                {['até 17', '18-24', '25-34', '35-44', '45-59', '60+'].map(f => <option key={f}>{f}</option>)}
              </select></label>
          </div>
          <div className="campo"><span>Como a pessoa se desloca</span>
            <div className="perfis">
              {PERFIS.map(p => (
                <button type="button" key={p} className={`perfil ${form.perfil === p ? 'on' : ''}`} style={{ '--c': PERFIS_UI[p].cor }}
                  aria-pressed={form.perfil === p} onClick={() => setForm({ ...form, perfil: p })}>
                  <span className="ico">{PERFIS_UI[p].icone}</span><b>{PERFIS_UI[p].curto}</b>
                </button>
              ))}
            </div>
          </div>
          <label className="a11y-opcao">
            <input id="val-consentimento" type="checkbox" checked={form.consentimento} onChange={e => setForm({ ...form, consentimento: e.target.checked })} />
            <span><b>A pessoa leu/ouviu o termo e concorda em participar</b></span>
          </label>
          {erro && <p className="erro">{erro}</p>}
          <button className="btn btn-pri" disabled={!form.consentimento || !form.apelido.trim()}>Começar</button>
        </form>
      ) : (
        <>
          <div className="card">
            <div className="card-tit">Participante: {participante.apelido} · {PERFIS_UI[participante.perfil].icone} {PERFIS_UI[participante.perfil].curto}</div>
            <p className="muted small">Ordem para esta pessoa: <b>{ordem.map(o => (o === 'COM_APP' ? 'com o app' : 'sem o app')).join(' → ')}</b>. Não ajude durante a tarefa; só cronometre.</p>
            <button className="btn btn-sm btn-ghost" onClick={() => { setParticipante(null); setFeitos({}); setForm({ apelido: '', perfil: 'PADRAO', faixa_etaria: '', consentimento: false }); }}>
              Próximo participante
            </button>
          </div>
          {tarefas.map(t => (
            <div key={t.codigo} className="card tarefa">
              <div className="card-tit">{t.codigo} · {t.enunciado}</div>
              <div className="grid2">
                {ordem.map(cond => (
                  <Execucao key={cond} ev={ev} tarefa={t} condicao={cond} participante={participante}
                    feito={feitos[`${t.codigo}-${cond}`]} onSalvo={() => setFeitos(f => ({ ...f, [`${t.codigo}-${cond}`]: true }))} />
                ))}
              </div>
            </div>
          ))}
        </>
      )}
    </div>
  );
}

function Execucao({ ev, tarefa, condicao, participante, feito, onSalvo }) {
  const [inicio, setInicio] = useState(null);
  const [seg, setSeg] = useState(null);
  const [agora, setAgora] = useState(0);
  const [resp, setResp] = useState({ concluiu: true, confianca: 3, facilidade: 3, comentario: '', frase: '' });
  const [erro, setErro] = useState(null);
  const timer = useRef(null);

  useEffect(() => () => clearInterval(timer.current), []);
  const comecar = () => {
    setInicio(Date.now()); setSeg(null);
    timer.current = setInterval(() => setAgora(Date.now()), 250);
    const url = condicao === 'COM_APP'
      ? `#/app?evento=${ev}&origem=${tarefa.origem || ''}&perfil=${participante.perfil}`
      : `#/planta?evento=${ev}&aqui=${tarefa.origem || ''}`;
    window.open(`${window.location.pathname}${url}`, '_blank', 'noopener');
  };
  const parar = () => { clearInterval(timer.current); setSeg(Math.round((Date.now() - inicio) / 1000)); };
  const salvar = async () => {
    setErro(null);
    try {
      await api.execucao(ev, { participante_id: participante.id, tarefa: tarefa.codigo, condicao, segundos: seg, ...resp });
      onSalvo();
    } catch (e) { setErro(e.message); }
  };

  const rotulo = condicao === 'COM_APP' ? '📱 Com o app' : '🗺️ Sem o app (planta impressa)';
  if (feito) return <div className="exec feito"><b>{rotulo}</b><p>✅ Registrado ({seg}s)</p></div>;

  return (
    <div className="exec">
      <b>{rotulo}</b>
      {inicio == null ? (
        <button className="btn btn-sm btn-pri" onClick={comecar}>▶ Começar e abrir {condicao === 'COM_APP' ? 'o app' : 'a planta'}</button>
      ) : seg == null ? (
        <>
          <div className="cronometro">{Math.round((agora - inicio) / 1000)}s</div>
          <button className="btn btn-sm" onClick={parar}>■ Terminou</button>
        </>
      ) : (
        <div className="questionario">
          <div className="cronometro">{seg}s</div>
          <label className="a11y-opcao"><input type="checkbox" checked={resp.concluiu} onChange={e => setResp({ ...resp, concluiu: e.target.checked })} /><span>Concluiu a tarefa</span></label>
          <Escala rotulo="Quão confiante ficou de que estava no caminho certo?" valor={resp.confianca} onChange={v => setResp({ ...resp, confianca: v })} />
          <Escala rotulo="Quão fácil foi?" valor={resp.facilidade} onChange={v => setResp({ ...resp, facilidade: v })} />
          <label className="campo"><span>“Como você pediria ajuda para isso?” (frase da pessoa)</span>
            <input value={resp.frase} onChange={e => setResp({ ...resp, frase: e.target.value })} placeholder="Escreva exatamente como a pessoa falou" /></label>
          <label className="campo"><span>Comentário (opcional)</span>
            <input value={resp.comentario} onChange={e => setResp({ ...resp, comentario: e.target.value })} /></label>
          {erro && <p className="erro">{erro}</p>}
          <button className="btn btn-sm btn-pri" onClick={salvar}>Salvar</button>
        </div>
      )}
    </div>
  );
}

function Escala({ rotulo, valor, onChange }) {
  return (
    <div className="escala" role="group" aria-label={rotulo}>
      <span>{rotulo}</span>
      <div className="row">
        {[1, 2, 3, 4, 5].map(n => (
          <button key={n} type="button" className={`nota ${valor === n ? 'on' : ''}`} aria-pressed={valor === n} onClick={() => onChange(n)}>{n}</button>
        ))}
      </div>
    </div>
  );
}
