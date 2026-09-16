import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import Mapa3D from '../components/Mapa3D.jsx';
import QrModal from '../components/QrModal.jsx';
import Chat from '../components/Chat.jsx';
import MenuAcessibilidade from '../components/MenuAcessibilidade.jsx';
import { useAcessibilidade } from '../lib/acessibilidade.js';
import { agendaPorPonto, agoraSP, hhmmDe, minutos } from '../components/Cenario3D.jsx';
import { api, aoMudarModo, emModoOffline, lerParams } from '../api.js';
import { falar, podeFalar } from '../lib/voz.js';
import { NIVEL, NIVEL_TXT, PERFIS_UI, TIPO_UI, ehDestino } from '../lib/tema.js';

const assinatura = m => m ? m.trechos.map(t => `${t.ruido}${t.lotacao}${t.bloqueado}`).join('') + m.pontos.map(p => p.bloqueado).join('')
  + (m.evacuacao?.ativa || '') + (m.evacuacao?.mensagem || '') : '';
const caminho = r => r?.pontos?.map(p => p.codigo).join('>') || '';

export default function MapaPage() {
  const params = useMemo(lerParams, []);
  const [eventos, setEventos] = useState([]);
  const [ev, setEv] = useState((params.get('evento') || 'NEXT26').toUpperCase());
  const [mapa, setMapa] = useState(null);
  const [erro, setErro] = useState(null);

  const [perfil, setPerfil] = useState((params.get('perfil') || 'PADRAO').toUpperCase());
  const [origem, setOrigem] = useState(params.get('origem')?.toUpperCase() || null);
  const [destino, setDestino] = useState(params.get('destino')?.toUpperCase() || null);
  const [modo, setModo] = useState(params.get('modo') || 'rota'); // rota | saida | comparar
  const [res, setRes] = useState(null);
  const [calculando, setCalculando] = useState(false);
  const [decisao, setDecisao] = useState(null); // null | 'seguir' | 'outra'
  const [preview, setPreview] = useState(null); // alternativa de saída em destaque

  const [camada, setCamada] = useState('lotacao');
  const [modo2D, setModo2D] = useState(false);
  const [selecionado, setSelecionado] = useState(null);
  const [toast, setToast] = useState(null);
  const [qr, setQr] = useState(false);
  const [offline, setOffline] = useState(emModoOffline());
  useEffect(() => aoMudarModo(setOffline), []);

  const ultimaRota = useRef({ chave: '', caminho: '' });
  const [a11y, alternarA11y] = useAcessibilidade();
  const [horaSim, setHoraSim] = useState(params.get('hora') || null); // simular horário (demo/vídeo)
  const [relogioAberto, setRelogioAberto] = useState(false);
  const [tour, setTour] = useState(false);
  const [seguir, setSeguir] = useState(false);
  const [contagem, setContagem] = useState(null);
  const [horaReal, setHoraReal] = useState(agoraSP());
  useEffect(() => { const id = setInterval(() => setHoraReal(agoraSP()), 30000); return () => clearInterval(id); }, []);
  useEffect(() => {
    const on = () => { const h = lerParams().get('hora'); if (h) setHoraSim(h); };
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  const evacuando = mapa?.evacuacao?.ativa === 'S';

  // evacuação acionada pelo organizador: todo aparelho entra no modo saída segura
  const evacAnterior = useRef(false);
  useEffect(() => {
    if (evacuando && !evacAnterior.current) {
      setModo('saida');
      falar(`Atenção. Evacuação em andamento. ${mapa.evacuacao.mensagem || ''}. Siga para a saída indicada no mapa.`);
    }
    evacAnterior.current = evacuando;
  }, [evacuando]); // eslint-disable-line react-hooks/exhaustive-deps

  // "humano decide": registra a escolha da pessoa (anônimo)
  const registrarDecisao = (tipo, extra = {}) => {
    api.decisao(ev, { perfil, origem, destino: modo === 'saida' ? res?.saida_sugerida?.codigo : destino, modo, caminho: caminho(res), decisao: tipo, ...extra });
  };

  const avisar = useCallback((txt, tipo = 'info') => {
    setToast({ txt, tipo, id: Date.now() });
  }, []);
  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 4200);
    return () => clearTimeout(t);
  }, [toast]);

  // ------------------------------------------------ dados do evento
  useEffect(() => { api.eventos().then(r => setEventos(r.eventos)).catch(() => {}); }, []);

  useEffect(() => {
    let vivo = true;
    setMapa(null); setRes(null); setErro(null);
    api.mapa(ev).then(m => {
      if (!vivo) return;
      setMapa(m);
      setOrigem(o => (o && m.pontos.some(p => p.codigo === o) ? o : m.evento.origem_padrao || m.pontos[0]?.codigo));
      setDestino(d => (d && m.pontos.some(p => p.codigo === d) ? d : null));
    }).catch(e => vivo && setErro(e.message));
    return () => { vivo = false; };
  }, [ev]);

  // "tempo real": consulta o banco a cada 6s; só re-renderiza se algo mudou
  const assin = assinatura(mapa);
  useEffect(() => {
    const id = setInterval(() => {
      if (document.hidden || emModoOffline()) return;
      api.mapa(ev).then(m => { if (assinatura(m) !== assin) setMapa(m); }).catch(() => {});
    }, 6000);
    return () => clearInterval(id);
  }, [ev, assin]);

  // ------------------------------------------------ cálculo da rota
  useEffect(() => {
    if (!mapa || !origem) return;
    if (modo !== 'saida' && !destino) { setRes(null); return; }
    let vivo = true;
    setCalculando(true);
    const chave = `${ev}|${modo}|${perfil}|${origem}|${destino}`;
    const req = modo === 'saida' ? api.saida(ev, { perfil, origem })
      : modo === 'comparar' ? api.comparar(ev, { origem, destino })
        : api.rota(ev, { perfil, origem, destino });
    req.then(r => {
      if (!vivo) return;
      const cam = modo === 'comparar' ? r.rotas.map(caminho).join('|') : caminho(r);
      const u = ultimaRota.current;
      if (u.chave === chave && u.caminho && u.caminho !== cam) {
        avisar('⚡ O ambiente mudou e a rota foi recalculada. Confira antes de seguir.', 'alerta');
        setDecisao(null);
      }
      ultimaRota.current = { chave, caminho: cam };
      setRes(r); setPreview(null);
    }).catch(e => vivo && avisar(e.message, 'erro'))
      .finally(() => vivo && setCalculando(false));
    return () => { vivo = false; };
  }, [ev, modo, perfil, origem, destino, assin, mapa, avisar]);

  useEffect(() => { setDecisao(null); }, [modo, perfil, origem, destino]);

  // ------------------------------------------------ ações
  const P = useMemo(() => Object.fromEntries((mapa?.pontos || []).map(p => [p.codigo, p])), [mapa]);
  const lugares = useMemo(() => (mapa?.pontos || []).filter(ehDestino), [mapa]);
  const porTipo = tipo => lugares.find(p => p.tipo === tipo && !/credenc/i.test(p.nome));

  const irPara = (cod, novoModo = 'rota') => { setDestino(cod); setModo(novoModo); };
  const emergencia = () => { setModo('saida'); avisar('🚨 Modo emergência: mostrando a saída mais segura para o seu perfil.', 'alerta'); };

  const acaoChat = a => {
    if (a.tipo === 'SAIDA') emergencia();
    else if (a.tipo === 'ROTA' && a.destino) irPara(a.destino, modo === 'comparar' ? 'comparar' : 'rota');
  };
  const contextoChat = c => {
    if (c.origem) setOrigem(c.origem);
    if (c.perfil) setPerfil(c.perfil);
  };

  const reportar = async tipo => {
    const alvo = selecionado || origem;
    if (!alvo) return;
    try {
      const r = await api.reportar(ev, { ponto: alvo, tipo, usuario: 'app' });
      avisar(r.mensagem, 'ok');
      setMapa(await api.mapa(ev));
    } catch (e) { avisar(e.message, 'erro'); }
  };

  const resetar = async () => {
    try {
      await api.reset(ev);
      setMapa(await api.mapa(ev));
      ultimaRota.current = { chave: '', caminho: '' };
      avisar('Cenário restaurado.', 'ok');
    } catch (e) { avisar(e.message, 'erro'); }
  };

  const clicarPonto = cod => setSelecionado(s => (s === cod ? null : cod));

  // ------------------------------------------------ rotas para o 3D
  const corPerfil = c => PERFIS_UI[c]?.cor || '#60a5fa';
  const rotas3D = useMemo(() => {
    if (!res || !mapa) return [];
    if (modo === 'comparar') return (res.rotas || []).filter(r => r.status === 'OK').map(r => ({ chave: r.perfil.codigo, pontos: r.pontos, cor: corPerfil(r.perfil.codigo) }));
    if (res.status !== 'OK') return [];
    const out = [];
    if (modo === 'saida') {
      for (const a of res.alternativas || []) {
        const pts = a.caminho.map(c => P[c]).filter(Boolean);
        if (preview === a.codigo) out.push({ chave: 'prev', pontos: pts, cor: '#94a3b8' });
        else out.push({ chave: `alt-${a.codigo}`, pontos: pts, cor: '#64748b', fraca: true });
      }
    }
    out.push({ chave: 'principal', pontos: res.pontos, cor: modo === 'saida' ? '#22c55e' : corPerfil(perfil) });
    return out;
  }, [res, modo, perfil, P, mapa, preview]);

  if (erro) return <div className="tela-cheia"><p>😕 {erro}</p><a className="btn" href="#/">Voltar</a></div>;
  if (!mapa) return <div className="tela-cheia"><div className="loader" /><p>Carregando o mapa do evento…</p></div>;

  const perfilAtual = mapa.perfis.find(p => p.codigo === perfil);
  const alvoReporte = P[selecionado || origem];
  const destinoFinal = modo === 'saida' ? res?.saida_sugerida?.codigo : destino;

  return (
    <div className={`app ${modo === 'saida' ? 'app-emergencia' : ''}`}>
      {evacuando && (
        <div className="faixa-evacuacao" role="alert">
          🚨 EVACUAÇÃO EM ANDAMENTO{mapa.evacuacao.mensagem ? ` — ${mapa.evacuacao.mensagem}` : ''}. Siga a rota verde até a saída e as orientações da brigada.
        </div>
      )}
      <section className="mapa-wrap" aria-label="Mapa 3D do evento">
        <Mapa3D mapa={mapa} rotas={rotas3D} origem={origem} destino={destinoFinal} camada={camada}
          modo2D={modo2D} emergencia={modo === 'saida'} selecionado={selecionado} calmo={a11y.semAnimacao} agora={horaSim || horaReal}
          tour={tour} seguir={seguir && rotas3D.length > 0} onContagem={setContagem}
          onPontoClick={clicarPonto} onVazio={() => setSelecionado(null)} />

        <header className="mapa-topo">
          <a href="#/" className="marca" aria-label="Início">🧭 <span>Rotas Acessíveis</span></a>
          <select className="sel-evento" value={ev} onChange={e => { setEv(e.target.value); setOrigem(null); setDestino(null); }} aria-label="Evento">
            {(eventos.length ? eventos : [{ codigo: ev, nome: mapa.evento.nome }]).map(e => <option key={e.codigo} value={e.codigo}>{e.nome}</option>)}
          </select>
          <MenuAcessibilidade prefs={a11y} alternar={alternarA11y} />
          {offline && (
            <span className="badge-offline" title="Sem conexão com o Oracle: rotas calculadas no aparelho com a última cópia do mapa. Reportes ficam só neste aparelho.">
              📴 Offline
            </span>
          )}
        </header>

        <div className="mapa-ferramentas">
          <div className="seg" role="group" aria-label="Vista">
            <button className={!modo2D ? 'on' : ''} onClick={() => setModo2D(false)}>3D</button>
            <button className={modo2D ? 'on' : ''} onClick={() => setModo2D(true)}>2D</button>
          </div>
          <div className="seg" role="group" aria-label="Camada">
            <button className={camada === 'lotacao' ? 'on' : ''} onClick={() => setCamada('lotacao')}>👥 Lotação</button>
            <button className={camada === 'ruido' ? 'on' : ''} onClick={() => setCamada('ruido')}>🔊 Ruído</button>
            <button className={!camada ? 'on' : ''} onClick={() => setCamada(null)}>Planta</button>
          </div>
          <button className={`btn-icone ${tour ? 'ligado' : ''}`} onClick={() => { setTour(t => !t); setSeguir(false); setSelecionado(null); }} title="Passeio pelo evento">🎬 {tour ? 'Parar tour' : 'Tour'}</button>
          <button className={`btn-icone ${seguir ? 'ligado' : ''}`} disabled={!rotas3D.length} onClick={() => { setSeguir(s => !s); setTour(false); setSelecionado(null); }} title="Câmera acompanha a rota">🎥 {seguir ? 'Parar' : 'Seguir rota'}</button>
          <button className="btn-icone" onClick={() => setQr(true)} title="QR codes dos totens">▦ QR</button>
        </div>

        <Relogio mapa={mapa} hora={horaSim || horaReal} simulado={!!horaSim} aberto={relogioAberto} setAberto={setRelogioAberto}
          setHora={setHoraSim} onVer={cod => setSelecionado(cod)} P={P} />

        {camada && (
          <div className="legenda">
            <span>{camada === 'lotacao' ? 'Lotação' : 'Ruído'}</span>
            {[1, 2, 3, 4, 5].map(n => <i key={n} style={{ background: NIVEL[n] }} title={NIVEL_TXT[n]} />)}
            <small>baixo → crítico · ao vivo</small>
          </div>
        )}

        {modo === 'saida' && contagem && !a11y.semAnimacao && (
          <div className="hud-evac" role="status">
            <div><b>🏃 {contagem.total - contagem.saidos}</b> ainda no pavilhão · <b>✅ {contagem.saidos}</b> já saíram</div>
            <div className="barra"><i style={{ width: `${Math.round((contagem.saidos / Math.max(1, contagem.total)) * 100)}%` }} /></div>
            <small>simulação do fluxo até as saídas</small>
          </div>
        )}

        <button className={`btn-emergencia ${modo === 'saida' ? 'on' : ''}`} onClick={() => (modo === 'saida' ? setModo('rota') : emergencia())}>
          {modo === 'saida' ? '✕ Sair do modo emergência' : '🚨 Emergência'}
        </button>

        {selecionado && P[selecionado] && (
          <div className="popover" role="dialog">
            <b>{TIPO_UI[P[selecionado].tipo]?.icone} {P[selecionado].nome}</b>
            <div className="row wrap">
              <button className="btn btn-sm" onClick={() => { setOrigem(selecionado); setSelecionado(null); }}>📍 Estou aqui</button>
              <button className="btn btn-sm btn-pri" onClick={() => { irPara(selecionado, modo === 'comparar' ? 'comparar' : 'rota'); setSelecionado(null); }}>🏁 Ir para cá</button>
              <button className="btn btn-sm btn-ghost" onClick={() => document.getElementById('reportar')?.scrollIntoView({ behavior: 'smooth' })}>⚠️ Reportar</button>
            </div>
          </div>
        )}
      </section>

      <aside className="painel">
        <Chat ev={ev} mapa={mapa} origem={origem} perfil={perfil} onAcao={acaoChat} onContexto={contextoChat} a11y={a11y}
          onLugar={cod => setSelecionado(cod)} onErro={msg => avisar(msg, 'erro')} />

        {/* perfil */}
        <div className="card">
          <div className="card-tit">Como você se desloca?</div>
          <div className="perfis">
            {mapa.perfis.map(p => (
              <button key={p.codigo} className={`perfil ${perfil === p.codigo ? 'on' : ''}`} style={{ '--c': corPerfil(p.codigo) }}
                onClick={() => setPerfil(p.codigo)} aria-pressed={perfil === p.codigo} disabled={modo === 'comparar'}>
                <span className="ico">{PERFIS_UI[p.codigo]?.icone}</span>
                <b>{PERFIS_UI[p.codigo]?.curto || p.nome}</b>
              </button>
            ))}
          </div>
          {perfilAtual?.descricao && modo !== 'comparar' && <p className="muted small">{perfilAtual.descricao}</p>}
        </div>

        {/* origem / destino */}
        <div className="card">
          <label className="campo">
            <span>📍 Onde estou</span>
            <SelectLugar lugares={lugares} value={origem || ''} onChange={setOrigem} />
          </label>
          <label className="campo">
            <span>🏁 Para onde</span>
            <SelectLugar lugares={lugares} value={modo === 'saida' ? '' : destino || ''} onChange={c => irPara(c, modo === 'comparar' ? 'comparar' : 'rota')}
              vazio={modo === 'saida' ? '🚨 Saída mais segura' : 'Escolha um destino…'} />
          </label>
          <div className="atalhos">
            {porTipo('ACOLHIMENTO') && <button className="chip" onClick={() => irPara(porTipo('ACOLHIMENTO').codigo)}>🧘 Lugar calmo</button>}
            {porTipo('BANHEIRO_ADAP') && <button className="chip" onClick={() => irPara(porTipo('BANHEIRO_ADAP').codigo)}>🚻 Banheiro acessível</button>}
            {lugares.find(p => /brigada|enfermaria/i.test(p.nome)) && <button className="chip" onClick={() => irPara(lugares.find(p => /brigada|enfermaria/i.test(p.nome)).codigo)}>🩺 Brigada</button>}
            <button className="chip chip-red" onClick={emergencia}>🚨 Saída segura</button>
          </div>
          <div className="seg seg-full">
            <button className={modo === 'rota' ? 'on' : ''} onClick={() => setModo('rota')}>Minha rota</button>
            <button className={modo === 'comparar' ? 'on' : ''} onClick={() => setModo('comparar')} disabled={!destino}>Comparar perfis</button>
            <button className={modo === 'saida' ? 'on' : ''} onClick={() => setModo('saida')}>Emergência</button>
          </div>
        </div>

        {/* resultado */}
        {calculando && !res && <div className="card"><div className="loader" /></div>}
        {res && modo !== 'comparar' && (
          <Resultado res={res} modo={modo} cor={modo === 'saida' ? '#22c55e' : corPerfil(perfil)} decisao={decisao}
            setDecisao={d => { setDecisao(d); registrarDecisao(d === 'seguir' ? 'SEGUIU' : 'OUTRA_OPCAO'); }}
            preview={preview} setPreview={setPreview} irPara={irPara} setModo={setModo} calculando={calculando} />
        )}
        {res && modo === 'comparar' && (
          <Comparacao res={res} perfil={perfil} setModo={setModo}
            setPerfil={p => { if (p !== perfil) registrarDecisao('TROCOU_PERFIL', { perfil: p }); setPerfil(p); }} />
        )}
        {!res && modo === 'rota' && !destino && (
          <div className="card vazio">Escolha um destino, toque num lugar do mapa ou fale com o assistente.</div>
        )}

        {/* reportar */}
        <div className="card" id="reportar">
          <div className="card-tit">⚠️ Algo mudou aqui? <small>vira dado pra todo mundo</small></div>
          <p className="muted small">Reportando em: <b>{alvoReporte?.nome || '—'}</b> {selecionado ? '' : '(sua localização)'}</p>
          <div className="reportes">
            <button className="btn btn-sm" onClick={() => reportar('CHEIO')}>👥 Muito cheio</button>
            <button className="btn btn-sm" onClick={() => reportar('BARULHO')}>🔊 Muito barulho</button>
            <button className="btn btn-sm btn-red" onClick={() => reportar('BLOQUEIO')}>⛔ Bloqueado</button>
            <button className="btn btn-sm btn-ghost" onClick={() => reportar('LIBERADO')}>✅ Normalizou</button>
          </div>
          {mapa.reportes?.length > 0 && (
            <ul className="feed">
              {mapa.reportes.slice(0, 4).map((r, i) => (
                <li key={i}>{{ CHEIO: '👥', BARULHO: '🔊', BLOQUEIO: '⛔', LIBERADO: '✅' }[r.tipo]} {r.nome} <small>{new Date(r.em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}</small></li>
              ))}
            </ul>
          )}
        </div>

        <details className="card demo">
          <summary>🎬 Modo apresentação</summary>
          <p className="muted small">Restaura lotação, ruído e bloqueios do cenário original.</p>
          <button className="btn btn-sm" onClick={resetar}>↺ Resetar cenário</button>
          <p className="muted small">{mapa.evento.descricao}</p>
          <div className="row wrap">
            <a className="btn btn-sm btn-ghost" href={`#/organizador?evento=${ev}`}>📊 Painel do organizador</a>
            <a className="btn btn-sm btn-ghost" href={`#/validacao?evento=${ev}`}>🧪 Teste com usuários</a>
            <a className="btn btn-sm btn-ghost" href={`#/planta?evento=${ev}`}>🖨️ Planta impressa</a>
          </div>
        </details>
      </aside>

      {toast && <div key={toast.id} className={`toast toast-${toast.tipo}`} role="status">{toast.txt}</div>}
      {qr && <QrModal mapa={mapa} evento={ev} onFechar={() => setQr(false)} />}
    </div>
  );
}

