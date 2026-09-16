import { useEffect, useMemo, useState } from 'react';
import { api, lerParams } from '../api.js';
import { TIPO_UI } from '../lib/tema.js';

// Planta 2D imprimível, sem rotas: usada na condição "sem o app" do teste e nos totens.
export default function PlantaPage() {
  const params = useMemo(lerParams, []);
  const ev = (params.get('evento') || 'NEXT26').toUpperCase();
  const aqui = params.get('aqui')?.toUpperCase();
  const [mapa, setMapa] = useState(null);
  useEffect(() => { api.mapa(ev).then(setMapa).catch(() => {}); }, [ev]);
  if (!mapa) return <div className="tela-cheia"><div className="loader" /></div>;

  const W = mapa.evento.largura_px, H = mapa.evento.altura_px;
  const P = Object.fromEntries(mapa.pontos.map(p => [p.codigo, p]));
  const voce = aqui && P[aqui];

  return (
    <div className="planta-pag">
      <div className="planta-topo no-print">
        <a href={`#/app?evento=${ev}`} className="btn btn-sm btn-ghost">← Voltar ao app</a>
        <button className="btn btn-sm btn-pri" onClick={() => window.print()}>🖨️ Imprimir</button>
      </div>
      <h1>{mapa.evento.nome} — planta</h1>
      <div className="planta-svg">
        <svg viewBox={`-20 -20 ${W + 40} ${H + 40}`} role="img" aria-label={`Planta do ${mapa.evento.nome}`}>
          <rect x="0" y="0" width={W} height={H} fill="#f8fafc" stroke="#0f172a" strokeWidth="6" />
          {mapa.trechos.map(t => {
            const a = P[t.a], b = P[t.b];
            return <line key={t.id} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={t.escada === 'S' ? '#b45309' : '#cbd5e1'}
              strokeWidth={t.escada === 'S' ? 14 : 36} strokeDasharray={t.escada === 'S' ? '10 8' : undefined} strokeLinecap="round" />;
          })}
          {mapa.areas.filter(a => a.tipo !== 'CORREDOR').map(a => (
            <g key={a.codigo}>
              <rect x={a.x} y={a.y} width={a.largura} height={a.altura} rx="8" fill={a.cor || TIPO_UI[a.tipo]?.cor || '#94a3b8'} fillOpacity="0.28"
                stroke={a.cor || '#475569'} strokeWidth="3" />
              <text x={a.x + a.largura / 2} y={a.y + a.altura / 2} textAnchor="middle" dominantBaseline="middle" fontSize={a.largura < 120 ? 15 : 20}
                fontWeight="700" fill="#0f172a">{a.nome}</text>
            </g>
          ))}
          {mapa.pontos.filter(p => p.tipo === 'SAIDA').map(p => (
            <g key={p.codigo}>
              <circle cx={p.x} cy={p.y} r="22" fill="#16a34a" />
              <text x={p.x} y={p.y + 46} textAnchor="middle" fontSize="18" fontWeight="700" fill="#166534">SAÍDA</text>
            </g>
          ))}
          {voce && (
            <g>
              <circle cx={voce.x} cy={voce.y} r="20" fill="#2563eb" stroke="#fff" strokeWidth="5" />
              <text x={voce.x} y={voce.y - 34} textAnchor="middle" fontSize="22" fontWeight="800" fill="#1d4ed8">VOCÊ ESTÁ AQUI</text>
            </g>
          )}
        </svg>
      </div>
      <p className="legenda-planta">Cinza: corredores · Laranja tracejado: degraus · Verde: saídas{voce ? ' · Azul: você' : ''}</p>
    </div>
  );
}
