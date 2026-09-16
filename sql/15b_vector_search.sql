-- =====================================================================
-- 15b — AI VECTOR SEARCH: assistente que entende a pessoa por SIGNIFICADO
--  * ac_intencao / ac_intencao_frase: exemplos em PT com embedding VECTOR(384)
--  * ac_ponto.embedding: lugares do evento vetorizados (nome + tipo + apelidos)
--  * busca híbrida: VECTOR_DISTANCE COSINE (semântica) + menção literal (palavra-chave)
--  Tudo in-database com DOC_MODEL (15a). Idempotente.
-- =====================================================================
SET DEFINE OFF
DECLARE
  PROCEDURE ddl(p VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p;
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE NOT IN (-955, -1430, -2260, -2275, -1408) THEN RAISE; END IF;
  END;
BEGIN
  ddl(q'[CREATE TABLE ac_intencao (
    codigo          VARCHAR2(30) PRIMARY KEY,
    categoria       VARCHAR2(20) NOT NULL,      -- NECESSIDADE | PERFIL
    descricao       VARCHAR2(200),
    modo            VARCHAR2(10),               -- ROTA | SAIDA (NECESSIDADE)
    destino_tipo    VARCHAR2(40),               -- tipo de ac_ponto a buscar
    perfil_sugerido VARCHAR2(30)                -- perfil implícito na necessidade / PERFIL
  )]');
  ddl(q'[CREATE TABLE ac_intencao_frase (
    id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    intencao  VARCHAR2(30) NOT NULL REFERENCES ac_intencao(codigo),
    frase     VARCHAR2(400) NOT NULL,
    embedding VECTOR(384, FLOAT32)
  )]');
  ddl('ALTER TABLE ac_ponto ADD (busca_texto VARCHAR2(400), embedding VECTOR(384, FLOAT32))');
END;
/

DELETE FROM ac_intencao_frase;
DELETE FROM ac_intencao;

INSERT INTO ac_intencao VALUES ('CRISE_SENSORIAL', 'NECESSIDADE', 'Sobrecarga sensorial: precisa de lugar calmo', 'ROTA', 'ACOLHIMENTO', 'NEURODIVERGENTE');
INSERT INTO ac_intencao VALUES ('BANHEIRO',        'NECESSIDADE', 'Procura banheiro', 'ROTA', 'BANHEIRO_ADAP', NULL);
INSERT INTO ac_intencao VALUES ('MAL_ESTAR',       'NECESSIDADE', 'Mal-estar ou ferimento: precisa de atendimento', 'ROTA', 'SERVICO', NULL);
INSERT INTO ac_intencao VALUES ('EMERGENCIA',      'NECESSIDADE', 'Emergência: precisa sair com segurança', 'SAIDA', 'SAIDA', NULL);
INSERT INTO ac_intencao VALUES ('COMIDA',          'NECESSIDADE', 'Quer comer ou beber', 'ROTA', 'ALIMENTACAO', NULL);
INSERT INTO ac_intencao VALUES ('PALESTRA',        'NECESSIDADE', 'Quer ver palestra, show ou apresentação', 'ROTA', 'PALCO', NULL);
INSERT INTO ac_intencao VALUES ('P_CADEIRANTE',    'PERFIL', 'Usa cadeira de rodas ou carrinho', NULL, NULL, 'CADEIRANTE');
INSERT INTO ac_intencao VALUES ('P_MOBILIDADE',    'PERFIL', 'Mobilidade reduzida', NULL, NULL, 'MOBILIDADE');
INSERT INTO ac_intencao VALUES ('P_NEURO',         'PERFIL', 'Sensível a barulho e multidão', NULL, NULL, 'NEURODIVERGENTE');

INSERT INTO ac_intencao_frase (intencao, frase)
SELECT 'CRISE_SENSORIAL', column_value FROM TABLE(sys.odcivarchar2list(
  'o barulho está insuportável', 'preciso de um lugar calmo', 'estou tendo uma crise', 'muito barulho aqui',
  'quero um lugar silencioso', 'estou ansioso e sobrecarregado', 'tem gente demais, preciso sair daqui um pouco',
  'preciso me acalmar', 'sala de descompressão', 'o som está muito alto', 'estou em sobrecarga sensorial',
  'quero ficar num lugar tranquilo', 'too loud, I need a quiet place', 'I am having a panic attack'))
