-- =====================================================================
-- 10 — MODELO v2 (aditivo e idempotente; não quebra o evento 1 / APEX)
--  + ac_evento: codigo, dimensões da planta, escala
--  + ac_ponto : codigo estável, bloqueado (ex.: saída interditada)
--  + ac_trecho: via (nome do corredor), valores base p/ reset, bloqueado
--  + ac_perfil: velocidade, descrição
--  + ac_area  : retângulos da planta (o front desenha o mapa sem PNG)
-- =====================================================================
DECLARE
  PROCEDURE ddl(p VARCHAR2) IS
  BEGIN
    EXECUTE IMMEDIATE p;
  EXCEPTION WHEN OTHERS THEN
    -- já existe: coluna(1430) / objeto(955) / índice(1408) / constraint(2261,2275)
    IF SQLCODE NOT IN (-1430, -955, -1408, -2261, -2275) THEN RAISE; END IF;
  END;
BEGIN
  ddl('ALTER TABLE ac_evento ADD (codigo VARCHAR2(30), largura_px NUMBER, altura_px NUMBER, escala_m_px NUMBER, planta_url VARCHAR2(500))');
  ddl('CREATE UNIQUE INDEX ac_evento_uk ON ac_evento(codigo)');

  ddl('ALTER TABLE ac_ponto ADD (codigo VARCHAR2(40), bloqueado VARCHAR2(1) DEFAULT ''N'' NOT NULL)');
  -- evento 1 (legado) não tem codigo: índice só vale para quem tem
  ddl('CREATE UNIQUE INDEX ac_ponto_uk ON ac_ponto(CASE WHEN codigo IS NOT NULL THEN evento_id END, codigo)');

  ddl('ALTER TABLE ac_trecho ADD (via VARCHAR2(120), ruido_base NUMBER, lotacao_base NUMBER, bloqueado VARCHAR2(1) DEFAULT ''N'' NOT NULL)');
  ddl('CREATE INDEX ac_trecho_a_ix ON ac_trecho(evento_id, ponto_a)');
  ddl('CREATE INDEX ac_trecho_b_ix ON ac_trecho(evento_id, ponto_b)');

  ddl('ALTER TABLE ac_perfil ADD (velocidade_ms NUMBER, descricao VARCHAR2(400))');

  -- v2.1: personalização visual por evento
  ddl('ALTER TABLE ac_evento ADD (descricao VARCHAR2(400), origem_padrao VARCHAR2(40))');

  ddl('ALTER TABLE ac_reporte ADD (detalhe VARCHAR2(400))');
  ddl('CREATE INDEX ac_reporte_ev_ix ON ac_reporte(evento_id, criado_em)');

  ddl(q'[CREATE TABLE ac_area (
    id        NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    evento_id NUMBER NOT NULL REFERENCES ac_evento(id),
    codigo    VARCHAR2(40) NOT NULL,
    nome      VARCHAR2(120),
    tipo      VARCHAR2(40),   -- STAND | PALCO | ALIMENTACAO | ACOLHIMENTO | BANHEIRO_ADAP | RAMPA | CORREDOR | TECNICA
    x NUMBER, y NUMBER, largura NUMBER, altura NUMBER,
    CONSTRAINT ac_area_uk UNIQUE (evento_id, codigo)
  )]');
  ddl('ALTER TABLE ac_area ADD (cor VARCHAR2(20), subtitulo VARCHAR2(120))');
END;
/

-- base = valor atual para o que já existia (evento 1)
UPDATE ac_trecho SET ruido_base = ruido, lotacao_base = lotacao WHERE ruido_base IS NULL;
COMMIT;
