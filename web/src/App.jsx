import { useEffect, useState } from 'react';
import Home from './pages/Home.jsx';
import MapaPage from './pages/MapaPage.jsx';

// roteamento por hash: #/ (home) e #/app?evento=&origem=&destino=&perfil=
function rotaAtual() {
  return window.location.hash.replace(/^#/, '').split('?')[0] || '/';
}

export default function App() {
  const [rota, setRota] = useState(rotaAtual());
  useEffect(() => {
    const on = () => {
      const r = rotaAtual();
      if (!r.startsWith('/')) return; // âncora da home (#como), não é rota
      setRota(r);
      window.scrollTo(0, 0);
    };
    window.addEventListener('hashchange', on);
    return () => window.removeEventListener('hashchange', on);
  }, []);
  return rota.startsWith('/app') ? <MapaPage /> : <Home />;
}
