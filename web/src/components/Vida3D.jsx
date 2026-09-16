// "Vida" do mapa 3D: pessoas caminhando pelo grafo (e evacuando), estrutura do pavilhão,
// pulso nos corredores críticos, setas da rota, feixes de luz e banners.
import { useEffect, useLayoutEffect, useMemo, useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { Line } from '@react-three/drei';
import * as THREE from 'three';

const PALETA = ['#fca5a5', '#fde68a', '#bfdbfe', '#c4b5fd', '#bbf7d0', '#fbcfe8', '#e2e8f0', '#fdba74', '#99f6e4'];

// ---------------------------------------------------------------- grafo para caminhar
function montarGrafo(mapa, P, to3) {
  const bloq = new Set(mapa.pontos.filter(p => p.bloqueado === 'S').map(p => p.codigo));
  const nos = {};
  for (const p of mapa.pontos) {
    const [x, z] = to3(p.x, p.y);
    nos[p.codigo] = { cod: p.codigo, x, z, adj: [], poi: !['CRUZAMENTO', 'RAMPA'].includes(p.tipo), saida: p.tipo === 'SAIDA' && !bloq.has(p.codigo) };
  }
  const arestas = [];
  for (const t of mapa.trechos) {
    if (t.bloqueado === 'S' || bloq.has(t.a) || bloq.has(t.b) || !nos[t.a] || !nos[t.b]) continue;
    const a = nos[t.a], b = nos[t.b];
    const len = Math.hypot(b.x - a.x, b.z - a.z) || 0.01;
    const e = { i: arestas.length, a: t.a, b: t.b, ax: a.x, az: a.z, bx: b.x, bz: b.z, len, px: -(b.z - a.z) / len, pz: (b.x - a.x) / len, lot: t.lotacao, m: t.distancia_m };
    arestas.push(e);
    a.adj.push({ e: e.i, para: t.b });
    b.adj.push({ e: e.i, para: t.a });
  }
  // distância até a saída mais próxima (Dijkstra multi-origem)
  const dist = {};
  for (const k in nos) dist[k] = nos[k].saida ? 0 : Infinity;
  const vis = new Set();
  for (;;) {
    let u = null;
    for (const k in dist) if (!vis.has(k) && dist[k] < Infinity && (u === null || dist[k] < dist[u])) u = k;
    if (u === null) break;
    vis.add(u);
    for (const { e, para } of nos[u].adj) {
      const d = dist[u] + arestas[e].len;
      if (d < dist[para]) dist[para] = d;
    }
  }
  return { nos, arestas, distSaida: dist };
}

function sorteio(seed) {
  let s = seed;
  return () => (s = (s * 16807) % 2147483647) / 2147483647;
}

// ---------------------------------------------------------------- pessoas
export function Agentes({ mapa, P, to3, emergencia, onContagem, maximo = 420 }) {
  const ref = useRef();
  const grafo = useMemo(() => montarGrafo(mapa, P, to3), [mapa, P, to3]);
  const rnd = useMemo(() => sorteio(11), []);

  const agentes = useMemo(() => {
    const lista = [];
    const r = sorteio(7);
    for (const e of grafo.arestas) {
      const n = Math.max(0, Math.round((e.m / 13) * Math.pow(e.lot, 1.3) * (maximo / 420)));
      for (let i = 0; i < n && lista.length < maximo; i++) {
        lista.push({ e: e.i, ida: r() > 0.5, t: r(), vel: 0.22 + r() * 0.2, off: (r() - 0.5) * 0.3, fase: r() * 6.28, pausa: 0, saiu: false, ultima: -1 });
      }
    }
    return lista;
  }, [grafo, maximo]);

  useLayoutEffect(() => {
    if (!ref.current) return;
    const c = new THREE.Color();
    agentes.forEach((_, i) => ref.current.setColorAt(i, c.set(PALETA[(i * 5) % PALETA.length])));
    if (ref.current.instanceColor) ref.current.instanceColor.needsUpdate = true;
  }, [agentes]);

  // entrou/saiu da emergência: vira todo mundo para a saída (ou devolve quem saiu)
  useEffect(() => {
    for (const ag of agentes) {
      if (emergencia) {
        const e = grafo.arestas[ag.e];
        const destino = ag.ida ? e.b : e.a, origem = ag.ida ? e.a : e.b;
        if (grafo.distSaida[origem] < grafo.distSaida[destino]) { ag.ida = !ag.ida; ag.t = 1 - ag.t; }
        ag.pausa = 0;
      } else if (ag.saiu) {
        ag.saiu = false; ag.e = Math.floor(rnd() * grafo.arestas.length); ag.t = rnd();
      }
    }
  }, [emergencia, agentes, grafo, rnd]);

  const dummy = useMemo(() => new THREE.Object3D(), []);
  const ultimoAviso = useRef(0);

  useFrame(({ clock }, dtBruto) => {
    if (!ref.current || !grafo.arestas.length) return;
    const dt = Math.min(dtBruto, 0.05);
    const tempo = clock.elapsedTime;
    let saidos = 0;

    agentes.forEach((ag, i) => {
      if (ag.saiu) {
        saidos++;
        dummy.position.set(0, -5, 0); dummy.scale.setScalar(0.0001); dummy.updateMatrix();
        ref.current.setMatrixAt(i, dummy.matrix);
        return;
      }
      let e = grafo.arestas[ag.e];
      if (ag.pausa > 0) {
        ag.pausa -= dt;
      } else {
        const lotacao = emergencia ? 1 : e.lot;
        const vel = (emergencia ? ag.vel * 3.2 : ag.vel * (1.25 - lotacao * 0.14));
        ag.t += (vel * dt) / e.len;
        if (ag.t >= 1) {
          const no = grafo.nos[ag.ida ? e.b : e.a];
          if (emergencia && no.saida) {
            ag.saiu = true;
          } else {
            let opcoes = no.adj.filter(o => o.e !== ag.e);
            if (!opcoes.length) opcoes = no.adj;
            let escolha;
            if (emergencia) {
              escolha = opcoes.reduce((m, o) => (grafo.distSaida[o.para] < grafo.distSaida[m.para] ? o : m), opcoes[0]);
            } else {
              if (no.poi && Math.random() < 0.45) ag.pausa = 1 + Math.random() * 3;
              const pesos = opcoes.map(o => Math.pow(grafo.arestas[o.e].lot, 1.5) + 0.4);
              let alvo = Math.random() * pesos.reduce((a, b) => a + b, 0);
              escolha = opcoes[opcoes.length - 1];
              for (let k = 0; k < opcoes.length; k++) { alvo -= pesos[k]; if (alvo <= 0) { escolha = opcoes[k]; break; } }
            }
            if (escolha) {
              ag.e = escolha.e;
              ag.ida = grafo.arestas[escolha.e].a === no.cod;
              ag.t = 0;
              e = grafo.arestas[ag.e];
            } else {
              ag.t = 1;
            }
          }
        }
      }
      const f = ag.ida ? ag.t : 1 - ag.t;
      const x = e.ax + (e.bx - e.ax) * f + e.px * ag.off;
      const z = e.az + (e.bz - e.az) * f + e.pz * ag.off;
      const andando = ag.pausa <= 0;
      dummy.position.set(x, 0.075 + (andando ? Math.abs(Math.sin(tempo * (emergencia ? 16 : 8) + ag.fase)) * 0.02 : 0), z);
      dummy.scale.setScalar(1);
      dummy.updateMatrix();
      ref.current.setMatrixAt(i, dummy.matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;

    if (onContagem && tempo - ultimoAviso.current > 0.5) {
      ultimoAviso.current = tempo;
      onContagem({ total: agentes.length, saidos });
    }
  });

  if (!agentes.length) return null;
  return (
    <instancedMesh key={agentes.length} ref={ref} args={[undefined, undefined, agentes.length]}>
      <capsuleGeometry args={[0.024, 0.06, 3, 6]} />
      <meshStandardMaterial roughness={0.55} />
    </instancedMesh>
  );
}

// ---------------------------------------------------------------- corredores críticos pulsando
export function PulsoCritico({ mapa, P, to3, camada }) {
  const grupo = useRef();
  const criticos = useMemo(() => mapa.trechos.filter(t => (camada === 'ruido' ? t.ruido >= 5 : t.lotacao >= 5) && P[t.a] && P[t.b]), [mapa, P, camada]);
  useFrame(({ clock }) => {
    if (!grupo.current) return;
    const op = 0.15 + ((Math.sin(clock.elapsedTime * 3) + 1) / 2) * 0.35;
    grupo.current.children.forEach(m => { m.material.opacity = op; });
  });
  if (!camada || !criticos.length) return null;
  return (
    <group ref={grupo}>
      {criticos.map(t => {
        const [ax, az] = to3(P[t.a].x, P[t.a].y), [bx, bz] = to3(P[t.b].x, P[t.b].y);
        const len = Math.hypot(bx - ax, bz - az);
        return (
          <mesh key={t.id} position={[(ax + bx) / 2, 0.035, (az + bz) / 2]} rotation={[0, -Math.atan2(bz - az, bx - ax), 0]}>
            <boxGeometry args={[len + 0.3, 0.02, 0.62]} />
            <meshBasicMaterial color="#ef4444" transparent opacity={0.3} depthWrite={false} blending={THREE.AdditiveBlending} />
          </mesh>
        );
      })}
    </group>
  );
}

// ---------------------------------------------------------------- estrutura do pavilhão
export function Estrutura({ W, H, emergencia }) {
  const w = W * 0.01, h = H * 0.01, alt = 2.4;
  const pilares = useMemo(() => {
    const out = [];
    const nx = 7, nz = 5;
    for (let i = 0; i <= nx; i++) { out.push([-w / 2 - 0.2 + ((w + 0.4) * i) / nx, -h / 2 - 0.2]); out.push([-w / 2 - 0.2 + ((w + 0.4) * i) / nx, h / 2 + 0.2]); }
    for (let j = 1; j < nz; j++) { out.push([-w / 2 - 0.2, -h / 2 - 0.2 + ((h + 0.4) * j) / nz]); out.push([w / 2 + 0.2, -h / 2 - 0.2 + ((h + 0.4) * j) / nz]); }
    return out;
  }, [w, h]);
  const treliça = useMemo(() => {
    const linhas = [];
    for (let i = 0; i <= 7; i++) {
      const x = -w / 2 - 0.2 + ((w + 0.4) * i) / 7;
      linhas.push([[x, alt, -h / 2 - 0.2], [x, alt, h / 2 + 0.2]]);
    }
    linhas.push([[-w / 2 - 0.2, alt, 0], [w / 2 + 0.2, alt, 0]]);
    return linhas;
  }, [w, h]);
  const luzes = useMemo(() => {
    const out = [];
    for (let i = 0; i < 7; i++) for (let j = 0; j < 4; j++) out.push([-w / 2 + (w * (i + 0.5)) / 7, alt - 0.05, -h / 2 + (h * (j + 0.5)) / 4]);
    return out;
  }, [w, h]);
  const refPil = useRef();
  const refLuz = useRef();
  const matLuz = useRef();
  useLayoutEffect(() => {
    const d = new THREE.Object3D();
    pilares.forEach(([x, z], i) => { d.position.set(x, alt / 2, z); d.updateMatrix(); refPil.current?.setMatrixAt(i, d.matrix); });
    luzes.forEach(([x, y, z], i) => { d.position.set(x, y, z); d.updateMatrix(); refLuz.current?.setMatrixAt(i, d.matrix); });
    if (refPil.current) refPil.current.instanceMatrix.needsUpdate = true;
    if (refLuz.current) refLuz.current.instanceMatrix.needsUpdate = true;
  }, [pilares, luzes]);
  useFrame(({ clock }) => {
    if (!matLuz.current) return;
    if (emergencia) {
      const on = Math.sin(clock.elapsedTime * 12) > 0;
      matLuz.current.color.set(on ? '#ef4444' : '#450a0a');
    } else {
      matLuz.current.color.set('#fef9c3');
    }
  });
  return (
    <group>
      <instancedMesh ref={refPil} args={[undefined, undefined, pilares.length]}>
        <cylinderGeometry args={[0.05, 0.05, alt, 10]} />
        <meshStandardMaterial color="#475569" transparent opacity={0.5} />
      </instancedMesh>
      {treliça.map((pts, i) => <Line key={i} points={pts} color="#64748b" lineWidth={1.5} transparent opacity={0.35} />)}
      <instancedMesh ref={refLuz} args={[undefined, undefined, luzes.length]}>
        <sphereGeometry args={[0.05, 10, 8]} />
        <meshBasicMaterial ref={matLuz} color="#fef9c3" />
      </instancedMesh>
    </group>
  );
}

// ---------------------------------------------------------------- feixe de luz (você / destino / saída)
export function Feixe({ pos, cor, altura = 3, largura = 0.22 }) {
  const ref = useRef();
  useFrame(({ clock }) => {
    if (ref.current) ref.current.material.opacity = 0.16 + (Math.sin(clock.elapsedTime * 2.5) + 1) * 0.07;
  });
  return (
    <mesh ref={ref} position={[pos[0], altura / 2, pos[1]]}>
      <cylinderGeometry args={[largura * 0.6, largura, altura, 24, 1, true]} />
      <meshBasicMaterial color={cor} transparent opacity={0.2} depthWrite={false} side={THREE.DoubleSide} blending={THREE.AdditiveBlending} />
    </mesh>
  );
}

// ---------------------------------------------------------------- setas correndo sobre a rota
export function Setas({ pts, cor, calmo }) {
  const ref = useRef();
  const acum = useMemo(() => {
    const L = [0];
    for (let i = 1; i < pts.length; i++) L.push(L[i - 1] + pts[i].distanceTo(pts[i - 1]));
    return L;
  }, [pts]);
  const total = acum[acum.length - 1] || 0;
  const n = Math.min(80, Math.floor(total / 0.32));
  const dummy = useMemo(() => new THREE.Object3D(), []);
  const cima = useMemo(() => new THREE.Vector3(0, 1, 0), []);
  const dir = useMemo(() => new THREE.Vector3(), []);

  useFrame(({ clock }) => {
    if (!ref.current || n === 0) return;
    const desloc = calmo ? 0 : (clock.elapsedTime * 0.7) % 0.32;
    for (let k = 0; k < n; k++) {
      const s = (k * 0.32 + desloc) % total;
      let i = 1;
      while (i < acum.length - 1 && acum[i] < s) i++;
      const f = (s - acum[i - 1]) / (acum[i] - acum[i - 1] || 1);
      dummy.position.lerpVectors(pts[i - 1], pts[i], Math.min(1, Math.max(0, f)));
      dummy.position.y += 0.03;
      dir.subVectors(pts[i], pts[i - 1]).normalize();
      dummy.quaternion.setFromUnitVectors(cima, dir);
      dummy.updateMatrix();
      ref.current.setMatrixAt(k, dummy.matrix);
    }
    ref.current.instanceMatrix.needsUpdate = true;
  });
  if (n === 0) return null;
  return (
    <instancedMesh key={n} ref={ref} args={[undefined, undefined, n]}>
      <coneGeometry args={[0.055, 0.14, 3]} />
      <meshBasicMaterial color={cor} />
    </instancedMesh>
  );
}

// ---------------------------------------------------------------- banner suspenso girando
export function Banner({ cor, W, altura }) {
  const ref = useRef();
  useFrame(({ clock }) => { if (ref.current) ref.current.rotation.y = clock.elapsedTime * 0.35; });
  return (
    <group position={[0, altura, 0]}>
      <mesh position={[0, 0.55, 0]}>
        <cylinderGeometry args={[0.004, 0.004, 1.1, 4]} />
        <meshBasicMaterial color="#94a3b8" transparent opacity={0.5} />
      </mesh>
      <group ref={ref}>
        {[0, Math.PI / 2].map(r => (
          <mesh key={r} rotation-y={r}>
            <boxGeometry args={[Math.min(0.9, W * 0.45), 0.2, 0.015]} />
            <meshStandardMaterial color={cor} emissive={cor} emissiveIntensity={0.85} />
          </mesh>
        ))}
      </group>
    </group>
  );
}
