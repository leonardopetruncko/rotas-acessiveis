// Conversa OFFLINE (sem Oracle): respostas básicas a partir da cópia do mapa.
// Online, quem responde é o AC_CONVERSA no banco (Vector Search + dados ao vivo).
import { interpretar } from './intencao.js';
import { ehDestino } from './tema.js';

const norm = s => ' ' + s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase() + ' ';
const hhmm = () => new Date().toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

export function conversaLocal(texto, mapa, origem) {
  const t = norm(texto);
  const i = interpretar(texto, mapa.pontos, mapa.perfis);
  const nome = c => mapa.pontos.find(p => p.codigo === c)?.nome;
  const area = c => mapa.areas.find(a => a.codigo === `A_${c}`);
  const base = { explicacao: { metodo: 'REGRAS_LOCAIS' }, contexto: { origem: i.origem, perfil: i.perfil }, sugestoes: [] };

  if (/(obrigad|valeu)/.test(t)) return { ...base, resposta: 'De nada! Em qualquer emergência, toque no botão 🚨.' };
  if (/^ *(oi|ola|bom dia|boa tarde|boa noite)[ !?.,]|quem e voce|o que voce faz/.test(t)) {
    return { ...base, resposta: `Oi! Sou a assistente do ${mapa.evento.nome}. Estou sem conexão com o servidor, mas ainda te mostro lugares, saídas e rotas.`,
      sugestoes: ['O que tem no evento?', 'Quais são as saídas?'] };
  }
  if (i.modo === 'saida') return { ...base, resposta: '🚨 Mostrando a saída mais segura pra você. Siga a sinalização e a brigada.', acao: { tipo: 'SAIDA', rotulo: 'Ver saída mais segura', automatica: true } };
  if (/(que evento|qual evento|nome do evento)/.test(t)) {
    return { ...base, resposta: `Você está no ${mapa.evento.nome} — ${mapa.evento.local}.`, sugestoes: ['O que tem no evento?'] };
  }
  if (/(programac|agenda|horario|que horas|acontecendo)/.test(t) && mapa.programacao?.length) {
    const agora = hhmm();
    const itens = mapa.programacao.filter(p => p.fim > agora).slice(0, 4)
      .map(p => `• ${p.inicio}–${p.fim}: ${p.titulo} — ${nome(p.ponto)}${p.inicio <= agora ? ' (agora)' : ''}`);
    return { ...base, resposta: itens.length ? `Agora são ${agora}:\n${itens.join('\n')}` : 'A programação de hoje já terminou.' };
  }
  if (/(o que tem|quais stands|empresas|visitar)/.test(t) && !i.destino) {
    const grupos = { Stands: ['STAND'], 'Palco e arena': ['PALCO', 'ARENA'], Serviços: ['ALIMENTACAO', 'SERVICO'], Acessibilidade: ['ACOLHIMENTO', 'BANHEIRO_ADAP', 'RAMPA'] };
    const linhas = Object.entries(grupos).map(([g, tipos]) => {
      const itens = mapa.areas.filter(a => tipos.includes(a.tipo)).map(a => a.nome);
      return itens.length ? `• ${g}: ${itens.join(', ')}` : null;
    }).filter(Boolean);
    return { ...base, resposta: `No ${mapa.evento.nome} tem:\n${linhas.join('\n')}` };
  }
  if (/(saidas|saida de emergencia)/.test(t)) {
    const s = mapa.pontos.filter(p => p.tipo === 'SAIDA').map(p => `• ${p.nome}${p.bloqueado === 'S' ? ' — ⛔ interditada' : ''}`);
    return { ...base, resposta: `Saídas:\n${s.join('\n')}`, acao: { tipo: 'SAIDA', rotulo: 'Mostrar a saída mais segura' } };
  }
  const destino = i.destino;
  if (destino && ehDestino(mapa.pontos.find(p => p.codigo === destino) || {})) {
    const a = area(destino);
    return {
      ...base, lugar: { codigo: destino, nome: nome(destino) },
      resposta: `${nome(destino)}${a?.descricao ? `: ${a.descricao}` : ''}${origem ? `\nToque em "Traçar rota" para ver o caminho a partir de ${nome(origem)}.` : ''}`,
      acao: { tipo: 'ROTA', destino, rotulo: `Traçar rota até ${nome(destino)}` },
    };
  }
  return { ...base, resposta: 'Sem conexão com o servidor, entendo menos coisas. Tente: "onde fica o banheiro", "quais são as saídas" ou "o que tem no evento".' };
}
