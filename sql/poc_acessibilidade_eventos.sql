-- =====================================================================
-- POC — ACESSIBILIDADE EM EVENTOS  (APEX + Autonomous)
-- Rota acessível e sensorial que se adapta ao perfil da pessoa.
-- Modelo genérico: serve para QUALQUER evento (só troca o seed do grafo).
-- Rode no Database Actions -> SQL.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) SCHEMA (grafo do local + perfis + rotas)
-- ---------------------------------------------------------------------
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
    WHERE table_name IN ('AC_ROTA_TRECHO','AC_ROTA','AC_TRECHO','AC_PONTO','AC_EVENTO','AC_PERFIL')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE '||t.table_name||' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

CREATE TABLE ac_evento (
  id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nome    VARCHAR2(200),
  local   VARCHAR2(200)
);

-- Pontos de interesse do evento (nós do grafo)
CREATE TABLE ac_ponto (
  id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id  NUMBER REFERENCES ac_evento(id),
  nome       VARCHAR2(120),
  tipo       VARCHAR2(40),   -- ENTRADA | RAMPA | ELEVADOR | ESCADA | BANHEIRO_ADAP | ACOLHIMENTO | STAND | PALCO | CRUZAMENTO | SAIDA
  x          NUMBER,         -- coordenada na planta (px ou metros)
  y          NUMBER,
  andar      NUMBER DEFAULT 0
);

-- Trechos que ligam dois pontos (arestas do grafo, bidirecionais)
CREATE TABLE ac_trecho (
  id            NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id     NUMBER REFERENCES ac_evento(id),
  ponto_a       NUMBER REFERENCES ac_ponto(id),
  ponto_b       NUMBER REFERENCES ac_ponto(id),
  distancia     NUMBER,             -- metros
  tem_escada    VARCHAR2(1) DEFAULT 'N',   -- S = intransponível p/ cadeira
  acessivel     VARCHAR2(1) DEFAULT 'S',   -- S = rampa/elevador/plano
  ruido         NUMBER DEFAULT 1,   -- 1 (silencioso) a 5 (muito barulhento)
  lotacao       NUMBER DEFAULT 1    -- 1 (vazio) a 5 (multidão)
);

-- Perfis de necessidade (definem os pesos da rota)
CREATE TABLE ac_perfil (
  codigo         VARCHAR2(30) PRIMARY KEY,  -- CADEIRANTE | NEURODIVERGENTE | MOBILIDADE | PADRAO
  nome           VARCHAR2(80),
  evita_escada   VARCHAR2(1),   -- S = escada é intransponível
  peso_ruido     NUMBER,        -- quanto o barulho penaliza a rota
  peso_lotacao   NUMBER         -- quanto a multidão penaliza a rota
);

-- Rota calculada (resultado, para o APEX desenhar)
CREATE TABLE ac_rota (
  id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id   NUMBER,
  perfil      VARCHAR2(30),
  origem_id   NUMBER,
  destino_id  NUMBER,
  custo_total NUMBER,
  criado_em   TIMESTAMP DEFAULT SYSTIMESTAMP
);
CREATE TABLE ac_rota_trecho (
  rota_id   NUMBER REFERENCES ac_rota(id),
  ordem     NUMBER,
  ponto_id  NUMBER
);

-- ---------------------------------------------------------------------
-- 2) SEED — perfis + um evento exemplo (planta simples de 1 andar)
-- ---------------------------------------------------------------------
INSERT INTO ac_perfil VALUES ('CADEIRANTE','Cadeirante / carrinho de bebê','S',1,2);
INSERT INTO ac_perfil VALUES ('NEURODIVERGENTE','Neurodivergente (evita estímulo)','N',6,5);
INSERT INTO ac_perfil VALUES ('MOBILIDADE','Muletas / mobilidade reduzida','S',1,3);
INSERT INTO ac_perfil VALUES ('PADRAO','Sem restrição','N',1,1);
COMMIT;

INSERT INTO ac_evento (nome, local) VALUES ('Feira Tech 2026','Pavilhão Central');
COMMIT;