function SelectLugar({ lugares, value, onChange, vazio = 'Escolha…' }) {
  const grupos = {};
  for (const p of lugares) (grupos[TIPO_UI[p.tipo]?.grupo || 'Outros'] ||= []).push(p);
  return (
    <select value={value} onChange={e => e.target.value && onChange(e.target.value)}>
      <option value="">{vazio}</option>
      {Object.entries(grupos).map(([g, ps]) => (
        <optgroup key={g} label={g}>
          {ps.map(p => <option key={p.codigo} value={p.codigo}>{TIPO_UI[p.tipo]?.icone} {p.nome}{p.bloqueado === 'S' ? ' (interditado)' : ''}</option>)}
        </optgroup>
      ))}
    </select>
  );
}

function Resultado({ res, modo, cor, decisao, setDecisao, preview, setPreview, irPara, setModo, calculando }) {
  if (res.status !== 'OK') {
    return (
      <div className="card resultado sem-rota">
        <div className="card-tit">😕 Sem rota viável</div>
        <p>{res.mensagem}</p>
        {res.indisponiveis?.length > 0 && <ul className="lista">{res.indisponiveis.map(i => <li key={i.codigo}>⛔ {i.nome} — {i.motivo}</li>)}</ul>}
      </div>
    );
  }
  return (
    <div className={`card resultado ${calculando ? 'recalc' : ''}`} style={{ '--c': cor }} aria-live="polite">
      <div className="res-topo">
        <div>
          <small className="muted">{modo === 'saida' ? '🚪 Saída sugerida' : 'Rota sugerida'}</small>
          <h3>{res.destino.nome}</h3>
        </div>
        {podeFalar && <button className="btn-icone" onClick={() => falar(res.mensagem)} aria-label="Ouvir">🔊</button>}
      </div>
      <div className="metricas">
        <div><b>{res.distancia_m} m</b><span>distância</span></div>
        <div><b>~{res.tempo_min} min</b><span>no seu ritmo</span></div>
        <div><b style={{ color: NIVEL[res.ruido_max] }}>{NIVEL_TXT[res.ruido_max]}</b><span>ruído máx.</span></div>
        <div><b style={{ color: NIVEL[res.lotacao_max] }}>{NIVEL_TXT[res.lotacao_max]}</b><span>lotação máx.</span></div>
      </div>
      <p className="mensagem">{res.mensagem}</p>
      {res.evita?.length > 0 && <div className="chips">{res.evita.map(e => <span key={e} className="chip chip-ok">✓ evita {e}</span>)}</div>}
      {res.alertas?.length > 0 && <div className="chips">{res.alertas.map(a => <span key={a} className="chip chip-warn">⚠ {a}</span>)}</div>}

      <ol className="passos">{res.instrucoes.map((p, i) => <li key={i}>{p}</li>)}</ol>

      {modo === 'saida' && res.alternativas?.length > 0 && (
        <div className="alternativas">
          <div className="card-tit small">Outras saídas <small>toque para ver no mapa</small></div>
          {res.alternativas.map(a => (
            <button key={a.codigo} className={`alt ${preview === a.codigo ? 'on' : ''}`} onClick={() => setPreview(p => (p === a.codigo ? null : a.codigo))}>
              <span>🚪 {a.nome}</span>
              <small>{a.distancia_m} m · ~{a.tempo_min} min{a.tem_escada ? ' · degraus' : ''}</small>
            </button>
          ))}
          {res.indisponiveis?.map(i => <div key={i.codigo} className="alt off"><span>⛔ {i.nome}</span><small>{i.motivo}</small></div>)}
        </div>
      )}

      <div className="decisao">
        {decisao === 'seguir' ? (
          <p className="ok">✅ Decisão sua: rota fixada. Se algo mudar no caminho, eu te aviso.</p>
        ) : (
          <>
            <button className="btn btn-pri" onClick={() => setDecisao('seguir')}>Vou seguir esta rota</button>
            <button className="btn btn-ghost" onClick={() => { setDecisao('outra'); if (modo === 'saida') setPreview(res.alternativas?.[0]?.codigo || null); else setModo('comparar'); }}>Ver outras opções</button>
          </>
        )}
      </div>
    </div>
  );
}

