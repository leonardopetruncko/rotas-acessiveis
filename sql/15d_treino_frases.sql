-- =====================================================================
-- 15d — TREINO: mais exemplos por intenção (gírias, erros comuns, EN/ES)
-- Rodar DEPOIS do 15b (o 15b recria a base). Não usa frases do conjunto de avaliação.
-- =====================================================================
SET DEFINE OFF
INSERT INTO ac_intencao_frase (intencao, frase)
SELECT 'Q_SAUDACAO', column_value FROM TABLE(sys.odcivarchar2list(
  'opa', 'fala aí', 'boa tarde, tudo certo?', 'você é uma assistente virtual?', 'com quem eu estou falando', 'hola', 'hi there'))
UNION ALL SELECT 'Q_EVENTO', column_value FROM TABLE(sys.odcivarchar2list(
  'onde eu vim parar', 'que congresso é esse', 'nome desse evento', 'que exposição é essa', 'sobre o que é esse evento', 'qué evento es este'))
UNION ALL SELECT 'Q_O_QUE_TEM', column_value FROM TABLE(sys.odcivarchar2list(
  'quais expositores estão aqui', 'que marcas estão expondo', 'lista de stands', 'o que dá pra ver por aqui', 'quais atrações tem hoje',
  'tem empresa de tecnologia', 'qué hay en el evento'))
UNION ALL SELECT 'Q_ONDE_FICA', column_value FROM TABLE(sys.odcivarchar2list(
  'onde tá o palco', 'me mostra onde fica a arena', 'em qual corredor fica a oracle', 'como faço para chegar na nvidia',
  'quero ir até o stand da azure', 'me guia até o credenciamento', 'localização da brigada', 'dónde queda el escenario', 'how do I get to the stage'))
UNION ALL SELECT 'Q_SOBRE_LUGAR', column_value FROM TABLE(sys.odcivarchar2list(
  'o que tem de legal na arena', 'o que eles mostram no stand da ibm', 'vale a pena ir no fiap labs', 'o que fazem nas startups',
  'para que serve a sala de acolhimento', 'o que é o stand da aws'))
UNION ALL SELECT 'Q_PROGRAMACAO', column_value FROM TABLE(sys.odcivarchar2list(
  'qual a próxima atração', 'tem palestra agora', 'horários das apresentações', 'o que vai ter mais tarde', 'que horas acaba o evento',
  'quando começa o pitch das startups', 'cronograma de hoje', 'what time is the keynote', 'qué hay ahora'))
UNION ALL SELECT 'Q_ACESSIBILIDADE', column_value FROM TABLE(sys.odcivarchar2list(
  'o pavilhão tem acessibilidade para cadeira de rodas', 'tem piso tátil', 'tem caminho sem escada', 'é tudo plano',
  'tem estrutura para deficientes', 'accessibility features'))
UNION ALL SELECT 'Q_LOTACAO', column_value FROM TABLE(sys.odcivarchar2list(
  'tá cheio lá', 'onde tem menos gente', 'qual área está mais calma agora', 'tem fila grande', 'o corredor principal está tumultuado',
  'como está o movimento agora', 'is it busy'))
UNION ALL SELECT 'Q_SAIDAS', column_value FROM TABLE(sys.odcivarchar2list(
  'onde é a saída', 'qual saída eu uso', 'onde fica a porta de emergência', 'saída mais próxima de mim', 'por onde eu saio do pavilhão',
  'rotas de fuga', 'where is the exit', 'salida de emergencia'))
UNION ALL SELECT 'BANHEIRO', column_value FROM TABLE(sys.odcivarchar2list(
  'preciso de um banheiro', 'toalete acessível', 'onde é o wc', 'tô apertado', 'lavabo', 'restroom please', 'dónde está el baño'))
UNION ALL SELECT 'COMIDA', column_value FROM TABLE(sys.odcivarchar2list(
  'onde tem restaurante', 'quero almoçar', 'tem food truck', 'lugar para lanchar', 'onde vende salgado', 'dónde puedo comer'))
UNION ALL SELECT 'CRISE_SENSORIAL', column_value FROM TABLE(sys.odcivarchar2list(
  'muito estímulo, preciso sair desse barulho', 'meu filho autista está agitado', 'preciso de um espaço tranquilo', 'estou em pânico com essa multidão',
  'as luzes estão me incomodando', 'preciso descansar num lugar quieto', 'demasiado ruido'))
UNION ALL SELECT 'MAL_ESTAR', column_value FROM TABLE(sys.odcivarchar2list(
  'não estou me sentindo bem', 'preciso de ajuda médica', 'alguém passou mal aqui', 'estou com muita dor', 'ambulância', 'necesito un médico'))
UNION ALL SELECT 'EMERGENCIA', column_value FROM TABLE(sys.odcivarchar2list(
  'incêndio', 'evacuação', 'tem uma emergência acontecendo', 'precisamos sair agora é perigoso', 'emergency'))
UNION ALL SELECT 'PALESTRA', column_value FROM TABLE(sys.odcivarchar2list(
  'quero assistir o keynote', 'vou ver o show no palco', 'onde é a palestra principal'))
UNION ALL SELECT 'P_CADEIRANTE', column_value FROM TABLE(sys.odcivarchar2list(
  'sou usuário de cadeira de rodas', 'estou empurrando um carrinho', 'wheelchair user'))
UNION ALL SELECT 'P_MOBILIDADE', column_value FROM TABLE(sys.odcivarchar2list(
  'estou com o pé imobilizado', 'uso andador', 'tenho problema no joelho'))
UNION ALL SELECT 'P_NEURO', column_value FROM TABLE(sys.odcivarchar2list(
  'tenho autismo', 'sou hipersensível a som', 'tenho transtorno do espectro autista'));

UPDATE ac_intencao_frase SET embedding = VECTOR_EMBEDDING(doc_model USING frase AS data) WHERE embedding IS NULL;
COMMIT;
SELECT COUNT(*) total_frases FROM ac_intencao_frase;