-- Pontos (planta de exemplo — coordenadas fictícias)
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Entrada Principal','ENTRADA',100,500);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Cruzamento Hall','CRUZAMENTO',300,500);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Escada Central','ESCADA',300,350);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Rampa Norte','RAMPA',300,650);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Corredor Palco (barulho)','CRUZAMENTO',550,350);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Corredor Calmo','CRUZAMENTO',550,650);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Palco Principal','PALCO',700,350);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Banheiro Adaptado','BANHEIRO_ADAP',800,650);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Sala de Acolhimento','ACOLHIMENTO',900,650);
INSERT INTO ac_ponto (evento_id, nome, tipo, x, y) VALUES (1,'Stand Nosso Produto','STAND',150,600);
COMMIT;

-- Trechos (ponto_a, ponto_b, distancia, tem_escada, acessivel, ruido, lotacao)
-- ids: 1 Entrada,2 Cruz Hall,3 Escada,4 Rampa,5 Corr Palco,6 Corr Calmo,7 Palco,8 Banheiro,9 Acolhimento,10 Stand
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,1,10,15,'N','S',1,1);   -- Entrada-Stand
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,1,2,20,'N','S',2,3);    -- Entrada-Cruz Hall
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,2,3,15,'S','N',2,2);    -- Cruz-Escada (ESCADA)
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,2,4,18,'N','S',1,1);    -- Cruz-Rampa (acessível)
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,3,5,25,'N','S',4,4);    -- Escada-Corr Palco
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,4,6,25,'N','S',1,1);    -- Rampa-Corr Calmo
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,5,7,20,'N','S',5,5);    -- Corr Palco-Palco (barulho/multidão)
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,5,6,20,'N','S',3,3);    -- Corr Palco-Corr Calmo (atalho médio)
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,6,8,20,'N','S',1,1);    -- Corr Calmo-Banheiro
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,8,9,10,'N','S',1,1);    -- Banheiro-Acolhimento
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,6,9,25,'N','S',1,1);    -- Corr Calmo-Acolhimento
INSERT INTO ac_trecho (evento_id,ponto_a,ponto_b,distancia,tem_escada,acessivel,ruido,lotacao) VALUES (1,7,8,30,'N','S',3,4);    -- Palco-Banheiro (rota barulhenta)
COMMIT;

-- ---------------------------------------------------------------------
-- 3) MOTOR DE ROTA — Dijkstra ponderado por perfil
--    custo do trecho = distancia + ruido*peso_ruido + lotacao*peso_lotacao
--    escada bloqueada se o perfil evita_escada = 'S'
--    Devolve a rota e grava em ac_rota / ac_rota_trecho para o APEX.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION ac_calcular_rota(
  p_evento  IN NUMBER,
  p_perfil  IN VARCHAR2,
  p_origem  IN NUMBER,
  p_destino IN NUMBER) RETURN NUMBER IS

  v_evita  VARCHAR2(1);
  v_pruido NUMBER;
  v_plot   NUMBER;
  v_rota_id NUMBER;
