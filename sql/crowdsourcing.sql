-- =====================================================================
-- CROWDSOURCING — pessoas reportam, a rota recalcula ao vivo
-- Roda depois do poc_acessibilidade_eventos.sql (usa ac_* e ac_calcular_rota)
-- =====================================================================

CREATE TABLE ac_reporte (
  id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id     NUMBER,
  ponto_id      NUMBER REFERENCES ac_ponto(id),
  tipo          VARCHAR2(20),
  reportado_por VARCHAR2(100),
  criado_em     TIMESTAMP DEFAULT SYSTIMESTAMP
);

CREATE OR REPLACE PROCEDURE ac_recalcular_demo(
  p_evento IN NUMBER DEFAULT 1, p_origem IN NUMBER DEFAULT 1, p_destino IN NUMBER DEFAULT 8) IS
  r NUMBER;
BEGIN
  DELETE FROM ac_rota_trecho WHERE rota_id IN (SELECT id FROM ac_rota WHERE evento_id=p_evento);
  DELETE FROM ac_rota WHERE evento_id=p_evento;
  r := ac_calcular_rota(p_evento,'PADRAO',p_origem,p_destino);
  r := ac_calcular_rota(p_evento,'CADEIRANTE',p_origem,p_destino);
  r := ac_calcular_rota(p_evento,'NEURODIVERGENTE',p_origem,p_destino);
  COMMIT;
END;
/

CREATE OR REPLACE PROCEDURE ac_reportar(
  p_ponto_id IN NUMBER, p_tipo IN VARCHAR2, p_usuario IN VARCHAR2 DEFAULT 'anonimo') IS
  v_evento NUMBER;
BEGIN
  SELECT evento_id INTO v_evento FROM ac_ponto WHERE id=p_ponto_id;
  INSERT INTO ac_reporte(evento_id, ponto_id, tipo, reportado_por)
  VALUES(v_evento, p_ponto_id, p_tipo, p_usuario);
  IF p_tipo='CHEIO' THEN
    UPDATE ac_trecho SET lotacao = LEAST(lotacao+1,5)
     WHERE evento_id=v_evento AND (ponto_a=p_ponto_id OR ponto_b=p_ponto_id);
  ELSIF p_tipo='BARULHO' THEN
    UPDATE ac_trecho SET ruido = LEAST(ruido+1,5)
     WHERE evento_id=v_evento AND (ponto_a=p_ponto_id OR ponto_b=p_ponto_id);
  END IF;
  COMMIT;
  ac_recalcular_demo(v_evento);
END;
/

CREATE OR REPLACE VIEW ac_v_lotacao AS
SELECT p.id AS ponto_id, p.nome, p.tipo,
       COUNT(CASE WHEN r.tipo='CHEIO'   THEN 1 END) AS reportes_cheio,
       COUNT(CASE WHEN r.tipo='BARULHO' THEN 1 END) AS reportes_barulho,
       COUNT(r.id) AS total_reportes
FROM ac_ponto p LEFT JOIN ac_reporte r ON r.ponto_id=p.id
GROUP BY p.id, p.nome, p.tipo;

-- Teste:
-- BEGIN ac_reportar(5,'BARULHO','maria'); END;
-- /
-- SELECT perfil, custo_total, LISTAGG(nome,' -> ') WITHIN GROUP (ORDER BY ordem)
-- FROM ac_v_rota_pontos GROUP BY rota_id, perfil, custo_total ORDER BY perfil;

-- APEX (página do Mapa):
--  item P1_PONTO (Select List: SELECT nome d, id r FROM ac_ponto WHERE evento_id=1)
--  botoes REPORT_CHEIO e REPORT_BARULHO (Submit Page)
--  process PL/SQL:
--    BEGIN
--      IF :REQUEST='REPORT_CHEIO'  THEN ac_reportar(:P1_PONTO,'CHEIO',  :APP_USER); END IF;
--      IF :REQUEST='REPORT_BARULHO' THEN ac_reportar(:P1_PONTO,'BARULHO',:APP_USER); END IF;
--    END;
