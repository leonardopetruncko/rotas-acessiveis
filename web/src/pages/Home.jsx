import { useEffect, useState } from 'react';
import Mapa3D from '../components/Mapa3D.jsx';
import { api } from '../api.js';
import { PERFIS_UI } from '../lib/tema.js';

const DEMO = { ev: 'NEXT26', origem: 'ORACLE', destino: 'ACOLH' };

export default function Home() {
  const [mapa, setMapa] = useState(null);
  const [comp, setComp] = useState(null);
  const [falhou, setFalhou] = useState(false);

  useEffect(() => {
    api.mapa(DEMO.ev).then(setMapa).catch(() => setFalhou(true));
    api.comparar(DEMO.ev, { origem: DEMO.origem, destino: DEMO.destino }).then(setComp).catch(() => {});
  }, []);

  const rotas = (comp?.rotas || []).filter(r => r.status === 'OK' && r.perfil.codigo !== 'MOBILIDADE')
    .map(r => ({ chave: r.perfil.codigo, pontos: r.pontos, cor: PERFIS_UI[r.perfil.codigo].cor }));
  const linkDemo = `#/app?evento=${DEMO.ev}&origem=${DEMO.origem}&destino=${DEMO.destino}&modo=comparar`;

  return (
    <div className="home">
      <nav className="nav">
        <a href="#/" className="marca">🧭 <span>Rotas Acessíveis</span></a>
        <div className="row">
          <a href="#como" className="link">Como funciona</a>
          <a href="#negocio" className="link">Para eventos</a>
          <a href={linkDemo} className="btn btn-pri btn-sm">Abrir demo</a>
        </div>
      </nav>

      <header className="hero">
        <div className="hero-txt">
          <span className="pill">Tech4Change 2026 · Potencializando o ser humano com IA</span>
          <h1>Cada pessoa,<br /><em>a sua rota.</em></h1>
          <p className="lead">
            Um mapa 3D do evento que calcula o melhor caminho para cada corpo e cada mente —
            sem escadas pra quem não sobe, sem multidão pra quem não aguenta, com a saída de emergência certa pra você.
          </p>
          <p className="lema">A IA ilumina o caminho. <b>Quem decide é você.</b></p>
          <div className="row wrap">
            <a href={linkDemo} className="btn btn-pri">Ver no FIAP NEXT →</a>
            <a href={`#/app?evento=${DEMO.ev}&origem=${DEMO.origem}&modo=saida`} className="btn btn-ghost">🚨 Simular emergência</a>
          </div>
          <div className="legenda-hero">
            {rotas.map(r => (
              <span key={r.chave}><i style={{ background: r.cor }} />{PERFIS_UI[r.chave].icone} {PERFIS_UI[r.chave].curto}</span>
            ))}
            {rotas.length > 0 && <small>mesmo ponto de partida, três rotas diferentes — ao vivo do Oracle</small>}
          </div>
        </div>
        <div className="hero-mapa">
          {mapa ? <Mapa3D mapa={mapa} rotas={rotas} origem={DEMO.origem} destino={DEMO.destino} camada={null} autoRotate interativo={false} />
            : <div className="hero-placeholder">{falhou ? <p className="muted centro">Não consegui carregar o mapa agora.</p> : <div className="loader" />}</div>}
        </div>
      </header>

      <section className="secao">
        <h2>O problema: o evento é o mesmo, a experiência não</h2>
        <div className="cards3">
          <article className="card">
            <div className="big">♿</div>
            <h3>A escada no meio do caminho</h3>
            <p>Quem usa cadeira de rodas descobre a barreira quando já chegou nela. A planta do evento não diz qual caminho funciona pra quem.</p>
          </article>
          <article className="card">
            <div className="big">🧠</div>
            <h3>Sobrecarga sensorial</h3>
            <p>Palco, caixas de som e corredor lotado. Para uma pessoa autista ou com ansiedade, o caminho mais curto pode ser o que leva a uma crise.</p>
          </article>
          <article className="card">
            <div className="big">🚨</div>
            <h3>Emergência não é igual pra todos</h3>
            <p>A rota de fuga padrão pode ter degraus ou passar pela multidão. Em evacuação, cada segundo e cada barreira contam.</p>
          </article>
        </div>
        <p className="fonte">No Brasil, são <b>18,6 milhões</b> de pessoas com deficiência (IBGE, PNAD Contínua 2022) — e a Lei Brasileira de Inclusão (13.146/2015) exige acessibilidade em espaços e eventos.</p>
      </section>

      <section className="secao" id="como">
        <h2>Como funciona</h2>
        <div className="passos-home">
          <div><span>1</span><h3>Planta vira mapa inteligente</h3><p>Cada evento é único. A planta vira um grafo com corredores, rampas, degraus, palcos e saídas. <small>Roadmap: OCI Vision lê a planta automaticamente.</small></p></div>
          <div><span>2</span><h3>Você diz como se desloca</h3><p>Cadeirante, mobilidade reduzida, sensível a estímulos ou sem restrição. Por toque, texto ou voz.</p></div>
          <div><span>3</span><h3>Rota pra você, em tempo real</h3><p>O motor pondera distância, degraus, ruído e lotação — e recalcula quando o público reporta “cheio”, “barulho” ou “bloqueado”.</p></div>
          <div><span>4</span><h3>Você decide</h3><p>Mostramos a sugestão, o porquê e as alternativas. Nada é imposto: a pessoa escolhe o caminho.</p></div>
        </div>
      </section>

      <section className="secao">
        <h2>Feito para o dia do evento</h2>
        <div className="grid-dif">
          <div className="card"><b>🚪 Saída segura por perfil</b><p>Em emergência, cada pessoa recebe a saída viável pra ela — e vê as outras opções.</p></div>
          <div className="card"><b>▦ QR “você está aqui”</b><p>Totens com QR abrem o mapa já localizado. Sem GPS indoor, sem instalar app.</p></div>
          <div className="card"><b>🎤 Voz e leitura em voz alta</b><p>Pergunte falando; ouça as instruções. Acessível também para baixa visão.</p></div>
          <div className="card"><b>👥 Mapa de calor ao vivo</b><p>Lotação e ruído por corredor, alimentados pelo público e pela equipe.</p></div>
          <div className="card"><b>🔒 Dados no Oracle</b><p>Motor de rotas em PL/SQL dentro do Autonomous Database: auditável e com LGPD por design.</p></div>
          <div className="card"><b>🧩 Qualquer evento</b><p>Feiras, congressos, shows, estádios, universidades. Troca a planta, mantém o motor.</p></div>
        </div>
      </section>

      <section className="secao" id="negocio">
        <h2>Para organizadores de eventos</h2>
        <div className="planos">
          <div className="card plano"><small>Por evento</small><h3>Evento Inclusivo</h3><p>Mapeamento da planta, app com rotas por perfil, QR nos totens e rotas de saída.</p></div>
          <div className="card plano destaque"><small>Assinatura</small><h3>Venue</h3><p>Para pavilhões e centros de convenção: todos os eventos do espaço, planta sempre atualizada.</p></div>
          <div className="card plano"><small>Add-on</small><h3>Analytics de fluxo</h3><p>Onde lotou, onde fez barulho, quais barreiras apareceram. Relatório de acessibilidade pós-evento.</p></div>
        </div>
        <p className="muted centro">Quem paga: organizadores, venues, patrocinadores e poder público — acessibilidade é exigência legal e diferencial de marca.</p>
      </section>

      <section className="cta">
        <h2>Veja funcionando no FIAP NEXT</h2>
        <p>Planta ilustrativa, dados sintéticos, motor real rodando no Oracle Autonomous AI Database.</p>
        <a href={linkDemo} className="btn btn-pri">Abrir o mapa 3D →</a>
      </section>

      <footer className="rodape">
        Rotas Acessíveis · Tech4Change 2026 · FIAP · Oracle Autonomous AI Database + React
      </footer>
    </div>
  );
}
