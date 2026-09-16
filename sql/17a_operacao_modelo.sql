-- =====================================================================
-- 17a — OPERAÇÃO DO EVENTO, VALIDAÇÃO E TREINO DA IA (idempotente)
--  ac_faq / ac_faq_pergunta   perguntas frequentes (global ou por evento) com embedding
--  ac_conversa_log            tudo que perguntam ao chat (sem identificar a pessoa)
--  ac_decisao                 sugestão da IA × escolha da pessoa ("humano decide" medido)
--  ac_evacuacao               evacuação acionada pelo organizador
--  ac_val_*                   kit de validação com usuários (tarefas cronometradas)
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
  ddl('ALTER TABLE ac_evento ADD (pin_organizador VARCHAR2(20) DEFAULT ''2026'')');

  ddl(q'[CREATE TABLE ac_faq (
    id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_codigo VARCHAR2(30),                 -- NULL = vale para todo evento
    chave         VARCHAR2(40) NOT NULL,
    resposta      VARCHAR2(1000) NOT NULL,
    destino_ponto VARCHAR2(40),                 -- lugar para oferecer "Traçar rota"
    CONSTRAINT ac_faq_uk UNIQUE (evento_codigo, chave)
  )]');
  ddl(q'[CREATE TABLE ac_faq_pergunta (
    id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    faq_id    NUMBER NOT NULL REFERENCES ac_faq(id) ON DELETE CASCADE,
    pergunta  VARCHAR2(400) NOT NULL,
    origem    VARCHAR2(20) DEFAULT 'CURADORIA',  -- CURADORIA | ENSINADA (veio do log)
    embedding VECTOR(384, FLOAT32)
  )]');

  ddl(q'[CREATE TABLE ac_conversa_log (
    id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id  NUMBER NOT NULL,
    texto      VARCHAR2(1000) NOT NULL,
    intencao   VARCHAR2(30),
    faq_chave  VARCHAR2(40),
    metodo     VARCHAR2(30),
    confianca  NUMBER,
    entendeu   VARCHAR2(1),
    revisado   VARCHAR2(1) DEFAULT 'N',
    rotulo     VARCHAR2(80),                    -- resposta correta ensinada pelo organizador
    criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP
  )]');
  ddl('CREATE INDEX ac_conversa_log_ix ON ac_conversa_log(evento_id, criado_em)');

  ddl(q'[CREATE TABLE ac_decisao (
    id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id  NUMBER NOT NULL,
    perfil     VARCHAR2(30),
    origem     VARCHAR2(40),
    destino    VARCHAR2(40),
    modo       VARCHAR2(10),                    -- rota | saida | comparar
    caminho    VARCHAR2(1000),
    decisao    VARCHAR2(20) NOT NULL,           -- SEGUIU | OUTRA_OPCAO | TROCOU_PERFIL
    criado_em  TIMESTAMP DEFAULT SYSTIMESTAMP
  )]');

  ddl(q'[CREATE TABLE ac_evacuacao (
    id           NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id    NUMBER NOT NULL,
    mensagem     VARCHAR2(400),
    iniciada_em  TIMESTAMP DEFAULT SYSTIMESTAMP,
    encerrada_em TIMESTAMP
  )]');

  ddl(q'[CREATE TABLE ac_val_tarefa (
    id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_codigo VARCHAR2(30) NOT NULL,
    codigo     VARCHAR2(10) NOT NULL,
    enunciado  VARCHAR2(500) NOT NULL,
    perfil     VARCHAR2(30),
    origem     VARCHAR2(40),
    destino    VARCHAR2(40),
    modo       VARCHAR2(10),
    intencao   VARCHAR2(30),
    CONSTRAINT ac_val_tarefa_uk UNIQUE (evento_codigo, codigo)
  )]');
  ddl(q'[CREATE TABLE ac_val_participante (
    id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id     NUMBER NOT NULL,
    apelido       VARCHAR2(60) NOT NULL,        -- pseudônimo, nunca nome real
    perfil        VARCHAR2(30),
    faixa_etaria  VARCHAR2(20),
    consentimento VARCHAR2(1) NOT NULL CHECK (consentimento = 'S'),
    criado_em     TIMESTAMP DEFAULT SYSTIMESTAMP
  )]');
  ddl(q'[CREATE TABLE ac_val_execucao (
    id              NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    participante_id NUMBER NOT NULL REFERENCES ac_val_participante(id),
    tarefa          VARCHAR2(10) NOT NULL,
    condicao        VARCHAR2(10) NOT NULL CHECK (condicao IN ('SEM_APP', 'COM_APP')),
    segundos        NUMBER,
    concluiu        VARCHAR2(1),
    confianca       NUMBER CHECK (confianca BETWEEN 1 AND 5),
    facilidade      NUMBER CHECK (facilidade BETWEEN 1 AND 5),
    comentario      VARCHAR2(1000),
    frase           VARCHAR2(400),              -- "como você perguntaria isso?" → treino da IA
    criado_em       TIMESTAMP DEFAULT SYSTIMESTAMP
  )]');
