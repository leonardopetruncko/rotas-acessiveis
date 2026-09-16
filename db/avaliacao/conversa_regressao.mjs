// Regressão do chat (AC_CONVERSA): node db/avaliacao/conversa_regressao.mjs
// ⚠AUTO = abre o modo emergência sozinho (só deve acontecer com regra de segurança ou 'emergência/socorro/perigo')
const B='https://ga62b00bec87621-ent6dw42g77dfktt.adb.sa-saopaulo-1.oraclecloudapps.com/ords/acesso_app/api/v1/eventos/NEXT26/conversa';
const perguntas = ['tem sala calma no evento?', 'quero sair do evento agora', 'está pegando fogo', 'tem fumaça aqui', 'emergência!', 'socorro',
 'como eu saio daqui?', 'onde fica a saída?', 'por onde eu fujo', 'o alarme tocou', 'minha amiga desmaiou', 'estou passando mal',
 'Tem rampa no evento?', 'tem comida no evento?', 'que evento é esse?', 'o que tem no evento?', 'o evento tem acessibilidade?',
 'tem banheiro no evento?', 'quais saídas tem no evento?', 'o evento está cheio?', 'a nvidia está no evento?', 'o barulho tá insuportável',
 'onde fica a praça de alimentação?', 'o que está acontecendo agora?', 'estou na AWS, como chego na arena?', 'obrigado'];
for (const t of perguntas) {
  let j; for (let k=0;k<2;k++){ const r=await fetch(B,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({texto:t, origem:'ORACLE', perfil:'PADRAO'})}); if(r.ok){j=await r.json();break;} }
  console.log(`${t.padEnd(38)} → ${(j.intencao||'').padEnd(16)} ${(j.explicacao?.metodo||'-').padEnd(15)} ${j.acao?.automatica?'⚠AUTO '+j.acao.tipo:(j.acao?'['+j.acao.tipo+']':'')}  | ${j.resposta.split('\n')[0].slice(0,55)}`);
}