UNION ALL SELECT 'BANHEIRO', column_value FROM TABLE(sys.odcivarchar2list(
  'onde fica o banheiro', 'preciso ir ao banheiro', 'banheiro acessível', 'sanitário adaptado',
  'quero fazer xixi', 'toalete mais perto', 'where is the restroom', 'I need a bathroom'))
UNION ALL SELECT 'MAL_ESTAR', column_value FROM TABLE(sys.odcivarchar2list(
  'estou passando mal', 'preciso de um médico', 'me machuquei', 'estou tonto', 'vou desmaiar',
  'onde fica a enfermaria', 'chama a brigada', 'primeiros socorros', 'minha pressão caiu', 'I feel sick, I need a doctor'))
UNION ALL SELECT 'EMERGENCIA', column_value FROM TABLE(sys.odcivarchar2list(
  'emergência', 'como eu saio daqui', 'tem fogo', 'está pegando fogo', 'tem fumaça', 'alarme de incêndio tocou',
  'precisamos evacuar', 'saída de emergência', 'quero sair do evento agora', 'socorro, perigo', 'where is the emergency exit', 'fire, evacuate'))
UNION ALL SELECT 'COMIDA', column_value FROM TABLE(sys.odcivarchar2list(
  'estou com fome', 'onde posso comer', 'praça de alimentação', 'quero um lanche', 'onde tem água',
  'quero beber alguma coisa', 'I am hungry', 'where can I eat'))
UNION ALL SELECT 'PALESTRA', column_value FROM TABLE(sys.odcivarchar2list(
  'quero ver a palestra', 'onde é o palco', 'keynote principal', 'quero assistir a apresentação',
  'onde vai ser o show', 'where is the main stage'))
UNION ALL SELECT 'P_CADEIRANTE', column_value FROM TABLE(sys.odcivarchar2list(
  'sou cadeirante', 'estou de cadeira de rodas', 'uso cadeira de rodas', 'estou com carrinho de bebê',
  'não posso usar escada', 'I use a wheelchair'))
UNION ALL SELECT 'P_MOBILIDADE', column_value FROM TABLE(sys.odcivarchar2list(
  'estou de muletas', 'ando com bengala', 'tenho dificuldade para andar', 'sou idoso e ando devagar',
  'estou grávida e cansada', 'I walk with crutches'))
UNION ALL SELECT 'P_NEURO', column_value FROM TABLE(sys.odcivarchar2list(
  'sou autista', 'tenho TEA', 'tenho TDAH', 'sou neurodivergente', 'barulho me incomoda muito',
  'multidão me deixa mal', 'I am autistic'));

UPDATE ac_intencao_frase SET embedding = VECTOR_EMBEDDING(doc_model USING frase AS data);

-- lugares: texto de busca = nome + tipo em linguagem natural
UPDATE ac_ponto p
   SET busca_texto = p.nome || ' ' || CASE p.tipo
         WHEN 'SAIDA' THEN 'saída exit'
         WHEN 'STAND' THEN 'stand estande empresa'
         WHEN 'PALCO' THEN 'palco palestra keynote show'
         WHEN 'ARENA' THEN 'arena competição hackathon'
         WHEN 'ACOLHIMENTO' THEN 'sala calma silenciosa descompressão sensorial'
         WHEN 'BANHEIRO_ADAP' THEN 'banheiro sanitário acessível'
         WHEN 'ALIMENTACAO' THEN 'comida lanche restaurante'
         WHEN 'SERVICO' THEN 'atendimento serviço'
         ELSE LOWER(p.tipo) END
 WHERE p.codigo IS NOT NULL AND p.tipo NOT IN ('CRUZAMENTO', 'RAMPA');
UPDATE ac_ponto SET embedding = VECTOR_EMBEDDING(doc_model USING busca_texto AS data)
 WHERE busca_texto IS NOT NULL;
COMMIT;

SELECT i.categoria, COUNT(*) frases FROM ac_intencao_frase f JOIN ac_intencao i ON i.codigo = f.intencao GROUP BY i.categoria;
SELECT COUNT(*) lugares_vetorizados FROM ac_ponto WHERE embedding IS NOT NULL;