END;
/

-- ---------------------------------------------------------------- FAQ
DELETE FROM ac_faq_pergunta WHERE origem = 'CURADORIA';
DELETE FROM ac_faq WHERE id NOT IN (SELECT faq_id FROM ac_faq_pergunta);

MERGE INTO ac_faq t USING (
  SELECT NULL ev, 'COMO_FUNCIONA' chave, 'Eu calculo a rota dentro do banco de dados Oracle: cada corredor tem distância, degraus, barulho e lotação, e cada perfil dá um peso diferente para isso. Para entender o que você escreve, uso um modelo de IA que roda dentro do próprio banco. Eu sugiro e explico; quem escolhe o caminho é você.' resposta, NULL destino FROM dual UNION ALL
  SELECT NULL, 'PRIVACIDADE', 'Não rastreio você. Só uso a sua localização quando você diz onde está ou escaneia um QR. As perguntas ficam guardadas sem nome, só para melhorar as respostas, e a IA roda dentro do banco do evento — nada vai para serviços externos.', NULL FROM dual UNION ALL
  SELECT NULL, 'QUEM_DECIDE', 'Você decide. Eu mostro a rota sugerida, o motivo e as alternativas, e nada acontece sem você tocar num botão. A única exceção é alerta de fogo ou fumaça: aí eu mostro a saída na hora, e você continua livre para escolher outra.', NULL FROM dual UNION ALL
  SELECT NULL, 'PERFIS', 'Tenho 4 perfis: Sem restrição (caminho mais curto), Cadeirante (sem escadas e fugindo de multidão), Mobilidade reduzida (sem escadas, menos gente) e Neurodivergente/sensível a estímulos (prioriza silêncio e pouca gente). Você troca a qualquer momento.', NULL FROM dual UNION ALL
  SELECT NULL, 'COMO_REPORTAR', 'No painel "Algo mudou aqui?" escolha Muito cheio, Muito barulho, Bloqueado ou Normalizou. O reporte vale para todo mundo e as rotas são recalculadas na hora.', NULL FROM dual UNION ALL
  SELECT NULL, 'QR', 'Os QR codes dos totens abrem o mapa já sabendo onde você está, sem GPS e sem instalar aplicativo.', NULL FROM dual UNION ALL
  SELECT 'NEXT26', 'CRIANCA_PERDIDA', 'Mantenha a calma e avise AGORA qualquer pessoa da organização ou vá à Brigada. Diga a roupa e a idade da criança. Crianças com pulseira de atendimento prioritário têm QR com o contato do responsável.', 'BRIG' FROM dual UNION ALL
  SELECT 'NEXT26', 'WIFI', 'Rede Wi-Fi: FIAP-NEXT-Visitantes. A senha está impressa no verso da sua credencial. (Informação ilustrativa do cenário de demonstração.)', NULL FROM dual UNION ALL
  SELECT 'NEXT26', 'ACHADOS_PERDIDOS', 'Achados e perdidos ficam no Credenciamento, perto da entrada principal.', 'CRED' FROM dual UNION ALL
  SELECT 'NEXT26', 'LIBRAS', 'As keynotes do Palco Principal têm intérprete de Libras e legenda ao vivo. Para outras atividades, peça no Credenciamento. (Informação ilustrativa.)', 'PALCO' FROM dual UNION ALL
  SELECT 'NEXT26', 'CAO_GUIA', 'Sim! Cão-guia pode entrar e circular em todo o evento — é um direito garantido pela Lei 11.126/2005.', NULL FROM dual UNION ALL
  SELECT 'NEXT26', 'AGUA', 'Tem bebedouros na Praça de Alimentação e água à venda nos food trucks.', 'ALIM' FROM dual UNION ALL
  SELECT 'NEXT26', 'CARREGAR_CELULAR', 'Há pontos de recarga de celular no Credenciamento.', 'CRED' FROM dual UNION ALL
  SELECT 'NEXT26', 'CADEIRA_EMPRESTIMO', 'O Credenciamento empresta cadeira de rodas mediante apresentação de documento.', 'CRED' FROM dual UNION ALL
  SELECT 'NEXT26', 'ABAFADOR', 'A Sala de Acolhimento empresta abafadores de ruído de graça.', 'ACOLH' FROM dual UNION ALL
  SELECT 'NEXT26', 'CREDENCIAL', 'Retire sua credencial no Credenciamento com um documento com foto.', 'CRED' FROM dual UNION ALL
  SELECT 'NEXT26', 'FALAR_EQUIPE', 'Procure qualquer pessoa com a camiseta da organização, ou vá ao Credenciamento. Em caso de saúde, vá direto à Brigada.', 'CRED' FROM dual UNION ALL
  SELECT 'NEXT26', 'FUMAR', 'É proibido fumar dentro do pavilhão, inclusive cigarro eletrônico.', NULL FROM dual UNION ALL
  SELECT 'NEXT26', 'ESTACIONAMENTO', 'Não tenho informação de estacionamento ou transporte neste cenário de demonstração. O Credenciamento pode orientar.', 'CRED' FROM dual
) s ON (NVL(t.evento_codigo, '-') = NVL(s.ev, '-') AND t.chave = s.chave)
WHEN MATCHED THEN UPDATE SET t.resposta = s.resposta, t.destino_ponto = s.destino
WHEN NOT MATCHED THEN INSERT (evento_codigo, chave, resposta, destino_ponto) VALUES (s.ev, s.chave, s.resposta, s.destino);

