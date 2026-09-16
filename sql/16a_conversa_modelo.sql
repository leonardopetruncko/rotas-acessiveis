-- =====================================================================
-- 16a — BASE DE CONHECIMENTO DO EVENTO (para a conversa)
--  ac_area.descricao: o que é cada lugar
--  ac_programacao: agenda por lugar (horário HH24:MI, dia do evento)
-- =====================================================================
DECLARE
  PROCEDURE ddl(p VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p;
  EXCEPTION WHEN OTHERS THEN
    IF SQLCODE NOT IN (-955, -1430) THEN RAISE; END IF;
  END;
BEGIN
  ddl('ALTER TABLE ac_area ADD (descricao VARCHAR2(400))');
  ddl(q'[CREATE TABLE ac_programacao (
    id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id   NUMBER NOT NULL REFERENCES ac_evento(id),
    ponto       VARCHAR2(40) NOT NULL,      -- codigo do ponto (sobrevive a recarga do cenário)
    titulo      VARCHAR2(200) NOT NULL,
    inicio      VARCHAR2(5) NOT NULL,       -- HH24:MI
    fim         VARCHAR2(5) NOT NULL,
    ruido_prev  NUMBER                      -- ruído esperado durante a atividade (1-5)
  )]');
  ddl('CREATE INDEX ac_programacao_ev_ix ON ac_programacao(evento_id, inicio)');
END;
/
