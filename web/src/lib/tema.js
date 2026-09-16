export const PERFIS_UI = {
  PADRAO: { icone: '🚶', cor: '#60a5fa', curto: 'Padrão' },
  CADEIRANTE: { icone: '♿', cor: '#facc15', curto: 'Cadeirante' },
  MOBILIDADE: { icone: '🩼', cor: '#fb923c', curto: 'Mobilidade' },
  NEURODIVERGENTE: { icone: '🧠', cor: '#e879f9', curto: 'Neurodivergente' },
};

// h = altura do bloco no 3D (unidades de cena)
export const TIPO_UI = {
  STAND: { cor: '#334155', h: 0.45, icone: '🏢', grupo: 'Stands' },
  PALCO: { cor: '#ef4444', h: 0.9, icone: '🎤', grupo: 'Palcos e arenas' },
  ARENA: { cor: '#a855f7', h: 0.7, icone: '🏆', grupo: 'Palcos e arenas' },
  ALIMENTACAO: { cor: '#f59e0b', h: 0.25, icone: '🍔', grupo: 'Serviços' },
  ACOLHIMENTO: { cor: '#2dd4bf', h: 0.35, icone: '🧘', grupo: 'Acessibilidade' },
  BANHEIRO_ADAP: { cor: '#38bdf8', h: 0.35, icone: '🚻', grupo: 'Acessibilidade' },
  SERVICO: { cor: '#64748b', h: 0.3, icone: '🩺', grupo: 'Serviços' },
  TECNICA: { cor: '#475569', h: 0.5, icone: '🎛️', grupo: 'Serviços' },
  RAMPA: { cor: '#84cc16', h: 0.05, icone: '↗️', grupo: 'Acessibilidade' },
  CORREDOR: { cor: '#1e293b', h: 0.02 },
  SAIDA: { cor: '#22c55e', icone: '🚪', grupo: 'Saídas' },
  CRUZAMENTO: {},
};

// nível 1..5 (ruído/lotação)
export const NIVEL = ['#22c55e', '#22c55e', '#84cc16', '#eab308', '#f97316', '#ef4444'];
export const NIVEL_TXT = ['', 'tranquilo', 'ok', 'moderado', 'alto', 'crítico'];

export const ehDestino = p => !['CRUZAMENTO', 'RAMPA'].includes(p.tipo);
