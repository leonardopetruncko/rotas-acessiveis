-- =====================================================================
-- 16b — PACKAGE AC_CONVERSA: assistente conversacional do evento (RAG in-database)
--  Pergunta → tipo (AI Vector Search sobre ac_intencao_frase, k-NN) → resposta montada
--  com DADOS REAIS do banco: planta, descrições, programação, lotação/ruído atuais,
--  rota calculada pelo AC_ROTAS para o perfil da pessoa.
--  A resposta INFORMA e oferece ação ("Traçar rota"); a pessoa decide.
-- =====================================================================
CREATE OR REPLACE PACKAGE ac_conversa AUTHID DEFINER AS
  FUNCTION responder_json(p_evento VARCHAR2, p_texto VARCHAR2, p_origem VARCHAR2 DEFAULT NULL,
                          p_perfil VARCHAR2 DEFAULT NULL) RETURN CLOB;
  PROCEDURE api_responder(p_evento VARCHAR2, p_body CLOB);
END ac_conversa;
/

CREATE OR REPLACE PACKAGE BODY ac_conversa AS
  NL CONSTANT VARCHAR2(1) := CHR(10);
  c_lim CONSTANT NUMBER := 0.42;

  TYPE t_txt IS TABLE OF VARCHAR2(200) INDEX BY PLS_INTEGER;

  FUNCTION norm(p VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN ' ' || TRANSLATE(LOWER(p), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') || ' ';
  END;

  FUNCTION agora RETURN VARCHAR2 IS
  BEGIN
    RETURN TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI');
  END;

  FUNCTION nome_ponto(p_ev NUMBER, p_cod VARCHAR2) RETURN VARCHAR2 IS
    l ac_ponto.nome%TYPE;
  BEGIN
    SELECT nome INTO l FROM ac_ponto WHERE evento_id = p_ev AND codigo = p_cod;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  FUNCTION com_artigo(p_via VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN CASE WHEN REGEXP_LIKE(p_via, '^(Rua|Av\.|Avenida|Passagem|Rampa|Arena|Praça|Sala|Área|Vila)') THEN 'na ' ELSE 'no ' END || p_via;
  END;

  FUNCTION nome_perfil(p_cod VARCHAR2) RETURN VARCHAR2 IS
    l ac_perfil.nome%TYPE;
  BEGIN
    SELECT nome INTO l FROM ac_perfil WHERE codigo = p_cod;
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  FUNCTION lista(p t_txt, p_sep VARCHAR2 DEFAULT ', ') RETURN VARCHAR2 IS
    l VARCHAR2(4000);
  BEGIN
    FOR i IN 1 .. p.COUNT LOOP
      l := l || CASE WHEN i > 1 THEN CASE WHEN i = p.COUNT AND p_sep = ', ' THEN ' e ' ELSE p_sep END END || p(i);
    END LOOP;
    RETURN l;
  END;

  -- lugar citado no texto: nome literal (tokens distintivos) ou palavra genérica que só um lugar tem
  FUNCTION lugar_citado(p_ev NUMBER, p_norm VARCHAR2) RETURN VARCHAR2 IS
    l_tok VARCHAR2(100);
    l_best VARCHAR2(40);
    l_len PLS_INTEGER := 0;
  BEGIN
    FOR p IN (SELECT codigo, nome FROM ac_ponto
               WHERE evento_id = p_ev AND tipo NOT IN ('CRUZAMENTO', 'RAMPA') ORDER BY id) LOOP
      FOR k IN 1 .. 8 LOOP
        l_tok := REGEXP_SUBSTR(TRIM(norm(p.nome)), '[a-z0-9]+', 1, k);
        EXIT WHEN l_tok IS NULL;
        CONTINUE WHEN LENGTH(l_tok) < 3 OR l_tok IN ('stand', 'sala', 'das', 'dos', 'cloud', 'saida', 'emergencia',
          'principal', 'fiap', 'area', 'praca', 'adaptado', 'entrada', 'corredor', 'interno', 'rua', 'sul', 'norte',
          'leste', 'oeste', 'microsoft', 'google', 'degraus');
        IF REGEXP_LIKE(p_norm, '[^a-z0-9]' || l_tok || 's?[^a-z0-9]') AND LENGTH(l_tok) > l_len THEN
          l_best := p.codigo; l_len := LENGTH(l_tok);
        END IF;
      END LOOP;
    END LOOP;
    IF l_best IS NOT NULL THEN RETURN l_best; END IF;
    -- genéricos que apontam para um tipo de lugar
    FOR g IN (SELECT 'palco' w, 'PALCO' t FROM dual UNION ALL SELECT 'banheiro', 'BANHEIRO_ADAP' FROM dual
              UNION ALL SELECT 'enfermaria', 'SERVICO' FROM dual UNION ALL SELECT 'comida', 'ALIMENTACAO' FROM dual
              UNION ALL SELECT 'lanche', 'ALIMENTACAO' FROM dual UNION ALL SELECT 'hackathon', 'ARENA' FROM dual) LOOP
      IF INSTR(p_norm, g.w) > 0 THEN
        SELECT MAX(codigo) KEEP (DENSE_RANK FIRST ORDER BY CASE WHEN LOWER(nome) LIKE '%brigada%' THEN 0 ELSE 1 END, id)
          INTO l_best FROM ac_ponto WHERE evento_id = p_ev AND tipo = g.t;
        RETURN l_best;
      END IF;
    END LOOP;
    RETURN NULL;
  END;

  FUNCTION lugar_por_vetor(p_ev NUMBER, p_texto VARCHAR2) RETURN VARCHAR2 IS
    l_cod VARCHAR2(40);
    l_d   NUMBER;
  BEGIN
    SELECT codigo, d INTO l_cod, l_d FROM (
      SELECT codigo, VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(doc_model USING p_texto AS data), COSINE) d
        FROM ac_ponto WHERE evento_id = p_ev AND embedding IS NOT NULL
       ORDER BY d FETCH FIRST 1 ROWS ONLY);
    RETURN CASE WHEN l_d < 0.45 THEN l_cod END;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  -- programação de um lugar (ou do evento): o que está rolando agora / a seguir
  FUNCTION prog_texto(p_ev NUMBER, p_ponto VARCHAR2, p_max PLS_INTEGER DEFAULT 3) RETURN VARCHAR2 IS
    l_agora VARCHAR2(5) := agora;
    l VARCHAR2(4000);
    n PLS_INTEGER := 0;
  BEGIN
    FOR r IN (SELECT titulo, inicio, fim, ruido_prev, ponto FROM ac_programacao
               WHERE evento_id = p_ev AND (p_ponto IS NULL OR ponto = p_ponto)
                 AND inicio <= l_agora AND fim > l_agora ORDER BY inicio) LOOP
      l := l || NL || '• Agora: ' || r.titulo || ' (' || r.inicio || '–' || r.fim || ')'
             || CASE WHEN p_ponto IS NULL THEN ' — ' || nome_ponto(p_ev, r.ponto) END
             || CASE WHEN r.ruido_prev >= 4 THEN ' · barulhento' END;
    END LOOP;
    FOR r IN (SELECT titulo, inicio, fim, ruido_prev, ponto FROM ac_programacao
               WHERE evento_id = p_ev AND (p_ponto IS NULL OR ponto = p_ponto) AND inicio > l_agora
               ORDER BY inicio) LOOP
      n := n + 1;
      EXIT WHEN n > p_max;
      l := l || NL || '• ' || r.inicio || ': ' || r.titulo
             || CASE WHEN p_ponto IS NULL THEN ' — ' || nome_ponto(p_ev, r.ponto) END
             || CASE WHEN r.ruido_prev >= 4 THEN ' · barulhento' END;
    END LOOP;
    RETURN LTRIM(l, NL);
  END;

  -- "onde fica": descrição + corredor + referência + distância/tempo pelo perfil
  FUNCTION descrever_lugar(p_evento VARCHAR2, p_ev NUMBER, p_cod VARCHAR2, p_origem VARCHAR2, p_perfil VARCHAR2) RETURN VARCHAR2 IS
    l_nome  ac_ponto.nome%TYPE;
    l_tipo  ac_ponto.tipo%TYPE;
    l_x NUMBER; l_y NUMBER;
    l_bloq  VARCHAR2(1);
    l_desc  ac_area.descricao%TYPE;
    l_via   ac_trecho.via%TYPE;
    l_viz   ac_ponto.nome%TYPE;
    l_lot   NUMBER; l_rui NUMBER;
    l_txt   VARCHAR2(4000);
    l_rota  JSON_OBJECT_T;
    l_prog  VARCHAR2(4000);
  BEGIN
    SELECT nome, tipo, x, y, bloqueado INTO l_nome, l_tipo, l_x, l_y, l_bloq
      FROM ac_ponto WHERE evento_id = p_ev AND codigo = p_cod;
    SELECT MAX(descricao) INTO l_desc FROM ac_area WHERE evento_id = p_ev AND codigo = 'A_' || p_cod;
    SELECT STATS_MODE(REGEXP_REPLACE(via, ' \(.*\)$')), MAX(lotacao), MAX(ruido) INTO l_via, l_lot, l_rui
      FROM ac_trecho t JOIN ac_ponto p ON p.id IN (t.ponto_a, t.ponto_b)
     WHERE t.evento_id = p_ev AND p.codigo = p_cod AND t.tem_escada = 'N';
    SELECT MAX(nome) KEEP (DENSE_RANK FIRST ORDER BY (x - l_x) * (x - l_x) + (y - l_y) * (y - l_y)) INTO l_viz
      FROM ac_ponto WHERE evento_id = p_ev AND codigo <> p_cod
       AND tipo NOT IN ('CRUZAMENTO', 'RAMPA', 'SAIDA', 'SERVICO', 'BANHEIRO_ADAP');

    l_txt := l_nome || CASE WHEN l_desc IS NOT NULL THEN ': ' || l_desc END;
    l_txt := l_txt || NL || 'Fica ' || com_artigo(NVL(l_via, 'pavilhão')) || CASE WHEN l_viz IS NOT NULL THEN ', perto de ' || l_viz END || '.';
    IF l_bloq = 'S' THEN l_txt := l_txt || NL || '⛔ Atenção: está interditado agora.'; END IF;
    IF l_lot >= 4 OR l_rui >= 4 THEN
      l_txt := l_txt || NL || 'Agora está ' || CASE WHEN l_lot >= 4 THEN 'cheio' END
            || CASE WHEN l_lot >= 4 AND l_rui >= 4 THEN ' e ' END || CASE WHEN l_rui >= 4 THEN 'barulhento' END || ' por ali.';
    END IF;

    IF p_origem IS NOT NULL AND p_origem <> p_cod THEN
      l_rota := JSON_OBJECT_T.parse(ac_rotas.rota_json(p_evento, NVL(p_perfil, 'PADRAO'), p_origem, p_cod));
      IF l_rota.get_string('status') = 'OK' THEN
        l_txt := l_txt || NL || 'Daqui (' || nome_ponto(p_ev, p_origem) || '): ~' || l_rota.get_number('distancia_m')
              || ' m, cerca de ' || l_rota.get_number('tempo_min') || ' min'
              || CASE WHEN NVL(p_perfil, 'PADRAO') <> 'PADRAO' THEN ' no perfil ' || nome_perfil(p_perfil) END
              || CASE WHEN l_rota.get_boolean('tem_escada') THEN ', com degraus no caminho' ELSE ', sem degraus' END || '.';
      ELSE
        l_txt := l_txt || NL || 'Não encontrei caminho sem barreiras até lá para o seu perfil. Procure a equipe do evento.';
      END IF;
    END IF;

    l_prog := prog_texto(p_ev, p_cod, 2);
    IF l_prog IS NOT NULL THEN l_txt := l_txt || NL || l_prog; END IF;
    RETURN l_txt;
  END;

  FUNCTION responder_json(p_evento VARCHAR2, p_texto VARCHAR2, p_origem VARCHAR2 DEFAULT NULL,
                          p_perfil VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_ev      NUMBER;
    l_evnome  ac_evento.nome%TYPE;
    l_evlocal ac_evento.local%TYPE;
    l_evdesc  ac_evento.descricao%TYPE;
    l_norm    VARCHAR2(4000);
    l_vec     VECTOR(384, FLOAT32);
    l_ass     JSON_OBJECT_T;
    l_int     VARCHAR2(30);
    l_metodo  VARCHAR2(30);
    l_conf    NUMBER;
    l_frase   VARCHAR2(400);
    l_d       NUMBER;
    l_lugar   VARCHAR2(40);
    l_origem  VARCHAR2(40) := UPPER(p_origem);
    l_perfil  VARCHAR2(30) := NVL(UPPER(p_perfil), 'PADRAO');
    l_perfil_sug VARCHAR2(30);
    l_resp    VARCHAR2(32767);
    l_acao    JSON_OBJECT_T;
    l_sug     JSON_ARRAY_T := JSON_ARRAY_T();
    o         JSON_OBJECT_T := JSON_OBJECT_T();
    j         JSON_OBJECT_T;
    l_arr     t_txt;
    l_n       NUMBER;
    l_tmp     VARCHAR2(4000);
    l_saida   JSON_OBJECT_T;

    PROCEDURE sugerir(p1 VARCHAR2, p2 VARCHAR2 DEFAULT NULL, p3 VARCHAR2 DEFAULT NULL) IS
    BEGIN
      l_sug.append(p1);
      IF p2 IS NOT NULL THEN l_sug.append(p2); END IF;
      IF p3 IS NOT NULL THEN l_sug.append(p3); END IF;
    END;

    PROCEDURE acao(p_tipo VARCHAR2, p_destino VARCHAR2, p_rotulo VARCHAR2, p_auto BOOLEAN DEFAULT FALSE) IS
    BEGIN
      l_acao := JSON_OBJECT_T();
      l_acao.put('tipo', p_tipo);
      IF p_destino IS NOT NULL THEN l_acao.put('destino', p_destino); END IF;
      l_acao.put('rotulo', p_rotulo);
      l_acao.put('automatica', p_auto);
    END;
  BEGIN
    BEGIN
      SELECT id, nome, local, descricao INTO l_ev, l_evnome, l_evlocal, l_evdesc
        FROM ac_evento WHERE codigo = UPPER(TRIM(p_evento));
    EXCEPTION WHEN NO_DATA_FOUND THEN
      raise_application_error(-20404, 'Evento não encontrado: ' || p_evento);
    END;
    IF p_texto IS NULL OR LENGTH(TRIM(p_texto)) < 1 THEN
      raise_application_error(-20400, 'Parâmetro obrigatório: texto');
    END IF;
    l_norm := norm(SUBSTR(p_texto, 1, 1000));

    -- 0) entendimento de rota/perfil/segurança (AC_ASSISTENTE)
    l_ass := JSON_OBJECT_T.parse(ac_assistente.interpretar_json(p_evento, p_texto));
    IF l_ass.has('origem') THEN l_origem := l_ass.get_object('origem').get_string('codigo'); END IF;
    -- só adota perfil dito explicitamente ("sou cadeirante"); perfil inferido da necessidade fica para o CASE
    IF l_ass.has('perfil') AND l_ass.get_object('perfil').get_string('metodo') <> 'NECESSIDADE' THEN
      l_perfil_sug := l_ass.get_object('perfil').get_string('codigo');
    END IF;
    l_perfil := NVL(l_perfil_sug, l_perfil);
    l_lugar := lugar_citado(l_ev, l_norm);

    -- 1) segurança primeiro
    IF l_ass.has('necessidade') AND l_ass.get_object('necessidade').get_string('metodo') = 'REGRA_SEGURANCA' THEN
      l_int := l_ass.get_object('necessidade').get_string('codigo');
      l_metodo := 'REGRA_SEGURANCA';
    END IF;

    -- 2) tipo de pergunta/necessidade por AI Vector Search (k-NN, voto ponderado)
    IF l_int IS NULL THEN
      SELECT VECTOR_EMBEDDING(doc_model USING p_texto AS data) INTO l_vec FROM dual;
      BEGIN
        SELECT intencao, dmin INTO l_int, l_d FROM (
          SELECT intencao, MIN(d) dmin, SUM(1 - d) score
            FROM (SELECT f.intencao, VECTOR_DISTANCE(f.embedding, l_vec, COSINE) d
                    FROM ac_intencao_frase f JOIN ac_intencao i ON i.codigo = f.intencao
                   WHERE i.categoria IN ('PERGUNTA', 'NECESSIDADE')
                   ORDER BY d FETCH FIRST 5 ROWS ONLY)
           WHERE d < c_lim
           GROUP BY intencao ORDER BY score DESC FETCH FIRST 1 ROWS ONLY);
        l_metodo := 'VECTOR_SEARCH';
        l_conf := ROUND(1 - l_d, 2);
        SELECT frase INTO l_frase FROM (
          SELECT frase FROM ac_intencao_frase WHERE intencao = l_int
           ORDER BY VECTOR_DISTANCE(embedding, l_vec, COSINE) FETCH FIRST 1 ROWS ONLY);
      EXCEPTION WHEN NO_DATA_FOUND THEN l_int := NULL;
      END;
    END IF;

    -- 3) palavra-chave (busca híbrida)
    IF l_int IS NULL THEN
      l_metodo := 'PALAVRA_CHAVE';
      l_int := CASE
        WHEN REGEXP_LIKE(l_norm, '^ *(oi|ola|opa|bom dia|boa tarde|boa noite|e ai|hey|hello)[ !?.,]')
          OR REGEXP_LIKE(l_norm, '(quem e voce|o que voce faz|me ajud|ajuda)') THEN 'Q_SAUDACAO'
        WHEN REGEXP_LIKE(l_norm, '(programac|agenda|horario|que horas|acontecendo|palestra|keynote)') THEN 'Q_PROGRAMACAO'
        WHEN REGEXP_LIKE(l_norm, '(saidas|saida de emergencia|quantas saida)') THEN 'Q_SAIDAS'
        WHEN REGEXP_LIKE(l_norm, '(acessib|rampa|elevador|degrau)') THEN 'Q_ACESSIBILIDADE'
        WHEN REGEXP_LIKE(l_norm, '(cheio|lotad|vazio|tranquil|barulhent|movimentad|muita gente)') THEN 'Q_LOTACAO'
        WHEN REGEXP_LIKE(l_norm, '(onde fica|onde e |onde tem|como chego|como vou|cade |caminho|me leva)') THEN 'Q_ONDE_FICA'
        WHEN REGEXP_LIKE(l_norm, '(o que tem|quais stands|empresas|atrac|visitar|expositor)') THEN
          CASE WHEN l_lugar IS NOT NULL THEN 'Q_SOBRE_LUGAR' ELSE 'Q_O_QUE_TEM' END
        WHEN REGEXP_LIKE(l_norm, '(que evento|qual evento|nome do evento|onde estou|que lugar e esse)') THEN 'Q_EVENTO'
      END;
      IF l_int IS NULL AND l_ass.has('necessidade') THEN
        l_int := l_ass.get_object('necessidade').get_string('codigo');
      END IF;
      IF l_int IS NULL AND l_lugar IS NOT NULL THEN l_int := 'Q_SOBRE_LUGAR'; END IF;
      IF l_int IS NULL AND l_ass.has('destino') THEN l_int := 'Q_ONDE_FICA'; END IF;
    END IF;

    -- desempate por intenção explícita no texto (o vetor erra perguntas curtas e parecidas)
    IF NVL(l_metodo, '-') <> 'REGRA_SEGURANCA' THEN
      IF REGEXP_LIKE(l_norm, '(obrigad|valeu|agradec)') AND LENGTH(l_norm) < 40 THEN
        l_int := 'Q_OBRIGADO'; l_metodo := 'PALAVRA_CHAVE'; l_conf := NULL; l_frase := NULL;
      ELSIF REGEXP_LIKE(l_norm, '(acontecendo|programac|agenda|que horas|horario|comeca|termina)') AND l_int <> 'Q_PROGRAMACAO' THEN
        l_int := 'Q_PROGRAMACAO'; l_metodo := 'PALAVRA_CHAVE'; l_conf := NULL; l_frase := NULL;
      ELSIF l_lugar IS NOT NULL AND REGEXP_LIKE(l_norm, '(me fal|fale sobre|o que e |o que tem n|o que acontece|sobre o |sobre a |como e )')
            AND l_int NOT IN ('Q_SOBRE_LUGAR', 'Q_PROGRAMACAO') THEN
        l_int := 'Q_SOBRE_LUGAR'; l_metodo := 'PALAVRA_CHAVE'; l_conf := NULL; l_frase := NULL;
      ELSIF l_int = 'Q_EVENTO' AND REGEXP_LIKE(l_norm, '(o que tem|quais stands|atrac|visitar|expositor|empresas)') THEN
        l_int := 'Q_O_QUE_TEM'; l_metodo := 'PALAVRA_CHAVE'; l_conf := NULL; l_frase := NULL;
      END IF;
    END IF;

    -- ajustes: "o que tem" + lugar citado = sobre o lugar; necessidade de lugar + "onde" = onde fica
    IF l_int = 'Q_O_QUE_TEM' AND l_lugar IS NOT NULL THEN l_int := 'Q_SOBRE_LUGAR'; END IF;
    IF l_int IN ('Q_ONDE_FICA', 'Q_SOBRE_LUGAR') AND l_lugar IS NULL THEN
      l_lugar := CASE WHEN l_ass.has('destino') THEN l_ass.get_object('destino').get_string('codigo') END;
      IF l_lugar IS NULL THEN l_lugar := lugar_por_vetor(l_ev, p_texto); END IF;
    END IF;
    IF l_lugar = l_origem AND l_int NOT IN ('Q_SOBRE_LUGAR', 'Q_PROGRAMACAO', 'Q_LOTACAO') THEN l_lugar := NULL; END IF;

    -- 4) resposta com dados do banco
    CASE
      WHEN l_int = 'Q_SAUDACAO' THEN
        l_resp := 'Oi! Sou a assistente do ' || l_evnome || '. Posso te contar o que tem no evento, onde fica cada lugar, '
               || 'o que está acontecendo agora, onde está cheio ou tranquilo e qual o melhor caminho pra você — '
               || 'inclusive a saída mais segura. Eu sugiro; quem decide o caminho é você.';
        sugerir('O que tem no evento?', 'O que está acontecendo agora?', 'Onde fica a praça de alimentação?');

      WHEN l_int = 'Q_OBRIGADO' THEN
        l_resp := 'De nada! Se precisar de algo, é só chamar. Em qualquer emergência, toque no botão 🚨 que eu mostro a saída mais segura.';
        sugerir('O que está acontecendo agora?', 'Onde está mais tranquilo agora?');

      WHEN l_int = 'Q_EVENTO' THEN
        SELECT COUNT(CASE WHEN tipo = 'STAND' THEN 1 END), MIN(i.inicio) INTO l_n, l_tmp
          FROM ac_ponto p LEFT JOIN (SELECT MIN(inicio) inicio FROM ac_programacao WHERE evento_id = l_ev) i ON 1 = 1
         WHERE p.evento_id = l_ev;
        l_resp := 'Você está no ' || l_evnome || ' — ' || l_evlocal || '.'
               || CASE WHEN l_evdesc IS NOT NULL THEN ' ' || l_evdesc END
               || NL || 'Tem ' || l_n || ' stands, palco principal, arena, praça de alimentação, brigada e espaços de acessibilidade'
               || ' (Sala de Acolhimento, banheiro adaptado e rampa).';
        SELECT MIN(inicio), MAX(fim) INTO l_tmp, l_frase FROM ac_programacao WHERE evento_id = l_ev;
        IF l_tmp IS NOT NULL THEN
          l_resp := l_resp || NL || 'Programação das ' || l_tmp || ' às ' || l_frase || '.';
          l_frase := NULL;
        END IF;
        sugerir('O que tem no evento?', 'Qual é a programação?', 'O evento é acessível?');

      WHEN l_int = 'Q_O_QUE_TEM' THEN
        l_resp := 'No ' || l_evnome || ' tem:';
        FOR g IN (SELECT grupo, LISTAGG(nome || CASE WHEN subtitulo IS NOT NULL AND grupo <> 'Stands' THEN ' (' || subtitulo || ')' END, ', ')
                         WITHIN GROUP (ORDER BY id) itens
                    FROM (SELECT a.*, CASE WHEN tipo = 'STAND' THEN 'Stands' WHEN tipo IN ('PALCO', 'ARENA') THEN 'Palco e arena'
                                           WHEN tipo IN ('ALIMENTACAO', 'SERVICO') THEN 'Serviços'
                                           WHEN tipo IN ('ACOLHIMENTO', 'BANHEIRO_ADAP', 'RAMPA') THEN 'Acessibilidade' END grupo
                            FROM ac_area a WHERE evento_id = l_ev)
                   WHERE grupo IS NOT NULL
                   GROUP BY grupo ORDER BY DECODE(grupo, 'Stands', 1, 'Palco e arena', 2, 'Serviços', 3, 4)) LOOP
          l_resp := l_resp || NL || '• ' || g.grupo || ': ' || g.itens;
        END LOOP;
        l_tmp := prog_texto(l_ev, NULL, 1);
        IF l_tmp IS NOT NULL THEN l_resp := l_resp || NL || NL || l_tmp; END IF;
        sugerir('O que tem no stand da Oracle?', 'Onde fica a Arena Tech4Change?', 'Onde está mais tranquilo agora?');

      WHEN l_int IN ('Q_ONDE_FICA', 'Q_SOBRE_LUGAR') THEN
        IF l_lugar IS NULL THEN
          l_resp := 'Qual lugar você procura? Por exemplo: Praça de Alimentação, Palco Principal, Arena Tech4Change, '
                 || 'Sala de Acolhimento, Banheiro Adaptado ou o stand de alguma empresa.';
          sugerir('Onde fica a praça de alimentação?', 'O que tem no evento?');
        ELSE
          l_resp := descrever_lugar(p_evento, l_ev, l_lugar, l_origem, l_perfil);
          acao('ROTA', l_lugar, 'Traçar rota até ' || nome_ponto(l_ev, l_lugar));
          sugerir('O que está acontecendo agora?', 'Onde está mais cheio?');
        END IF;

      WHEN l_int = 'Q_PROGRAMACAO' THEN
        IF l_lugar IS NOT NULL THEN
          l_resp := 'Programação em ' || nome_ponto(l_ev, l_lugar) || ' (agora são ' || agora || '):';
          FOR r IN (SELECT inicio, fim, titulo, ruido_prev FROM ac_programacao
                     WHERE evento_id = l_ev AND ponto = l_lugar ORDER BY inicio) LOOP
            l_resp := l_resp || NL || '• ' || r.inicio || '–' || r.fim || ': ' || r.titulo
                   || CASE WHEN r.fim <= agora THEN ' (já terminou)' WHEN r.inicio <= agora THEN ' (acontecendo agora)' ELSE ' (ainda vai começar)' END
                   || CASE WHEN r.ruido_prev >= 4 THEN ' · barulhento' END;
          END LOOP;
          IF l_resp NOT LIKE '%•%' THEN
            l_resp := 'Não há atividades programadas em ' || nome_ponto(l_ev, l_lugar) || '.';
          END IF;
          acao('ROTA', l_lugar, 'Traçar rota até ' || nome_ponto(l_ev, l_lugar));
        ELSE
          l_tmp := prog_texto(l_ev, NULL, 4);
          IF l_tmp IS NULL THEN
            l_resp := 'A programação de hoje já terminou (agora são ' || agora || '). Como foi o dia:';
            FOR r IN (SELECT inicio, fim, titulo, ponto FROM ac_programacao WHERE evento_id = l_ev ORDER BY inicio) LOOP
              l_resp := l_resp || NL || '• ' || r.inicio || '–' || r.fim || ': ' || r.titulo || ' — ' || nome_ponto(l_ev, r.ponto);
            END LOOP;
          ELSE
            l_resp := 'Agora são ' || agora || ':' || NL || l_tmp;
          END IF;
          l_resp := l_resp || NL || 'Se barulho te incomoda, evite os itens marcados como barulhentos.';
        END IF;
        sugerir('Onde fica a Arena Tech4Change?', 'Onde está mais tranquilo agora?');

      WHEN l_int = 'Q_ACESSIBILIDADE' THEN
        l_resp := 'Recursos de acessibilidade no ' || l_evnome || ':';
        FOR a IN (SELECT nome, descricao FROM ac_area WHERE evento_id = l_ev
                   AND tipo IN ('RAMPA', 'BANHEIRO_ADAP', 'ACOLHIMENTO') ORDER BY tipo) LOOP
          l_resp := l_resp || NL || '• ' || a.nome || CASE WHEN a.descricao IS NOT NULL THEN ': ' || a.descricao END;
        END LOOP;
        SELECT LISTAGG(DISTINCT via, ', ') WITHIN GROUP (ORDER BY via) INTO l_tmp
          FROM ac_trecho WHERE evento_id = l_ev AND tem_escada = 'S';
        IF l_tmp IS NOT NULL THEN l_resp := l_resp || NL || '• Atenção, têm degraus: ' || l_tmp || '.'; END IF;
        l_resp := l_resp || NL || 'Escolha o seu perfil (cadeirante, mobilidade reduzida ou sensível a estímulos) e eu calculo rotas sem essas barreiras.';
        sugerir('Onde fica o banheiro adaptado?', 'Quais são as saídas?', 'Onde está mais tranquilo agora?');

      WHEN l_int = 'Q_LOTACAO' THEN
        IF l_lugar IS NOT NULL THEN
          SELECT MAX(lotacao), MAX(ruido) INTO l_n, l_d FROM ac_trecho t JOIN ac_ponto p ON p.id IN (t.ponto_a, t.ponto_b)
           WHERE t.evento_id = l_ev AND p.codigo = l_lugar;
          l_resp := 'Perto de ' || nome_ponto(l_ev, l_lugar) || ' agora: lotação ' || l_n || '/5 e ruído ' || l_d || '/5.';
        ELSE
          SELECT LISTAGG(via, ', ') WITHIN GROUP (ORDER BY lot DESC) INTO l_tmp FROM (
            SELECT REGEXP_REPLACE(via, ' \(.*\)$') via, MAX(lotacao) lot FROM ac_trecho
             WHERE evento_id = l_ev AND lotacao >= 4 GROUP BY REGEXP_REPLACE(via, ' \(.*\)$')
             ORDER BY lot DESC FETCH FIRST 3 ROWS ONLY);
          l_resp := CASE WHEN l_tmp IS NOT NULL THEN 'Mais cheio agora: ' || l_tmp || '.' ELSE 'Nenhum corredor está muito cheio agora.' END;
          SELECT LISTAGG(via, ', ') WITHIN GROUP (ORDER BY via) INTO l_tmp FROM (
            SELECT REGEXP_REPLACE(via, ' \(.*\)$') via FROM ac_trecho WHERE evento_id = l_ev
             GROUP BY REGEXP_REPLACE(via, ' \(.*\)$') HAVING MAX(lotacao) <= 2 AND MAX(ruido) <= 1);
          IF l_tmp IS NOT NULL THEN l_resp := l_resp || NL || 'Mais tranquilo: ' || l_tmp || '.'; END IF;
          SELECT LISTAGG(via, ', ') WITHIN GROUP (ORDER BY rui DESC) INTO l_tmp FROM (
            SELECT REGEXP_REPLACE(via, ' \(.*\)$') via, MAX(ruido) rui FROM ac_trecho
             WHERE evento_id = l_ev AND ruido >= 4 GROUP BY REGEXP_REPLACE(via, ' \(.*\)$')
             ORDER BY rui DESC FETCH FIRST 3 ROWS ONLY);
          IF l_tmp IS NOT NULL THEN l_resp := l_resp || NL || 'Mais barulhento: ' || l_tmp || '.'; END IF;
        END IF;
        SELECT COUNT(*) INTO l_n FROM ac_reporte WHERE evento_id = l_ev AND criado_em > SYSTIMESTAMP - INTERVAL '30' MINUTE;
        l_resp := l_resp || NL || 'Baseado nos dados ao vivo do evento' || CASE WHEN l_n > 0 THEN ' e em ' || l_n || ' reporte(s) dos últimos 30 min' END || '.';
        IF l_ass.has('necessidade') AND l_ass.get_object('necessidade').get_string('codigo') = 'CRISE_SENSORIAL' OR l_perfil = 'NEURODIVERGENTE' THEN
          SELECT MAX(codigo) INTO l_tmp FROM ac_ponto WHERE evento_id = l_ev AND tipo = 'ACOLHIMENTO';
          IF l_tmp IS NOT NULL THEN acao('ROTA', l_tmp, 'Ir para a Sala de Acolhimento'); END IF;
        END IF;
        sugerir('Onde fica a Sala de Acolhimento?', 'O que está acontecendo agora?');

      WHEN l_int = 'Q_SAIDAS' THEN
        l_resp := 'Saídas do ' || l_evnome || ':';
        FOR s IN (SELECT p.codigo, p.nome, p.bloqueado,
                         (SELECT MAX(t.tem_escada) FROM ac_trecho t WHERE t.evento_id = l_ev AND p.id IN (t.ponto_a, t.ponto_b)) escada
                    FROM ac_ponto p WHERE p.evento_id = l_ev AND p.tipo = 'SAIDA' ORDER BY p.id) LOOP
          l_resp := l_resp || NL || '• ' || s.nome || ' — '
                 || CASE WHEN s.bloqueado = 'S' THEN '⛔ interditada' WHEN s.escada = 'S' THEN 'liberada, com degraus' ELSE 'liberada, sem degraus' END;
        END LOOP;
        IF l_origem IS NOT NULL THEN
          l_saida := JSON_OBJECT_T.parse(ac_rotas.rota_saida_json(p_evento, l_perfil, l_origem));
          IF l_saida.get_string('status') = 'OK' THEN
            l_resp := l_resp || NL || 'Pra você, a partir de ' || nome_ponto(l_ev, l_origem) || ', a mais indicada é '
                   || l_saida.get_object('saida_sugerida').get_string('nome') || ' (~' || l_saida.get_number('distancia_m') || ' m).';
          END IF;
        END IF;
        acao('SAIDA', NULL, 'Mostrar a saída mais segura');
        sugerir('O evento é acessível?', 'Onde fica a brigada?');

      WHEN l_int = 'EMERGENCIA' THEN
        l_resp := '🚨 Mostrando agora a saída mais segura pra você. Mantenha a calma, siga a sinalização e as orientações da brigada.'
               || NL || 'Se alguém estiver ferido, avise a equipe ou ligue 193 (Bombeiros) / 192 (SAMU).';
        acao('SAIDA', NULL, 'Ver saída mais segura', TRUE);

      WHEN l_int = 'MAL_ESTAR' THEN
        SELECT MAX(codigo) KEEP (DENSE_RANK FIRST ORDER BY CASE WHEN LOWER(nome) LIKE '%brigada%' THEN 0 ELSE 1 END, id)
          INTO l_tmp FROM ac_ponto WHERE evento_id = l_ev AND tipo = 'SERVICO';
        l_resp := 'Sinto muito. Se for grave, peça ajuda a qualquer pessoa da equipe agora ou ligue 192 (SAMU).';
        IF l_tmp IS NOT NULL THEN
          l_resp := l_resp || NL || descrever_lugar(p_evento, l_ev, l_tmp, l_origem, l_perfil);
          acao('ROTA', l_tmp, 'Traçar rota até a brigada');
        END IF;

      WHEN l_int IN ('CRISE_SENSORIAL', 'BANHEIRO', 'COMIDA', 'PALESTRA') THEN
        IF l_lugar IS NULL OR l_int = 'CRISE_SENSORIAL' THEN
          SELECT MAX(p.codigo) KEEP (DENSE_RANK FIRST ORDER BY p.id) INTO l_lugar
            FROM ac_ponto p JOIN ac_intencao i ON i.destino_tipo = p.tipo
           WHERE p.evento_id = l_ev AND i.codigo = l_int;
          IF l_int = 'CRISE_SENSORIAL' THEN l_perfil := 'NEURODIVERGENTE'; l_perfil_sug := 'NEURODIVERGENTE'; END IF;
        END IF;
        l_resp := CASE l_int WHEN 'CRISE_SENSORIAL' THEN 'Vamos achar um lugar calmo. Respira fundo — eu te guio por um caminho com menos barulho e menos gente.' || NL
                             ELSE NULL END;
        IF l_lugar IS NOT NULL THEN
          l_resp := l_resp || descrever_lugar(p_evento, l_ev, l_lugar, l_origem, l_perfil);
          acao('ROTA', l_lugar, 'Traçar rota até ' || nome_ponto(l_ev, l_lugar));
        END IF;

      ELSE
        l_resp := 'Não entendi bem. Posso responder coisas como: que evento é esse, o que tem aqui, onde fica um lugar, '
               || 'a programação, onde está cheio, quais são as saídas — ou calcular uma rota pra você.';
        l_metodo := NULL;
        sugerir('O que tem no evento?', 'Onde fica a praça de alimentação?', 'O que está acontecendo agora?');
    END CASE;

    IF l_perfil_sug IS NOT NULL AND (p_perfil IS NULL OR UPPER(p_perfil) <> l_perfil_sug) THEN
      l_resp := l_resp || NL || '(Sugeri o perfil ' || nome_perfil(l_perfil_sug) || ' — pode trocar se não for você.)';
    END IF;

    o.put('intencao', l_int);
    IF l_metodo IS NOT NULL THEN
      j := JSON_OBJECT_T();
      j.put('metodo', l_metodo);
      IF l_conf IS NOT NULL THEN j.put('confianca', l_conf); END IF;
      IF l_frase IS NOT NULL THEN j.put('frase_parecida', l_frase); END IF;
      o.put('explicacao', j);
    END IF;
    o.put('resposta', l_resp);
    IF l_lugar IS NOT NULL THEN
      j := JSON_OBJECT_T(); j.put('codigo', l_lugar); j.put('nome', nome_ponto(l_ev, l_lugar));
      o.put('lugar', j);
    END IF;
    IF l_acao IS NOT NULL THEN o.put('acao', l_acao); END IF;
    j := JSON_OBJECT_T();
    IF l_origem IS NOT NULL THEN j.put('origem', l_origem); END IF;
    IF l_perfil_sug IS NOT NULL THEN j.put('perfil', l_perfil_sug); END IF;
    o.put('contexto', j);
    o.put('sugestoes', l_sug);
    RETURN o.to_clob;
  END;

  PROCEDURE api_responder(p_evento VARCHAR2, p_body CLOB) IS
    j     JSON_OBJECT_T;
    l_res CLOB;
    l_off PLS_INTEGER := 1;
    o     JSON_OBJECT_T;
  BEGIN
    BEGIN
      j := JSON_OBJECT_T.parse(NVL(p_body, '{}'));
    EXCEPTION WHEN OTHERS THEN raise_application_error(-20400, 'Corpo JSON inválido');
    END;
    l_res := responder_json(p_evento, j.get_string('texto'), j.get_string('origem'), j.get_string('perfil'));
    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    HTP.p('Cache-Control: no-store');
    OWA_UTIL.http_header_close;
    WHILE l_off <= DBMS_LOB.getlength(l_res) LOOP
      HTP.prn(DBMS_LOB.substr(l_res, 8000, l_off));
      l_off := l_off + 8000;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    o := JSON_OBJECT_T();
    o.put('status', 'ERRO');
    o.put('mensagem', REGEXP_REPLACE(SQLERRM, '^ORA-\d+: ', ''));
    OWA_UTIL.status_line(CASE SQLCODE WHEN -20400 THEN 400 WHEN -20404 THEN 404 ELSE 500 END, NULL, FALSE);
    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    OWA_UTIL.http_header_close;
    HTP.prn(o.to_string);
  END;
END ac_conversa;
/

BEGIN
  ORDS.define_template('rotas.v1', 'eventos/:evento/conversa');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/conversa', 'POST', ORDS.source_type_plsql,
    'BEGIN ac_conversa.api_responder(:evento, :body_text); END;');
  COMMIT;
END;
/

SELECT object_name, object_type, status FROM user_objects WHERE object_name = 'AC_CONVERSA';
