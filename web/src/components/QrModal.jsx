import { useEffect, useState } from 'react';
import QRCode from 'qrcode';
import { TIPO_UI, ehDestino } from '../lib/tema.js';

// QR "Você está aqui": cada totem/stand tem o seu. Sem GPS, sem app pra instalar.
export default function QrModal({ mapa, evento, onFechar }) {
  const [codigos, setCodigos] = useState([]);

  useEffect(() => {
    const base = `${window.location.origin}${window.location.pathname}`;
    const pontos = mapa.pontos.filter(ehDestino);
    Promise.all(pontos.map(async p => {
      const url = `${base}?evento=${evento}&origem=${p.codigo}#/app`;
      const img = await QRCode.toDataURL(url, { margin: 1, width: 220, color: { dark: '#0b1220', light: '#ffffff' } });
      return { p, url, img };
    })).then(setCodigos);
  }, [mapa, evento]);

  return (
    <div className="modal-fundo" onClick={onFechar}>
      <div className="modal" onClick={e => e.stopPropagation()} role="dialog" aria-label="QR codes dos totens">
        <div className="modal-topo">
          <div>
            <h3>QR “Você está aqui”</h3>
            <p className="muted">Imprima e cole nos totens e stands. A pessoa aponta a câmera e o mapa já abre com a localização certa — sem GPS, sem instalar app.</p>
          </div>
          <div className="row">
            <button className="btn" onClick={() => window.print()}>🖨️ Imprimir</button>
            <button className="btn btn-ghost" onClick={onFechar} aria-label="Fechar">✕</button>
          </div>
        </div>
        {window.location.hostname === 'localhost' && (
          <p className="aviso">Você está em <b>localhost</b>: para testar no celular, abra o site pelo IP da rede (o Vite mostra em “Network”).</p>
        )}
        <div className="qr-grid">
          {codigos.map(({ p, url, img }) => (
            <a key={p.codigo} className="qr-card" href={url}>
              <img src={img} alt={`QR de ${p.nome}`} />
              <b>{TIPO_UI[p.tipo]?.icone} {p.nome}</b>
              <span>{mapa.evento.nome}</span>
            </a>
          ))}
        </div>
      </div>
    </div>
  );
}
