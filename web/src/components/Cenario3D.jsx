// Cenografia do evento: estandes abertos com mobília, palco/arena com plateia e efeitos "ao vivo",
// praça de alimentação e sala de acolhimento. Tudo gerado a partir de ac_area + ac_programacao.
import { useLayoutEffect, useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { Html } from '@react-three/drei';
import * as THREE from 'three';
import { TIPO_UI } from '../lib/tema.js';

const S = 0.01;
export const TIPOS_ABERTOS = new Set(['STAND', 'PALCO', 'ARENA', 'ALIMENTACAO', 'ACOLHIMENTO']);

export const minutos = hhmm => {
  const [h, m] = String(hhmm).split(':').map(Number);
  return h * 60 + m;
};
export const hhmmDe = min => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;
export const agoraSP = () => new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

// atividade ao vivo e próxima (até 90 min) por código de ponto
export function agendaPorPonto(programacao = [], agora) {
  const m = minutos(agora);
  const mapa = {};
  for (const p of programacao) {
    const ini = minutos(p.inicio), fim = minutos(p.fim);
    const e = (mapa[p.ponto] ||= {});
    if (ini <= m && m < fim) e.aoVivo = p;
    else if (ini > m && ini - m <= 90 && (!e.proxima || minutos(e.proxima.inicio) > ini)) e.proxima = p;
  }
  return mapa;
}

function escurecer(cor, f = 0.55) {
  return `#${new THREE.Color(cor).lerp(new THREE.Color('#0b1220'), f).getHexString()}`;
}

// ---------------------------------------------------------------- peças
function Caixa({ p, s, cor, emissivo = 0, opacidade = 1, rot }) {
  return (
    <mesh position={p} rotation={rot}>
      <boxGeometry args={s} />
      <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={emissivo} roughness={0.7}
        transparent={opacidade < 1} opacity={opacidade} />
    </mesh>
  );
}

function Instancias({ posicoes, geometria, cor, emissivo = 0, escala = [1, 1, 1] }) {
  const ref = useRef();
  useLayoutEffect(() => {
    if (!ref.current) return;
    const d = new THREE.Object3D();
    posicoes.forEach(([x, y, z, ry = 0], i) => {
      d.position.set(x, y, z); d.rotation.set(0, ry, 0); d.scale.set(...escala); d.updateMatrix();
      ref.current.setMatrixAt(i, d.matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;
  }, [posicoes, escala]);
  if (!posicoes.length) return null;
  return (
    <instancedMesh key={posicoes.length} ref={ref} args={[undefined, undefined, posicoes.length]}>
      {geometria}
      <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={emissivo} roughness={0.8} />
    </instancedMesh>
  );
}

// telão que "passa conteúdo" quando está ao vivo
function Telao({ p, s, cor, aoVivo }) {
  const mat = useRef();
  useFrame(({ clock }) => {
    if (!mat.current) return;
    if (aoVivo) {
      const t = clock.elapsedTime;
      mat.current.emissive.setHSL((0.55 + Math.sin(t * 0.6) * 0.12 + 1) % 1, 0.8, 0.5);
      mat.current.emissiveIntensity = 1.1 + Math.sin(t * 7) * 0.25;
    } else {
      mat.current.emissive.set(cor);
      mat.current.emissiveIntensity = 0.35;
    }
  });
  return (
    <mesh position={p}>
      <boxGeometry args={s} />
      <meshStandardMaterial ref={mat} color="#0b1020" emissive={cor} emissiveIntensity={0.35} />
    </mesh>
  );
}

// ondas de som saindo do palco quando há atividade barulhenta
function OndasSom({ raio, intensidade = 4 }) {
  const aneis = useRef([]);
  const n = Math.max(2, Math.min(4, intensidade - 1));
  useFrame(({ clock }) => {
    aneis.current.forEach((m, i) => {
      if (!m) return;
      const f = ((clock.elapsedTime * 0.45) + i / n) % 1;
      const s = raio * (0.4 + f * 1.4);
      m.scale.set(s, s, s);
      m.material.opacity = (1 - f) * 0.45;
    });
  });
  return Array.from({ length: n }, (_, i) => (
    <mesh key={i} ref={el => (aneis.current[i] = el)} rotation-x={-Math.PI / 2} position-y={0.03}>
      <ringGeometry args={[0.96, 1, 64]} />
      <meshBasicMaterial color="#f472b6" transparent depthWrite={false} />
    </mesh>
  ));
}

function Holofote({ p, alvo, cor = '#fde68a', ativo }) {
  const ref = useRef();
  const dir = useMemo(() => new THREE.Vector3(...alvo).sub(new THREE.Vector3(...p)), [p, alvo]);
  const comp = dir.length();
  const quat = useMemo(() => new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, -1, 0), dir.clone().normalize()), [dir]);
  useFrame(({ clock }) => {
    if (ref.current) ref.current.material.opacity = ativo ? 0.13 + Math.sin(clock.elapsedTime * 3 + p[0]) * 0.05 : 0;
  });
  const meio = new THREE.Vector3(...p).add(dir.clone().multiplyScalar(0.5));
  return (
    <mesh ref={ref} position={meio} quaternion={quat}>
      <coneGeometry args={[0.35, comp, 24, 1, true]} />
      <meshBasicMaterial color={cor} transparent opacity={0} depthWrite={false} side={THREE.DoubleSide} blending={THREE.AdditiveBlending} />
    </mesh>
  );
}

// pessoas na plateia (só quando há atividade)
function Plateia({ posicoes, agitar }) {
  const ref = useRef();
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const cores = useMemo(() => {
    const paleta = ['#fca5a5', '#fde68a', '#bfdbfe', '#c4b5fd', '#bbf7d0', '#fbcfe8', '#e2e8f0'];
    return posicoes.map((_, i) => paleta[(i * 7) % paleta.length]);
  }, [posicoes]);
  useLayoutEffect(() => {
    if (!ref.current) return;
    const c = new THREE.Color();
    cores.forEach((k, i) => ref.current.setColorAt(i, c.set(k)));
    if (ref.current.instanceColor) ref.current.instanceColor.needsUpdate = true;
  }, [cores]);
  useFrame(({ clock }) => {
    if (!ref.current) return;
    const t = clock.elapsedTime;
    posicoes.forEach(([x, y, z], i) => {
      dummy.position.set(x, y + (agitar ? Math.abs(Math.sin(t * 4 + i)) * 0.03 : 0), z);
      dummy.updateMatrix();
      ref.current.setMatrixAt(i, dummy.matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;
  });
  if (!posicoes.length) return null;
  return (
    <instancedMesh key={posicoes.length} ref={ref} args={[undefined, undefined, posicoes.length]}>
      <capsuleGeometry args={[0.028, 0.06, 3, 6]} />
      <meshStandardMaterial roughness={0.6} />
    </instancedMesh>
  );
}

function grade(cols, linhas, x0, x1, z0, z1, y = 0) {
  const out = [];
  for (let r = 0; r < linhas; r++) {
    for (let c = 0; c < cols; c++) {
      out.push([x0 + ((x1 - x0) * (c + 0.5)) / cols, y, z0 + ((z1 - z0) * (r + 0.5)) / linhas]);
    }
  }
  return out;
}

// ---------------------------------------------------------------- mobília por tipo (frente = +z)
function MobiliaStand({ W, D, H, cor, aoVivo }) {
  const banquetas = useMemo(() => grade(3, 1, -W * 0.3, W * 0.3, D * 0.05, D * 0.15, 0.06), [W, D]);
  const visitas = useMemo(() => (aoVivo ? grade(5, 2, -W * 0.38, W * 0.38, D * 0.22, D * 0.44, 0.08) : grade(3, 1, -W * 0.3, W * 0.3, D * 0.34, D * 0.42, 0.08)), [W, D, aoVivo]);
  return (
    <group>
      <Telao p={[0, H * 0.62, -D / 2 + 0.03]} s={[W * 0.62, H * 0.5, 0.02]} cor={cor} aoVivo={aoVivo} />
      <Caixa p={[0, 0.07, D * 0.28]} s={[W * 0.55, 0.14, 0.09]} cor={cor} emissivo={0.25} />
      <Caixa p={[0, 0.145, D * 0.28]} s={[W * 0.57, 0.012, 0.11]} cor="#e2e8f0" />
      <Caixa p={[W / 2 - 0.1, H * 0.45, D / 2 - 0.1]} s={[0.07, H * 0.9, 0.03]} cor={cor} emissivo={0.6} />
      <Instancias posicoes={banquetas} cor="#cbd5e1" geometria={<cylinderGeometry args={[0.04, 0.04, 0.12, 12]} />} />
      <Plateia posicoes={visitas} agitar={aoVivo} />
    </group>
  );
}

function MobiliaPalco({ W, D, H, cor, aoVivo, arena, ruido }) {
  const palcoZ = -D / 2 + D * 0.18;
  const cadeiras = useMemo(() => (arena
    ? grade(4, 3, -W * 0.38, W * 0.38, -D * 0.05, D * 0.42, 0.06)
    : grade(9, 5, -W * 0.42, W * 0.42, -D * 0.02, D * 0.44, 0.04)), [W, D, arena]);
  const pessoas = useMemo(() => (aoVivo ? cadeiras.map(([x, , z]) => [x, 0.1, z]) : []), [cadeiras, aoVivo]);
  return (
    <group>
      <Caixa p={[0, 0.07, palcoZ]} s={[W * 0.8, 0.14, D * 0.3]} cor={escurecer(cor, 0.3)} emissivo={0.15} />
      <Telao p={[0, H * 0.75 + 0.2, -D / 2 + 0.04]} s={[W * 0.7, H * 0.7, 0.03]} cor={cor} aoVivo={aoVivo} />
      <Caixa p={[-W * 0.45, H * 0.55, -D / 2 + 0.12]} s={[0.12, H * 1.1, 0.12]} cor="#111827" />
      <Caixa p={[W * 0.45, H * 0.55, -D / 2 + 0.12]} s={[0.12, H * 1.1, 0.12]} cor="#111827" />
      {aoVivo && <Plateia posicoes={[[0, 0.22, palcoZ]]} agitar />}
      <Caixa p={[W * 0.12, 0.2, palcoZ + 0.05]} s={[0.08, 0.14, 0.06]} cor="#94a3b8" />
      {arena
        ? <Instancias posicoes={cadeiras} cor="#334155" geometria={<boxGeometry args={[0.36, 0.08, 0.16]} />} />
        : <Instancias posicoes={cadeiras} cor="#1e293b" geometria={<boxGeometry args={[0.07, 0.07, 0.07]} />} />}
      {arena && <Instancias posicoes={cadeiras.map(([x, , z]) => [x, 0.1, z - 0.02])} cor="#38bdf8" emissivo={aoVivo ? 1.2 : 0.3}
        geometria={<boxGeometry args={[0.08, 0.04, 0.005]} />} />}
      <Plateia posicoes={pessoas} agitar={aoVivo && !arena} />
      <Holofote p={[-W * 0.45, H * 1.15, -D / 2 + 0.12]} alvo={[0, 0.15, palcoZ]} ativo={aoVivo} />
      <Holofote p={[W * 0.45, H * 1.15, -D / 2 + 0.12]} alvo={[0, 0.15, palcoZ]} cor="#a5f3fc" ativo={aoVivo} />
      {aoVivo && ruido >= 4 && <OndasSom raio={Math.max(W, D) * 0.6} intensidade={ruido} />}
    </group>
  );
}

function MobiliaAlimentacao({ W, D, aoVivo }) {
  const trucks = [-W * 0.3, 0, W * 0.3];
  const cores = ['#f97316', '#22c55e', '#e11d48'];
  const mesas = useMemo(() => grade(4, 1, -W * 0.4, W * 0.4, D * 0.18, D * 0.32, 0.06), [W, D]);
  const fila = useMemo(() => (aoVivo ? grade(9, 2, -W * 0.42, W * 0.42, D * 0.02, D * 0.12, 0.08) : []), [W, D, aoVivo]);
  return (
    <group>
      {trucks.map((x, i) => (
        <group key={i} position={[x, 0, -D * 0.22]}>
          <Caixa p={[0, 0.13, 0]} s={[W * 0.22, 0.22, D * 0.3]} cor={cores[i]} emissivo={0.2} />
          <Caixa p={[0, 0.13, D * 0.151]} s={[W * 0.14, 0.09, 0.005]} cor="#fef3c7" emissivo={0.8} />
          <Caixa p={[0, 0.27, 0.02]} s={[W * 0.24, 0.02, D * 0.36]} cor="#f8fafc" />
        </group>
      ))}
      <Instancias posicoes={mesas} cor="#e5e7eb" geometria={<cylinderGeometry args={[0.07, 0.07, 0.1, 16]} />} />
      <Instancias posicoes={mesas.map(([x, , z]) => [x, 0.22, z])} cor="#f59e0b" emissivo={0.2} geometria={<coneGeometry args={[0.13, 0.08, 16]} />} />
      <Plateia posicoes={fila} />
    </group>
  );
}

function MobiliaAcolhimento({ W, D, H }) {
  const pufes = useMemo(() => grade(2, 3, -W * 0.25, W * 0.25, -D * 0.35, D * 0.3, 0.05), [W, D]);
  const luz = useRef();
  useFrame(({ clock }) => { if (luz.current) luz.current.material.emissiveIntensity = 0.55 + Math.sin(clock.elapsedTime * 0.8) * 0.15; });
  return (
    <group>
      <Instancias posicoes={pufes} cor="#a7f3d0" escala={[1, 0.55, 1]} geometria={<sphereGeometry args={[0.1, 16, 12]} />} />
      <Caixa p={[-W * 0.36, 0.07, -D * 0.4]} s={[0.07, 0.14, 0.07]} cor="#92400e" />
      <mesh position={[-W * 0.36, 0.2, -D * 0.4]}><sphereGeometry args={[0.09, 12, 10]} /><meshStandardMaterial color="#16a34a" /></mesh>
      <mesh ref={luz} position={[0, H * 0.9, 0]}>
        <boxGeometry args={[W * 0.5, 0.02, D * 0.3]} />
        <meshStandardMaterial color="#99f6e4" emissive="#5eead4" emissiveIntensity={0.6} transparent opacity={0.8} />
      </mesh>
    </group>
  );
}

// ---------------------------------------------------------------- estande aberto
export function Estande({ a, to3, P, rotulos, agenda }) {
  const ui = TIPO_UI[a.tipo] || TIPO_UI.STAND;
  const cor = a.cor || ui.cor;
  const H = a.tipo === 'PALCO' ? 0.55 : a.tipo === 'ARENA' ? 0.45 : a.tipo === 'ACOLHIMENTO' ? 0.4 : 0.32;
  const [cx, cz] = to3(a.x + a.largura / 2, a.y + a.altura / 2);
  const w = a.largura * S * 0.94, d = a.altura * S * 0.94;

  // a frente do estande é o lado mais próximo da entrada (ponto com o mesmo código)
  const ponto = P[a.codigo.replace(/^A_/, '')];
  let giro = 0;
  if (ponto) {
    const lados = [
      ['baixo', Math.abs(ponto.y - (a.y + a.altura))], ['cima', Math.abs(ponto.y - a.y)],
      ['esq', Math.abs(ponto.x - a.x)], ['dir', Math.abs(ponto.x - (a.x + a.largura))],
    ].sort((x, y) => x[1] - y[1])[0][0];
    giro = { baixo: 0, cima: Math.PI, esq: -Math.PI / 2, dir: Math.PI / 2 }[lados];
  }
  const lateral = Math.abs(giro) === Math.PI / 2;
  const W = lateral ? d : w;
  const D = lateral ? w : d;

  const cod = a.codigo.replace(/^A_/, '');
  const ag = agenda[cod] || {};
  const aoVivo = ag.aoVivo;
  const parede = escurecer(cor, 0.35);

  return (
    <group position={[cx, 0, cz]}>
      <group rotation-y={giro}>
        <mesh rotation-x={-Math.PI / 2} position-y={0.004}>
          <planeGeometry args={[W, D]} />
          <meshStandardMaterial color={escurecer(cor, 0.62)} roughness={1} />
        </mesh>
        <Caixa p={[0, H / 2, -D / 2 + 0.015]} s={[W, H, 0.03]} cor={parede} emissivo={0.12} />
        <Caixa p={[-W / 2 + 0.015, H * 0.3, 0]} s={[0.03, H * 0.6, D]} cor={parede} emissivo={0.08} opacidade={0.9} />
        <Caixa p={[W / 2 - 0.015, H * 0.3, 0]} s={[0.03, H * 0.6, D]} cor={parede} emissivo={0.08} opacidade={0.9} />
        <Caixa p={[0, H + 0.02, -D / 2 + 0.015]} s={[W, 0.04, 0.05]} cor={cor} emissivo={0.9} />
        {a.tipo === 'STAND' && <MobiliaStand W={W} D={D} H={H} cor={cor} aoVivo={!!aoVivo} />}
        {(a.tipo === 'PALCO' || a.tipo === 'ARENA') && (
          <MobiliaPalco W={W} D={D} H={H} cor={cor} aoVivo={!!aoVivo} arena={a.tipo === 'ARENA'} ruido={aoVivo?.ruido_prev || 3} />
        )}
        {a.tipo === 'ALIMENTACAO' && <MobiliaAlimentacao W={W} D={D} aoVivo={!!aoVivo} />}
        {a.tipo === 'ACOLHIMENTO' && <MobiliaAcolhimento W={W} D={D} H={H} />}
      </group>

      {rotulos && (
        <Html center position={[0, H + (a.tipo === 'PALCO' ? 1.0 : 0.35), 0]} distanceFactor={10} zIndexRange={[20, 0]} style={{ pointerEvents: 'none' }}>
          <div className={`lbl ${aoVivo ? 'lbl-vivo' : ''}`} style={{ '--c': cor }}>
            <b>{a.nome}</b>
            {aoVivo
              ? <span className="ao-vivo"><i />AO VIVO · {aoVivo.titulo}</span>
              : ag.proxima
                ? <span className="proxima">⏰ {ag.proxima.inicio} · {ag.proxima.titulo}</span>
                : a.subtitulo && <span>{a.subtitulo}</span>}
          </div>
        </Html>
      )}
    </group>
  );
}
