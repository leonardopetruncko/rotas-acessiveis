import { useEffect, useState } from 'react';
import Home from './pages/Home.jsx';
import MapaPage from './pages/MapaPage.jsx';
import OrganizadorPage from './pages/OrganizadorPage.jsx';
import ValidacaoPage from './pages/ValidacaoPage.jsx';
import PlantaPage from './pages/PlantaPage.jsx';

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
  if (rota.startsWith('/app')) return <MapaPage />;
  if (rota.startsWith('/organizador')) return <OrganizadorPage />;
  if (rota.startsWith('/validacao')) return <ValidacaoPage />;
  if (rota.startsWith('/planta')) return <PlantaPage />;
  return <Home />;
}
