// Qualidade gráfica do mapa 3D conforme o aparelho.
// 'alta' = desktop/notebook bom · 'leve' = celular, pouca memória/CPU ou FPS caindo.
export function detectarQualidade() {
  try {
    const q = new URLSearchParams(window.location.hash.split('?')[1] || window.location.search).get('qualidade');
    if (q === 'alta' || q === 'leve') return q;
    const toque = window.matchMedia?.('(pointer: coarse)').matches;
    const telaPequena = Math.min(window.screen?.width || 9999, window.screen?.height || 9999) < 820;
    const memoria = navigator.deviceMemory;          // Chrome/Android (GB, aproximado)
    const nucleos = navigator.hardwareConcurrency;
    if ((toque && telaPequena) || (memoria && memoria <= 4) || (nucleos && nucleos <= 4)) return 'leve';
  } catch { /* ambiente sem window */ }
  return 'alta';
}

export const LIMITES = {
  alta: { dpr: [1, 1.75], agentes: 420, estrutura: true, banners: true, holofotes: true, plateiaAnimada: true },
  leve: { dpr: [1, 1], agentes: 130, estrutura: false, banners: false, holofotes: false, plateiaAnimada: false },
};
