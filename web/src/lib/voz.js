// Voz nativa do navegador: ouvir (pt-BR) e falar. Sem enviar áudio a terceiros além do próprio navegador.
const SR = typeof window !== 'undefined' && (window.SpeechRecognition || window.webkitSpeechRecognition);

export const podeOuvir = !!SR;
export const podeFalar = typeof window !== 'undefined' && 'speechSynthesis' in window;

export function ouvir({ onTexto, onFim, onErro }) {
  if (!SR) return null;
  const r = new SR();
  r.lang = 'pt-BR';
  r.interimResults = true;
  r.maxAlternatives = 1;
  r.onresult = e => {
    const txt = Array.from(e.results).map(x => x[0].transcript).join(' ');
    onTexto?.(txt, e.results[e.results.length - 1].isFinal);
  };
  r.onerror = e => onErro?.(e.error);
  r.onend = () => onFim?.();
  r.start();
  return r;
}

export function falar(texto) {
  if (!podeFalar || !texto) return;
  window.speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(texto);
  u.lang = 'pt-BR';
  u.rate = 1.02;
  const v = window.speechSynthesis.getVoices().find(x => x.lang?.toLowerCase().startsWith('pt'));
  if (v) u.voice = v;
  window.speechSynthesis.speak(u);
}

export function calar() {
  if (podeFalar) window.speechSynthesis.cancel();
}