function Comparacao({ res, perfil, setPerfil, setModo }) {
  const rotas = res.rotas || [];
  const max = Math.max(...rotas.map(r => r.distancia_m || 0), 1);
  return (
    <div className="card">
      <div className="card-tit">Mesmo trajeto, rotas diferentes</div>
      <p className="muted small">Cada pessoa vê o caminho que funciona pra ela. Toque em um perfil para escolher.</p>
      {rotas.map(r => {
        const ui = PERFIS_UI[r.perfil.codigo];
        return (
          <button key={r.perfil.codigo} className={`comp ${perfil === r.perfil.codigo ? 'on' : ''}`} style={{ '--c': ui.cor }}
            onClick={() => { setPerfil(r.perfil.codigo); setModo('rota'); }}>
            <div className="comp-topo"><span>{ui.icone} <b>{ui.curto}</b></span><span>{r.status === 'OK' ? `${r.distancia_m} m · ~${r.tempo_min} min` : 'sem rota'}</span></div>
            <div className="barra"><i style={{ width: `${((r.distancia_m || 0) / max) * 100}%` }} /></div>
            {r.status === 'OK' && <small>{r.evita?.length ? `evita ${r.evita.join(', ')}` : 'caminho mais direto'}{r.tem_escada ? ' · tem degraus' : ''}</small>}
          </button>
        );
      })}
    </div>
  );
}

