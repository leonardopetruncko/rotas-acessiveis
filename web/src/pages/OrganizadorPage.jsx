import { useCallback, useEffect, useMemo, useState } from 'react';
import Mapa3D from '../components/Mapa3D.jsx';
import { api, lerParams } from '../api.js';
import { NIVEL, NIVEL_TXT } from '../lib/tema.js';

const TIPO_REPORTE = { CHEIO: '👥 Cheio', BARULHO: '🔊 Barulho', BLOQUEIO: '⛔ Bloqueio', LIBERADO: '✅ Normalizou' };

function lerPin() {
  try { return sessionStorage.getItem('rotas-pin') || ''; } catch { return ''; }
}

// Painel de quem organiza o evento: lotação ao vivo, evacuação, decisões das pessoas e curadoria da IA.
export default function OrganizadorPage() {
  const ev = useMemo(() => (lerParams().get('evento') || 'NEXT26').toUpperCase(), []);
  const [painel, setPainel] = useState(null);
  const [mapa, setMapa] = useState(null);
  const [rotulos, setRotulos] = useState([]);
  const [pin, setPin] = useState(lerPin);
  const [msgEvac, setMsgEvac] = useState('');
  const [aviso, setAviso] = useState(null);
  const [escolha, setEscolha] = useState({});
  const [erro, setErro] = useState(null);

  const carregar = useCallback(() => {
    api.painel(ev).then(p => { setPainel(p); setErro(null); }).catch(e => setErro(e.message));
    api.mapa(ev).then(setMapa).catch(() => {});
  }, [ev]);

  useEffect(() => {
    carregar();
    api.rotulos().then(r => setRotulos(r.rotulos)).catch(() => {});
    const id = setInterval(() => { if (!document.hidden) carregar(); }, 5000);
    return () => clearInterval(id);
  }, [carregar]);

  useEffect(() => { try { sessionStorage.setItem('rotas-pin', pin); } catch { /* ok */ } }, [pin]);
  useEffect(() => { if (!aviso) return; const t = setTimeout(() => setAviso(null), 5000); return () => clearTimeout(t); }, [aviso]);

  const evacuar = async ativa => {
    try {
      const r = await api.evacuacao(ev, { ativa, mensagem: msgEvac || null, pin });
      setAviso({ txt: r.mensagem, tipo: 'ok' });
      carregar();
    } catch (e) { setAviso({ txt: e.message, tipo: 'erro' }); }
  };

  const ensinar = async (item, rotulo) => {
    try {
      const r = await api.ensinar(ev, { log_id: item.id, rotulo, pin });
      setAviso({ txt: r.mensagem, tipo: 'ok' });
      carregar();
    } catch (e) { setAviso({ txt: e.message, tipo: 'erro' }); }
  };

  if (erro && !painel) return <div className="tela-cheia"><p>😕 {erro}</p><a className="btn" href="#/">Voltar</a></div>;
  if (!painel) return <div className="tela-cheia"><div className="loader" /><p>Carregando painel…</p></div>;

  const k = painel.kpis;
  const evacAtiva = painel.evacuacao?.ativa === 'S';
  const val = painel.validacao || [];
  const tarefasVal = [...new Set(val.map(v => v.tarefa))];

  return (
    <div className="pagina org">
      <header className="pag-topo">
        <a href={`#/app?evento=${ev}`} className="marca">🧭 <span>Rotas Acessíveis</span></a>
        <div>
          <h1>Painel do organizador</h1>
          <p className="muted small">{mapa?.evento?.nome || ev} · atualizado às {painel.gerado_em} · a cada 5 s</p>
        </div>
        <label className="pin">
          <span>PIN</span>
          <input id="org-pin" type="password" inputMode="numeric" value={pin} onChange={e => setPin(e.target.value)} placeholder="PIN do organizador" />
        </label>
      </header>

      {evacAtiva && <div className="faixa-evacuacao estatica" role="alert">🚨 Evacuação em andamento desde {painel.evacuacao.desde}{painel.evacuacao.mensagem ? ` — ${painel.evacuacao.mensagem}` : ''}</div>}

      <section className="kpis">
        <div className="kpi"><b>{k.corredores_criticos}</b><span>corredores críticos agora</span></div>
        <div className="kpi"><b>{k.reportes_30min}</b><span>reportes nos últimos 30 min</span></div>
        <div className="kpi"><b>{k.pontos_bloqueados}</b><span>pontos interditados</span></div>
        <div className="kpi"><b>{k.conversas}</b><span>perguntas à assistente</span><small>{k.taxa_entendimento ?? '—'}% entendidas</small></div>
        <div className="kpi"><b>{k.pct_seguiu ?? '—'}{k.pct_seguiu != null ? '%' : ''}</b><span>seguiram a rota sugerida</span><small>{k.decisoes} decisões registradas</small></div>
        <div className="kpi"><b>{k.participantes_teste}</b><span>participantes no teste</span><small>{painel.frases_coletadas} frases coletadas</small></div>
      </section>

      <div className="org-grid">
        <section className="card org-mapa">
          <div className="card-tit">Mapa de lotação ao vivo</div>
          <div className="org-mapa-3d">
            {mapa && <Mapa3D mapa={mapa} camada="lotacao" modo2D interativo={false} emergencia={evacAtiva} />}
          </div>
        </section>

        <section className={`card evac ${evacAtiva ? 'on' : ''}`}>
          <div className="card-tit">🚨 Evacuação</div>
          <p className="muted small">Ao acionar, todos os celulares com o app entram no modo saída segura em até 6 s, cada um com a saída viável para o seu perfil.</p>
          <label className="campo">
            <span>Mensagem para o público (opcional)</span>
            <input id="evac-msg" value={msgEvac} onChange={e => setMsgEvac(e.target.value)} placeholder="Ex.: fumaça na área técnica" />
          </label>
          {evacAtiva
            ? <button className="btn" onClick={() => evacuar(false)}>✓ Encerrar evacuação</button>
            : <button className="btn btn-red" onClick={() => evacuar(true)} disabled={!pin}>Acionar evacuação</button>}
          {!pin && <small className="muted">Informe o PIN do organizador no topo.</small>}
        </section>

        <section className="card">
          <div className="card-tit">Corredores agora</div>
          <div className="tabela-barras">
            {(painel.corredores || []).map(c => (
              <div key={c.via} className="linha-barra">
                <span className="nome">{c.bloqueado === 'S' ? '⛔ ' : ''}{c.via}</span>
                <span className="barras">
                  <i style={{ width: `${c.lotacao * 20}%`, background: NIVEL[c.lotacao] }} title={`Lotação ${c.lotacao}/5`} />
                  <i style={{ width: `${c.ruido * 20}%`, background: NIVEL[c.ruido] }} className="fina" title={`Ruído ${c.ruido}/5`} />
                </span>
                <small>{NIVEL_TXT[c.lotacao]}</small>
              </div>
            ))}
          </div>
          <p className="muted small">Barra grossa = lotação · barra fina = ruído</p>
        </section>

        <section className="card">
          <div className="card-tit">Reportes do público</div>
          {painel.reportes?.length ? (
            <ul className="feed">
              {painel.reportes.map((r, i) => <li key={i}>{TIPO_REPORTE[r.tipo] || r.tipo} · {r.lugar} <small>{r.em}</small></li>)}
            </ul>
          ) : <p className="muted small">Nenhum reporte ainda.</p>}
        </section>

        <section className="card org-ia">
          <div className="card-tit">🧠 Ensinar a assistente <small>curadoria humana</small></div>
          <p className="muted small">Perguntas que a IA não entendeu ou entendeu com pouca confiança. Escolha a resposta certa: a frase vira exemplo no Vector Search e perguntas parecidas passam a funcionar.</p>
          {painel.para_revisar?.length ? painel.para_revisar.map(item => (
            <div key={item.id} className="revisar">
              <div><b>“{item.texto}”</b><small>{item.em} · entendeu como {item.obtido}{item.confianca != null ? ` (${Math.round(item.confianca * 100)}%)` : ''}</small></div>
              <div className="row wrap">
                <select id={`rot-${item.id}`} value={escolha[item.id] || ''} onChange={e => setEscolha(s => ({ ...s, [item.id]: e.target.value }))}>
                  <option value="">Resposta certa…</option>
                  {rotulos.map(r => <option key={r.rotulo} value={r.rotulo}>{r.rotulo}</option>)}
                </select>
                <button className="btn btn-sm btn-pri" disabled={!escolha[item.id] || !pin} onClick={() => ensinar(item, escolha[item.id])}>Ensinar</button>
                <button className="btn btn-sm btn-ghost" disabled={!pin} onClick={() => ensinar(item, 'IGNORAR')}>Está certo</button>
              </div>
            </div>
          )) : <p className="muted small">Nada para revisar. 🎉</p>}
          {painel.intencoes?.length > 0 && (
            <>
              <div className="card-tit small">O que mais perguntam</div>
              <div className="chips">{painel.intencoes.map(i => <span key={i.rotulo} className="chip">{i.rotulo} · {i.total}</span>)}</div>
            </>
          )}
        </section>

        <section className="card">
          <div className="card-tit">A IA sugere, a pessoa decide</div>
          {painel.decisoes_por_perfil?.length ? (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Perfil</th><th className="num">Seguiu</th><th className="num">Escolheu outra</th></tr></thead>
                <tbody>{painel.decisoes_por_perfil.map(d => <tr key={d.perfil}><td>{d.perfil}</td><td className="num">{d.seguiu}</td><td className="num">{d.outra}</td></tr>)}</tbody>
              </table>
            </div>
          ) : <p className="muted small">As decisões aparecem quando o público toca em “Vou seguir esta rota” ou “Ver outras opções”.</p>}
        </section>

        <section className="card org-val">
          <div className="card-tit">🧪 Teste com usuários <a className="link-mini" href={`#/validacao?evento=${ev}`}>abrir kit</a></div>
          {tarefasVal.length ? (
            <div className="table-wrap">
              <table>
                <thead><tr><th>Tarefa</th><th>Condição</th><th className="num">n</th><th className="num">Tempo médio</th><th className="num">Confiança</th><th className="num">Concluiu</th></tr></thead>
                <tbody>
                  {val.map(v => (
                    <tr key={v.tarefa + v.condicao}>
                      <td>{v.tarefa}</td><td>{v.condicao === 'COM_APP' ? 'Com o app' : 'Sem o app'}</td><td className="num">{v.n}</td>
                      <td className="num">{v.segundos_medio}s</td><td className="num">{v.confianca_media}/5</td><td className="num">{v.pct_concluiu}%</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : <p className="muted small">Ainda não há testes registrados.</p>}
        </section>
      </div>

      {aviso && <div className={`toast toast-${aviso.tipo}`} role="status">{aviso.txt}</div>}
    </div>
  );
}
