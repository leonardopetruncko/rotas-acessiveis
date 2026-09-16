import { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { Canvas, useFrame, useThree } from '@react-three/fiber';
import { Html, Line, OrbitControls } from '@react-three/drei';
import * as THREE from 'three';
import { NIVEL, TIPO_UI, ehDestino } from '../lib/tema.js';

const S = 0.01; // 1px da planta = 0.01 unidade de cena

function useGeo(mapa) {
  return useMemo(() => {
    const W = mapa.evento.largura_px || 1400;
    const H = mapa.evento.altura_px || 1000;
    const to3 = (x, y) => [(x - W / 2) * S, (y - H / 2) * S];
    const P = Object.fromEntries(mapa.pontos.map(p => [p.codigo, p]));
    return { W, H, to3, P };
  }, [mapa]);
}

// ---------------------------------------------------------------- câmera
function Rig({ modo2D, controls, foco }) {
  const { camera, size } = useThree();
  const animando = useRef(true);
  useEffect(() => { animando.current = true; }, [modo2D, foco?.[0], foco?.[1]]);
  useFrame((_, dt) => {
    if (!animando.current) return;
    const k = Math.min(2.4, Math.max(1, 1.3 / (size.width / size.height))); // afasta a câmera em telas estreitas
    const alvo = modo2D ? new THREE.Vector3(0, 18 * k, 0.01) : new THREE.Vector3(0, 11.5 * k, 11 * k);
    const olhar = new THREE.Vector3(foco?.[0] ?? 0, 0, foco?.[1] ?? 0.3).multiplyScalar(modo2D || k > 1 ? 0 : 0.35);
    const f = 1 - Math.pow(0.002, dt);
    camera.position.lerp(alvo.add(olhar), f);
    if (controls.current) {
      controls.current.target.lerp(olhar, f);
      controls.current.update();
    }
    if (camera.position.distanceTo(alvo) < 0.03) animando.current = false;
  });
  return null;
}

// ---------------------------------------------------------------- planta
function Piso({ W, H }) {
  const w = W * S, h = H * S, e = 0.06, alt = 0.35;
  return (
    <group>
      <mesh rotation-x={-Math.PI / 2} position-y={-0.001}>
        <planeGeometry args={[w + 0.4, h + 0.4]} />
        <meshStandardMaterial color="#0c1426" roughness={0.95} />
      </mesh>
      {[[0, -h / 2 - 0.2, w + 0.4, e], [0, h / 2 + 0.2, w + 0.4, e], [-w / 2 - 0.2, 0, e, h + 0.4], [w / 2 + 0.2, 0, e, h + 0.4]].map(([x, z, sx, sz], i) => (
        <mesh key={i} position={[x, alt / 2, z]}>
          <boxGeometry args={[sx, alt, sz]} />
          <meshStandardMaterial color="#334155" transparent opacity={0.55} />
        </mesh>
      ))}
    </group>
  );
}

function Area({ a, to3, rotulos }) {
  const ui = TIPO_UI[a.tipo] || TIPO_UI.STAND;
  const h = ui.h ?? 0.3;
  const [cx, cz] = to3(a.x + a.largura / 2, a.y + a.altura / 2);
  const w = a.largura * S, d = a.altura * S;
  const cor = a.cor || ui.cor;
  const mat = useRef();
  useFrame(({ clock }) => {
    if (a.tipo === 'PALCO' && mat.current) mat.current.emissiveIntensity = 0.3 + Math.sin(clock.elapsedTime * 5) * 0.18;
  });
  const topo = new THREE.Color(cor).lerp(new THREE.Color('#ffffff'), 0.25);
  return (
    <group position={[cx, 0, cz]}>
      <mesh position-y={h / 2}>
        <boxGeometry args={[w * 0.94, h, d * 0.94]} />
        <meshStandardMaterial ref={mat} color={cor} emissive={cor}
          emissiveIntensity={a.tipo === 'ACOLHIMENTO' ? 0.45 : 0.14} roughness={0.55} metalness={0.05}
          transparent opacity={a.tipo === 'CORREDOR' ? 0.45 : 0.93} />
      </mesh>
      {h > 0.1 && (
        <mesh position-y={h + 0.002} rotation-x={-Math.PI / 2}>
          <planeGeometry args={[w * 0.94, d * 0.94]} />
          <meshBasicMaterial color={topo} transparent opacity={0.18} />
        </mesh>
      )}
      {a.tipo === 'PALCO' && (
        <mesh position={[0, h + 0.35, -d * 0.4]}>
          <boxGeometry args={[w * 0.7, 0.55, 0.04]} />
          <meshStandardMaterial color="#111827" emissive="#60a5fa" emissiveIntensity={0.6} />
        </mesh>
      )}
      {rotulos && h > 0.1 && (
        <Html center position={[0, h + 0.18, 0]} distanceFactor={10} zIndexRange={[20, 0]} style={{ pointerEvents: 'none' }}>
          <div className="lbl" style={{ '--c': cor }}>
            <b>{a.nome}</b>
            {a.subtitulo && <span>{a.subtitulo}</span>}
          </div>
        </Html>
      )}
    </group>
  );
}

function Corredores({ mapa, P, to3, camada }) {
  return (
    <group>
      {mapa.trechos.map(t => {
        const a = P[t.a], b = P[t.b];
        if (!a || !b) return null;
        const [ax, az] = to3(a.x, a.y), [bx, bz] = to3(b.x, b.y);
        const len = Math.hypot(bx - ax, bz - az);
        const ang = Math.atan2(bz - az, bx - ax);
        const nivel = camada === 'lotacao' ? t.lotacao : camada === 'ruido' ? t.ruido : null;
        const bloq = t.bloqueado === 'S' || a.bloqueado === 'S' || b.bloqueado === 'S';
        // heatmap atenuado pra rota continuar sendo o destaque
        const cor = bloq ? '#b91c1c' : nivel ? `#${new THREE.Color(NIVEL[nivel]).lerp(new THREE.Color('#0c1426'), 0.45).getHexString()}` : t.escada === 'S' ? '#b45309' : '#26334d';
        return (
          <group key={t.id}>
            <mesh position={[(ax + bx) / 2, 0.01 + (t.id % 3) * 0.0008, (az + bz) / 2]} rotation={[0, -ang, 0]}>
              <boxGeometry args={[len, 0.02, 0.4]} />
              <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={bloq ? 0.35 : nivel ? 0.12 : 0.05} roughness={0.9} />
            </mesh>
            {t.escada === 'S' && (
              <Html center position={[(ax + bx) / 2, 0.25, (az + bz) / 2]} distanceFactor={10} style={{ pointerEvents: 'none' }}>
                <div className="tag tag-escada">degraus</div>
              </Html>
            )}
          </group>
        );
      })}
      {mapa.pontos.filter(p => p.tipo === 'CRUZAMENTO' || p.tipo === 'RAMPA').map(p => {
        const [x, z] = to3(p.x, p.y);
        return (
          <mesh key={p.codigo} position={[x, 0.012, z]} rotation-x={-Math.PI / 2}>
            <circleGeometry args={[0.2, 24]} />
            <meshStandardMaterial color="#26334d" />
          </mesh>
        );
      })}
    </group>
  );
}

// pontinhos = pessoas; densidade vem da lotação de cada trecho
function Multidao({ mapa, P, to3, agitada }) {
  const ref = useRef();
  const gente = useMemo(() => {
    let seed = 7;
    const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
    const arr = [];
    for (const t of mapa.trechos) {
      const a = P[t.a], b = P[t.b];
      if (!a || !b) continue;
      const [ax, az] = to3(a.x, a.y), [bx, bz] = to3(b.x, b.y);
      const len = Math.hypot(bx - ax, bz - az) || 1;
      const px = -(bz - az) / len, pz = (bx - ax) / len;
      const n = Math.round((t.distancia_m / 14) * Math.pow(t.lotacao, 1.35));
      for (let i = 0; i < n; i++) {
        const f = rnd(), o = (rnd() - 0.5) * 0.34;
        arr.push({ x: ax + (bx - ax) * f + px * o, z: az + (bz - az) * f + pz * o, fase: rnd() * 6.28, vel: 0.6 + rnd(), lot: t.lotacao });
      }
    }
    return arr;
  }, [mapa, P, to3]);

  useLayoutEffect(() => {
    if (!ref.current) return;
    const c = new THREE.Color();
    gente.forEach((g, i) => ref.current.setColorAt(i, c.set(g.lot >= 4 ? '#fca5a5' : g.lot === 3 ? '#fde68a' : '#cbd5e1')));
    if (ref.current.instanceColor) ref.current.instanceColor.needsUpdate = true;
  }, [gente]);

  const dummy = useMemo(() => new THREE.Object3D(), []);
  useFrame(({ clock }) => {
    if (!ref.current) return;
    const t = clock.elapsedTime * (agitada ? 2.5 : 1);
    gente.forEach((g, i) => {
      dummy.position.set(g.x + Math.sin(t * g.vel + g.fase) * 0.035, 0.07, g.z + Math.cos(t * g.vel * 0.8 + g.fase) * 0.035);
      dummy.updateMatrix();
      ref.current.setMatrixAt(i, dummy.matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;
  });
  if (!gente.length) return null;
  return (
    <instancedMesh key={gente.length} ref={ref} args={[undefined, undefined, gente.length]}>
      <capsuleGeometry args={[0.022, 0.05, 3, 6]} />
      <meshStandardMaterial roughness={0.6} />
    </instancedMesh>
  );
}

function Pontos({ mapa, to3, onPontoClick, emergencia, selecionado }) {
  return mapa.pontos.filter(ehDestino).map(p => {
    const [x, z] = to3(p.x, p.y);
    const saida = p.tipo === 'SAIDA';
    const bloq = p.bloqueado === 'S';
    const cor = bloq ? '#ef4444' : saida ? '#22c55e' : TIPO_UI[p.tipo]?.cor || '#e2e8f0';
    const r = saida ? 0.13 : 0.08;
    const sel = selecionado === p.codigo;
    return (
      <group key={p.codigo} position={[x, 0, z]}>
        <mesh position-y={0.1}>
          <cylinderGeometry args={[r, r, saida ? 0.2 : 0.12, 24]} />
          <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={saida ? 0.9 : 0.4} />
        </mesh>
        <mesh position-y={0.15}
          onClick={e => { e.stopPropagation(); onPontoClick?.(p.codigo); }}
          onPointerOver={e => { e.stopPropagation(); document.body.style.cursor = 'pointer'; }}
          onPointerOut={() => { document.body.style.cursor = ''; }}>
          <cylinderGeometry args={[0.28, 0.28, 0.3, 12]} />
          <meshBasicMaterial transparent opacity={0} depthWrite={false} />
        </mesh>
        {(saida || sel) && (
          <Html center position={[0, saida ? 0.45 : 0.4, 0]} distanceFactor={10} zIndexRange={[30, 0]} style={{ pointerEvents: 'none' }}>
            <div className={`tag ${saida ? 'tag-saida' : 'tag-sel'} ${bloq ? 'tag-bloq' : ''} ${emergencia && saida && !bloq ? 'pulse' : ''}`}>
              {saida ? (bloq ? '⛔ Interditada' : '🚪 Saída') : `📍 ${p.nome}`}
            </div>
          </Html>
        )}
      </group>
    );
  });
}

function Voce({ pos }) {
  const ring = useRef();
  useFrame(({ clock }) => {
    const f = (clock.elapsedTime * 1.1) % 1;
    const s = 1 + f * 2.2;
    ring.current.scale.set(s, s, s);
    ring.current.material.opacity = 1 - f;
  });
  return (
    <group position={[pos[0], 0.03, pos[1]]}>
      <mesh rotation-x={-Math.PI / 2} ref={ring}>
        <ringGeometry args={[0.13, 0.19, 40]} />
        <meshBasicMaterial color="#38bdf8" transparent />
      </mesh>
      <mesh position-y={0.16}>
        <sphereGeometry args={[0.11, 24, 24]} />
        <meshStandardMaterial color="#38bdf8" emissive="#38bdf8" emissiveIntensity={1.2} />
      </mesh>
      <Html center position={[0, 0.58, 0]} distanceFactor={10} zIndexRange={[40, 0]} style={{ pointerEvents: 'none' }}>
        <div className="tag tag-voce">Você está aqui</div>
      </Html>
    </group>
  );
}

function Destino({ pos, cor, nome }) {
  const g = useRef();
  useFrame(({ clock }) => { g.current.position.y = 0.45 + Math.abs(Math.sin(clock.elapsedTime * 2.2)) * 0.18; });
  return (
    <group position={[pos[0], 0, pos[1]]}>
      <group ref={g}>
        <mesh rotation-x={Math.PI} position-y={-0.14}>
          <coneGeometry args={[0.1, 0.26, 20]} />
          <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={0.9} />
        </mesh>
        <mesh>
          <sphereGeometry args={[0.13, 24, 24]} />
          <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={0.9} />
        </mesh>
      </group>
      <Html center position={[0, 1.0, 0]} distanceFactor={10} zIndexRange={[40, 0]} style={{ pointerEvents: 'none' }}>
        <div className="tag tag-destino" style={{ '--c': cor }}>🏁 {nome}</div>
      </Html>
    </group>
  );
}

function Rota({ pontos, cor, to3, idx = 0, total = 1, fraca = false, calmo = false }) {
  const off = total > 1 ? (idx - (total - 1) / 2) * 0.075 : 0;
  const pts = useMemo(() => pontos.map(p => {
    const [x, z] = to3(p.x, p.y);
    return new THREE.Vector3(x + off, 0.1 + idx * 0.012, z + off);
  }), [pontos, to3, off, idx]);
  const acum = useMemo(() => {
    const L = [0];
    for (let i = 1; i < pts.length; i++) L.push(L[i - 1] + pts[i].distanceTo(pts[i - 1]));
    return L;
  }, [pts]);
  const dash = useRef();
  const walker = useRef();
  useFrame(({ clock }, dt) => {
    if (calmo) return;
    if (dash.current?.material) dash.current.material.dashOffset -= dt * 0.9;
    if (walker.current && pts.length > 1) {
      const tot = acum[acum.length - 1];
      const t = (clock.elapsedTime * 1.2 + idx * 0.7) % tot;
      let i = 1;
      while (i < acum.length - 1 && acum[i] < t) i++;
      const f = (t - acum[i - 1]) / (acum[i] - acum[i - 1] || 1);
      walker.current.position.lerpVectors(pts[i - 1], pts[i], Math.min(1, Math.max(0, f)));
    }
  });
  if (pts.length < 2) return null;
  return (
    <group>
      <Line points={pts} color={cor} lineWidth={fraca ? 3 : 18} transparent opacity={fraca ? 0.4 : 0.35} />
      {fraca
        ? <Line points={pts} color={cor} lineWidth={2} dashed dashSize={0.12} gapSize={0.12} transparent opacity={0.7} />
        : <><Line points={pts} color="#0b1220" lineWidth={8} />
          <Line ref={dash} points={pts} color={cor} lineWidth={6} dashed dashSize={0.24} gapSize={0.1} /></>}
      {!fraca && !calmo && (
        <mesh ref={walker}>
          <sphereGeometry args={[0.075, 16, 16]} />
          <meshStandardMaterial color="#ffffff" emissive={cor} emissiveIntensity={2.5} />
        </mesh>
      )}
    </group>
  );
}

// ---------------------------------------------------------------- cena
function Cena({ mapa, rotas = [], origem, destino, camada, modo2D, autoRotate, interativo, onPontoClick, emergencia, selecionado, rotulos, calmo }) {
  const { W, H, to3, P } = useGeo(mapa);
  const controls = useRef();
  const po = origem && P[origem] ? to3(P[origem].x, P[origem].y) : null;
  const principal = rotas.find(r => !r.fraca);
  const destinoCod = destino || principal?.pontos?.[principal.pontos.length - 1]?.codigo;
  const pd = destinoCod && P[destinoCod] ? to3(P[destinoCod].x, P[destinoCod].y) : null;

  return (
    <>
      <color attach="background" args={[emergencia ? '#16060a' : '#070b16']} />
      <fog attach="fog" args={[emergencia ? '#16060a' : '#070b16', 18, 40]} />
      <ambientLight intensity={0.55} />
      <hemisphereLight args={['#bcd3ff', '#0b1020', 0.6]} />
      <directionalLight position={[6, 12, 6]} intensity={1.3} />
      <pointLight position={[0, 4, 0]} intensity={emergencia ? 18 : 0} color="#ef4444" distance={20} />

      <Rig modo2D={modo2D} controls={controls} foco={autoRotate ? null : po} />
      <OrbitControls ref={controls} makeDefault enableDamping dampingFactor={0.08}
        enableRotate={interativo && !modo2D} enableZoom={interativo} enablePan={interativo}
        minDistance={4} maxDistance={32} maxPolarAngle={Math.PI / 2.25}
        autoRotate={autoRotate && !calmo} autoRotateSpeed={0.5}
        onStart={() => { /* usuário assumiu a câmera */ }} />

      <Piso W={W} H={H} />
      <Corredores mapa={mapa} P={P} to3={to3} camada={camada} />
      {mapa.areas.map(a => <Area key={a.codigo} a={a} to3={to3} rotulos={rotulos} />)}
      {!calmo && <Multidao mapa={mapa} P={P} to3={to3} agitada={emergencia} />}
      <Pontos mapa={mapa} to3={to3} onPontoClick={onPontoClick} emergencia={emergencia} selecionado={selecionado} />

      {rotas.map((r, i) => (
        <Rota key={`${r.chave || i}-${r.pontos.map(p => p.codigo).join('-')}`} pontos={r.pontos} cor={r.cor} to3={to3}
          idx={r.fraca ? 0 : i} total={rotas.filter(x => !x.fraca).length} fraca={r.fraca} calmo={calmo} />
      ))}
      {po && <Voce pos={po} />}
      {pd && destinoCod !== origem && <Destino pos={pd} cor={principal?.cor || '#22c55e'} nome={P[destinoCod].nome} />}
    </>
  );
}

export default function Mapa3D({ className, ...props }) {
  return (
    <div className={`mapa3d ${className || ''}`}>
      <Canvas dpr={[1, 2]} camera={{ position: [0, 11, 10], fov: 45, near: 0.1, far: 100 }}
        onPointerMissed={() => props.onVazio?.()}>
        <Cena interativo rotulos {...props} />
      </Canvas>
    </div>
  );
}