// Relógio do evento: mostra o que está ao vivo e permite simular outro horário (útil para demo e vídeo)
function Relogio({ mapa, hora, simulado, aberto, setAberto, setHora, onVer, P }) {
  const agenda = agendaPorPonto(mapa.programacao, hora);
  const aoVivo = Object.entries(agenda).filter(([, v]) => v.aoVivo).map(([cod, v]) => ({ cod, ...v.aoVivo }));
  const faixa = (mapa.programacao || []).map(p => [minutos(p.inicio), minutos(p.fim)]);
  const min = faixa.length ? Math.min(...faixa.map(f => f[0])) - 30 : 480;
  const max = faixa.length ? Math.max(...faixa.map(f => f[1])) + 30 : 1140;
  return (
    <div className={`relogio ${aberto ? 'aberto' : ''}`}>
      <button className="relogio-topo" onClick={() => setAberto(a => !a)} aria-expanded={aberto}>
        🕒 <b>{hora}</b>{simulado ? ' (simulado)' : ''}
        {aoVivo.length > 0 && <span className="ao-vivo"><i />{aoVivo.length} ao vivo</span>}
      </button>
      {aberto && (
        <div className="relogio-corpo">
          {aoVivo.length ? aoVivo.map(a => (
            <button key={a.cod + a.titulo} className="relogio-item" onClick={() => onVer(a.cod)}>
              <span className="ao-vivo"><i />AO VIVO</span> {a.titulo} <small>{P[a.cod]?.nome} · até {a.fim}</small>
            </button>
          )) : <p className="muted small">Nada acontecendo neste horário.</p>}
          <label className="campo">
            <span>Simular horário do evento</span>
            <input id="relogio-hora" type="range" min={min} max={max} step={5} value={Math.min(max, Math.max(min, minutos(hora)))}
              onChange={e => setHora(hhmmDe(Number(e.target.value)))} />
          </label>
          <div className="row wrap">
            {['10:15', '13:30', '14:10', '17:45'].map(h => <button key={h} className="chip" onClick={() => setHora(h)}>{h}</button>)}
            {simulado && <button className="chip" onClick={() => setHora(null)}>Horário real</button>}
          </div>
        </div>
      )}
    </div>
  );
}