BEGIN
  SELECT evita_escada, peso_ruido, peso_lotacao
    INTO v_evita, v_pruido, v_plot
  FROM ac_perfil WHERE codigo = p_perfil;

  -- Dijkstra usando WITH ... GRAPH_TABLE não; fazemos com CONNECT-like via tabela temporária em memória.
  -- Implementação simples com coleções PL/SQL.
  DECLARE
    TYPE t_num IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
    dist   t_num;          -- menor custo até cada ponto
    prev   t_num;          -- ponto anterior no caminho
    visit  t_num;          -- 0/1
    v_u    NUMBER;
    v_best NUMBER;
    v_alt  NUMBER;
    v_custo_trecho NUMBER;
    v_bloqueado BOOLEAN;
  BEGIN
    -- inicializa
    FOR p IN (SELECT id FROM ac_ponto WHERE evento_id = p_evento) LOOP
      dist(p.id) := 1e9; prev(p.id) := NULL; visit(p.id) := 0;
    END LOOP;
    dist(p_origem) := 0;

    LOOP
      -- escolhe o não-visitado de menor distância
      v_u := NULL; v_best := 1e9;
      FOR p IN (SELECT id FROM ac_ponto WHERE evento_id = p_evento) LOOP
        IF visit(p.id) = 0 AND dist(p.id) < v_best THEN
          v_best := dist(p.id); v_u := p.id;
        END IF;
      END LOOP;
      EXIT WHEN v_u IS NULL OR v_u = p_destino;
      visit(v_u) := 1;

      -- relaxa vizinhos (grafo bidirecional)
      FOR e IN (
        SELECT ponto_b AS viz, distancia, tem_escada, ruido, lotacao FROM ac_trecho
          WHERE evento_id = p_evento AND ponto_a = v_u
        UNION ALL
        SELECT ponto_a AS viz, distancia, tem_escada, ruido, lotacao FROM ac_trecho
          WHERE evento_id = p_evento AND ponto_b = v_u
      ) LOOP
        v_bloqueado := (v_evita = 'S' AND e.tem_escada = 'S');
        IF NOT v_bloqueado THEN
          v_custo_trecho := e.distancia + e.ruido*v_pruido + e.lotacao*v_plot;
          v_alt := dist(v_u) + v_custo_trecho;
          IF v_alt < dist(e.viz) THEN
            dist(e.viz) := v_alt; prev(e.viz) := v_u;
          END IF;
        END IF;
      END LOOP;
    END LOOP;

    -- grava a rota
    INSERT INTO ac_rota (evento_id, perfil, origem_id, destino_id, custo_total)
    VALUES (p_evento, p_perfil, p_origem, p_destino, ROUND(dist(p_destino),1))
    RETURNING id INTO v_rota_id;

    -- reconstrói o caminho (destino -> origem) e grava na ordem certa
    DECLARE
      TYPE t_path IS TABLE OF NUMBER;
      caminho t_path := t_path();
      v_cur NUMBER := p_destino;
      v_i   NUMBER;
    BEGIN
      IF dist(p_destino) >= 1e9 THEN
        RETURN v_rota_id; -- sem caminho (ex.: cadeirante sem rota acessível)
      END IF;
      WHILE v_cur IS NOT NULL LOOP
        caminho.EXTEND; caminho(caminho.COUNT) := v_cur;
        v_cur := prev(v_cur);
      END LOOP;
      -- inverte
      v_i := 1;
      FOR k IN REVERSE 1..caminho.COUNT LOOP
        INSERT INTO ac_rota_trecho (rota_id, ordem, ponto_id) VALUES (v_rota_id, v_i, caminho(k));
        v_i := v_i + 1;
      END LOOP;
    END;

    COMMIT;
    RETURN v_rota_id;
  END;
END;
/

-- ---------------------------------------------------------------------
-- 4) VIEWS para o APEX (mapa e passo a passo)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW ac_v_rota_pontos AS
SELECT r.id AS rota_id, r.perfil, r.custo_total, rt.ordem,
       p.id AS ponto_id, p.nome, p.tipo, p.x, p.y
FROM   ac_rota r
JOIN   ac_rota_trecho rt ON rt.rota_id = r.id
JOIN   ac_ponto p        ON p.id = rt.ponto_id
ORDER  BY r.id, rt.ordem;

-- Todos os pontos de um evento (para o mapa base do APEX)
CREATE OR REPLACE VIEW ac_v_pontos AS
SELECT id, evento_id, nome, tipo, x, y, andar FROM ac_ponto;

-- ---------------------------------------------------------------------
-- 5) DEMONSTRAÇÃO — mesma origem/destino, perfis diferentes = rotas diferentes
--    Entrada (1) -> Banheiro Adaptado (8)
-- ---------------------------------------------------------------------
DECLARE r NUMBER;
BEGIN
  r := ac_calcular_rota(1,'PADRAO',1,8);
  r := ac_calcular_rota(1,'CADEIRANTE',1,8);       -- deve evitar a escada
  r := ac_calcular_rota(1,'NEURODIVERGENTE',1,8);  -- deve evitar palco (barulho/multidão)
END;
/

-- Ver as rotas geradas (o APEX desenha isso no mapa)
SELECT perfil, custo_total,
       LISTAGG(nome, '  ->  ') WITHIN GROUP (ORDER BY ordem) AS caminho
FROM   ac_v_rota_pontos
GROUP  BY rota_id, perfil, custo_total
ORDER  BY perfil;
