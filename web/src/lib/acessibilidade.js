// Preferências de acessibilidade do próprio app (ficam só neste aparelho).
import { useEffect, useState } from 'react';

const CHAVE = 'rotas-a11y';
export const PADRAO_A11Y = { contraste: false, fonteGrande: false, simples: false, lerAuto: false, semAnimacao: false, modoLeve: false };

function ler() {
  try {
    return { ...PADRAO_A11Y, ...JSON.parse(localStorage.getItem(CHAVE) || '{}') };
  } catch {
    return { ...PADRAO_A11Y };
  }
}

export function useAcessibilidade() {
  const [prefs, setPrefs] = useState(ler);
  useEffect(() => {
    try { localStorage.setItem(CHAVE, JSON.stringify(prefs)); } catch { /* sem storage: vale só nesta sessão */ }
    const el = document.documentElement;
    el.classList.toggle('a11y-contraste', prefs.contraste);
    el.classList.toggle('a11y-fonte', prefs.fonteGrande);
    el.classList.toggle('a11y-sem-animacao', prefs.semAnimacao);
  }, [prefs]);
  const alternar = k => setPrefs(p => ({ ...p, [k]: !p[k] }));
  return [prefs, alternar];
}

// Linguagem simples: frases curtas, sem parênteses, no máximo 4 linhas.
export function simplificar(texto) {
  if (!texto) return texto;
  return texto
    .split('\n')
    .map(l => l.replace(/\s*\([^)]*\)/g, '').trim())
    .filter(Boolean)
    .map(l => (l.startsWith('•') ? l : l.replace(/\b(Av|Dr|Dra|Sr|Sra|Prof)\./g, '$1§').split(/(?<=[.!?])\s+/)[0].replace(/§/g, '.')))
    .slice(0, 4)
    .join('\n');
}