INSERT INTO ac_faq_pergunta (faq_id, pergunta)
SELECT f.id, q.pergunta FROM ac_faq f JOIN (
  SELECT 'COMO_FUNCIONA' chave, column_value pergunta FROM TABLE(sys.odcivarchar2list(
    'como funciona esse app', 'como a rota é escolhida', 'de onde vem a sugestão de caminho', 'isso é inteligência artificial',
    'qual tecnologia vocês usam', 'como você sabe o melhor caminho', 'how does this work')) UNION ALL
  SELECT 'PRIVACIDADE', column_value FROM TABLE(sys.odcivarchar2list(
    'o que vocês fazem com minhas informações', 'minha localização fica salva', 'isso é seguro para minha privacidade',
    'vocês sabem onde eu estou o tempo todo', 'e a LGPD', 'meus dados são vendidos', 'do you track me')) UNION ALL
  SELECT 'QUEM_DECIDE', column_value FROM TABLE(sys.odcivarchar2list(
    'sou obrigado a seguir essa rota', 'a IA escolhe por mim', 'posso ignorar a sugestão', 'quem manda no caminho sou eu ou você',
    'o app toma decisão sozinho')) UNION ALL
  SELECT 'PERFIS', column_value FROM TABLE(sys.odcivarchar2list(
    'que tipos de perfil tem', 'para que serve o perfil', 'qual perfil devo escolher', 'o que muda em cada perfil')) UNION ALL
  SELECT 'COMO_REPORTAR', column_value FROM TABLE(sys.odcivarchar2list(
    'como informo que está lotado', 'quero avisar que tem um obstáculo', 'como reporto barulho', 'posso avisar que a passagem fechou')) UNION ALL
  SELECT 'QR', column_value FROM TABLE(sys.odcivarchar2list(
    'para que servem os códigos nas placas', 'o que acontece quando escaneio o código', 'preciso ler o qr')) UNION ALL
  SELECT 'CRIANCA_PERDIDA', column_value FROM TABLE(sys.odcivarchar2list(
    'minha filha sumiu', 'uma criança se perdeu dos pais', 'encontrei uma criança sozinha', 'meu sobrinho desapareceu', 'lost child')) UNION ALL
  SELECT 'WIFI', column_value FROM TABLE(sys.odcivarchar2list(
    'tem wi-fi', 'qual a rede de internet', 'senha da internet', 'como conecto na rede', 'wifi password')) UNION ALL
  SELECT 'ACHADOS_PERDIDOS', column_value FROM TABLE(sys.odcivarchar2list(
    'achados e perdidos', 'esqueci minha mochila em algum lugar', 'perdi meu celular', 'alguém achou um documento', 'lost and found')) UNION ALL
  SELECT 'LIBRAS', column_value FROM TABLE(sys.odcivarchar2list(
    'tem tradução em libras', 'sou surdo, tem acessibilidade nas palestras', 'tem legendagem ao vivo', 'intérprete de língua de sinais')) UNION ALL
  SELECT 'CAO_GUIA', column_value FROM TABLE(sys.odcivarchar2list(
    'cão guia é permitido', 'posso levar meu cachorro de assistência', 'aceitam cão de serviço', 'guide dog allowed')) UNION ALL
  SELECT 'AGUA', column_value FROM TABLE(sys.odcivarchar2list(
    'tem bebedouro', 'onde tem água potável', 'estou com sede', 'onde encho minha garrafinha')) UNION ALL
  SELECT 'CARREGAR_CELULAR', column_value FROM TABLE(sys.odcivarchar2list(
    'tem tomada para carregar', 'preciso carregar o celular', 'meu telefone vai descarregar', 'ponto de recarga')) UNION ALL
  SELECT 'CADEIRA_EMPRESTIMO', column_value FROM TABLE(sys.odcivarchar2list(
    'tem cadeira de rodas para emprestar', 'minha avó precisa de uma cadeira de rodas', 'aluguel de cadeira de rodas')) UNION ALL
  SELECT 'ABAFADOR', column_value FROM TABLE(sys.odcivarchar2list(
    'tem protetor auricular', 'abafador de ruído', 'preciso de fone para bloquear o barulho')) UNION ALL
  SELECT 'CREDENCIAL', column_value FROM TABLE(sys.odcivarchar2list(
    'onde retiro o crachá', 'onde troco meu ingresso', 'preciso da minha pulseira de acesso', 'credenciamento fica onde')) UNION ALL
  SELECT 'FALAR_EQUIPE', column_value FROM TABLE(sys.odcivarchar2list(
    'quero falar com um atendente', 'onde tem alguém da equipe', 'preciso de ajuda de uma pessoa', 'contato da organização')) UNION ALL
  SELECT 'FUMAR', column_value FROM TABLE(sys.odcivarchar2list(
    'tem fumódromo', 'onde posso fumar', 'pode usar vape aqui')) UNION ALL
  SELECT 'ESTACIONAMENTO', column_value FROM TABLE(sys.odcivarchar2list(
    'tem estacionamento', 'como chego de metrô', 'onde para o uber', 'onde deixo meu carro'))
) q ON q.chave = f.chave;

UPDATE ac_faq_pergunta SET embedding = VECTOR_EMBEDDING(doc_model USING pergunta AS data) WHERE embedding IS NULL;

-- ---------------------------------------------------------------- tarefas do teste com usuários
MERGE INTO ac_val_tarefa t USING (
  SELECT 'NEXT26' ev, 'T1' cod, 'Você está no Stand Oracle Cloud e o barulho está insuportável. Encontre um lugar calmo para se recuperar.' enun, 'NEURODIVERGENTE' perfil, 'ORACLE' ori, 'ACOLH' dest, 'rota' modo, 'CRISE_SENSORIAL' intencao FROM dual UNION ALL
  SELECT 'NEXT26', 'T2', 'Você usa cadeira de rodas e está no Stand AWS. Chegue ao banheiro adaptado sem passar por degraus.', 'CADEIRANTE', 'AWS', 'WC', 'rota', 'BANHEIRO' FROM dual UNION ALL
  SELECT 'NEXT26', 'T3', 'O alarme de incêndio tocou. Você está na Arena Tech4Change e anda de muletas. Descubra por qual saída sair.', 'MOBILIDADE', 'ARENA', NULL, 'saida', 'EMERGENCIA' FROM dual UNION ALL
  SELECT 'NEXT26', 'T4', 'Descubra o que está acontecendo agora no evento e onde fica.', 'PADRAO', 'ENT', NULL, 'rota', 'Q_PROGRAMACAO' FROM dual
) s ON (t.evento_codigo = s.ev AND t.codigo = s.cod)
WHEN MATCHED THEN UPDATE SET t.enunciado = s.enun, t.perfil = s.perfil, t.origem = s.ori, t.destino = s.dest, t.modo = s.modo, t.intencao = s.intencao
WHEN NOT MATCHED THEN INSERT (evento_codigo, codigo, enunciado, perfil, origem, destino, modo, intencao)
  VALUES (s.ev, s.cod, s.enun, s.perfil, s.ori, s.dest, s.modo, s.intencao);
COMMIT;

SELECT (SELECT COUNT(*) FROM ac_faq) faqs, (SELECT COUNT(*) FROM ac_faq_pergunta) perguntas_faq,
       (SELECT COUNT(*) FROM ac_val_tarefa) tarefas FROM dual;
