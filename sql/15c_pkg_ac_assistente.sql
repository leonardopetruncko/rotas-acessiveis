-- =====================================================================
-- 15c — PACKAGE AC_ASSISTENTE: entende o pedido da pessoa (Vector Search in-database)
--  1) necessidade: k-NN (k=5) por VECTOR_DISTANCE COSINE sobre ac_intencao_frase, voto ponderado
--  2) perfil: vizinho mais próximo da categoria PERFIL com limiar apertado
--  3) guarda-corpo de segurança: fogo/fumaça/desmaio NUNCA dependem só de similaridade
--  4) lugares: menção literal ao nome (híbrido) + busca vetorial no trecho "estou no ... / ir para ..."
--  Resposta explicável: confiança, frase de exemplo mais parecida, método usado.
--  A IA INTERPRETA e SUGERE; a pessoa confirma na tela.
-- =====================================================================
CREATE OR REPLACE PACKAGE ac_assistente AUTHID DEFINER AS
  FUNCTION interpretar_json(p_evento VARCHAR2, p_texto VARCHAR2) RETURN CLOB;
  PROCEDURE api_interpretar(p_evento VARCHAR2, p_body CLOB);
END ac_assistente;
/

CREATE OR REPLACE PACKAGE BODY ac_assistente AS
  c_lim_necessidade CONSTANT NUMBER := 0.42;  -- distância cosseno máx. p/ aceitar o vetor (confiança >= 0.58)
  c_lim_perfil      CONSTANT NUMBER := 0.25;
  c_lim_lugar       CONSTANT NUMBER := 0.45;

  FUNCTION norm(p VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN ' ' || TRANSLATE(LOWER(p), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') || ' ';
  END;

  FUNCTION generica(p VARCHAR2) RETURN BOOLEAN IS
  BEGIN
    RETURN LENGTH(p) < 3 OR p IN ('stand', 'sala', 'das', 'dos', 'cloud', 'saida', 'emergencia', 'principal', 'fiap',
      'area', 'praca', 'banheiro', 'adaptado', 'entrada', 'corredor', 'interno', 'rua', 'sul', 'norte', 'leste', 'oeste',
      'palco', 'microsoft', 'google');
  END;

  -- trecho logo após "estou no/na/em", "ir para/pra"... até vírgula/ponto
  FUNCTION trecho_apos(p_norm VARCHAR2, p_gatilho VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN TRIM(REGEXP_SUBSTR(p_norm, p_gatilho || ' ([^,.;!?]+)', 1, 1, NULL, REGEXP_COUNT(p_gatilho, '\(') + 1));
  END;

  FUNCTION lugar_por_vetor(p_evento NUMBER, p_trecho VARCHAR2, o_dist OUT NUMBER) RETURN VARCHAR2 IS
    l_cod ac_ponto.codigo%TYPE;
  BEGIN
    IF p_trecho IS NULL OR LENGTH(p_trecho) < 3 THEN RETURN NULL; END IF;
    SELECT codigo, d INTO l_cod, o_dist FROM (
      SELECT codigo, VECTOR_DISTANCE(embedding, VECTOR_EMBEDDING(doc_model USING p_trecho AS data), COSINE) d
        FROM ac_ponto WHERE evento_id = p_evento AND embedding IS NOT NULL
       ORDER BY d FETCH FIRST 1 ROWS ONLY);
    RETURN CASE WHEN o_dist < c_lim_lugar THEN l_cod END;
  EXCEPTION WHEN NO_DATA_FOUND THEN RETURN NULL;
  END;

  FUNCTION interpretar_json(p_evento VARCHAR2, p_texto VARCHAR2) RETURN CLOB IS
    l_ev      NUMBER;
    l_norm    VARCHAR2(4000);
    l_vec     VECTOR(384, FLOAT32);
    o         JSON_OBJECT_T := JSON_OBJECT_T();
    j         JSON_OBJECT_T;
    -- necessidade
    l_int     ac_intencao.codigo%TYPE;
    l_int_d   NUMBER;
    l_int_fr  VARCHAR2(400);
    l_metodo  VARCHAR2(40) := 'VECTOR_SEARCH';
    l_modo    ac_intencao.modo%TYPE;
    l_dtipo   ac_intencao.destino_tipo%TYPE;
    l_psug    ac_intencao.perfil_sugerido%TYPE;
    l_idesc   ac_intencao.descricao%TYPE;
    -- perfil
    l_perfil  VARCHAR2(30);
    l_pf_d    NUMBER;
    l_pf_fr   VARCHAR2(400);
    -- lugares
    l_origem  ac_ponto.codigo%TYPE;
    l_destino ac_ponto.codigo%TYPE;
    l_o_met   VARCHAR2(20);
    l_d_met   VARCHAR2(20);
    l_dist    NUMBER;
    l_tok     VARCHAR2(100);
    l_pos     PLS_INTEGER;
    l_antes   VARCHAR2(100);
    l_resp    VARCHAR2(2000);
    l_nome    ac_ponto.nome%TYPE;
  BEGIN
    SELECT id INTO l_ev FROM ac_evento WHERE codigo = UPPER(TRIM(p_evento));
    IF p_texto IS NULL OR LENGTH(TRIM(p_texto)) < 2 THEN
      raise_application_error(-20400, 'Parâmetro obrigatório: texto');
    END IF;
    l_norm := norm(SUBSTR(p_texto, 1, 1000));
    SELECT VECTOR_EMBEDDING(doc_model USING p_texto AS data) INTO l_vec FROM dual; -- operador SQL, não PL/SQL

    -- 1) necessidade: k-NN com voto ponderado (1 - distância)
    BEGIN
      SELECT intencao, dmin INTO l_int, l_int_d FROM (
        SELECT intencao, MIN(d) dmin, SUM(1 - d) score
          FROM (SELECT f.intencao, VECTOR_DISTANCE(f.embedding, l_vec, COSINE) d
                  FROM ac_intencao_frase f JOIN ac_intencao i ON i.codigo = f.intencao
                 WHERE i.categoria = 'NECESSIDADE'
                 ORDER BY d FETCH FIRST 5 ROWS ONLY)
         WHERE d < c_lim_necessidade
         GROUP BY intencao ORDER BY score DESC FETCH FIRST 1 ROWS ONLY);
    EXCEPTION WHEN NO_DATA_FOUND THEN l_int := NULL;
    END;

    -- emergência NUNCA por similaridade fraca (evita alarme falso): exige distância <= 0.20
    IF l_int = 'EMERGENCIA' AND l_int_d > 0.20 THEN l_int := NULL; END IF;

    -- 3) guarda-corpo de segurança (regra explícita > similaridade)
    IF REGEXP_LIKE(l_norm, '(fogo|fumaca|incendio|queimad|evacu|explos|desab|teto|caindo|tiroteio|pisote|alarme|choque eletrico)') THEN
      l_int := 'EMERGENCIA'; l_metodo := 'REGRA_SEGURANCA';
    ELSIF REGEXP_LIKE(l_norm, '(desmai|dor no peito|infart|convuls|sangr|machuc|passando mal|nao consigo respirar|caiu|bateu a cabeca|enjoad|vista escur|tontur)') THEN
      l_int := 'MAL_ESTAR'; l_metodo := 'REGRA_SEGURANCA';
    END IF;

    -- vetor sem confiança suficiente -> palavra-chave (busca híbrida)
    IF l_int IS NULL THEN
      l_metodo := 'PALAVRA_CHAVE';
      l_int := CASE
        WHEN REGEXP_LIKE(l_norm, '(saida|sair daqui|fugir|fujo|socorro|perigo|emergencia)') THEN 'EMERGENCIA'
        WHEN REGEXP_LIKE(l_norm, '(banheiro|sanitario|toalete| wc |lavar as maos|xixi)') THEN 'BANHEIRO'
        WHEN REGEXP_LIKE(l_norm, '(barulho|silencio|calm|crise|ansios|sobrecarga|nervos|multidao|som alto)') THEN 'CRISE_SENSORIAL'
        WHEN REGEXP_LIKE(l_norm, '(fome|comer|comida|lanche|beber|agua|refrigerante|cafe)') THEN 'COMIDA'
        WHEN REGEXP_LIKE(l_norm, '(palestra|keynote|apresentacao| show )') THEN 'PALESTRA'
        WHEN REGEXP_LIKE(l_norm, '(medico|enfermaria|brigada|tontu|tonto|mal estar)') THEN 'MAL_ESTAR'
      END;
      l_int_d := NULL;
    END IF;

    IF l_int IS NOT NULL THEN
      SELECT descricao, modo, destino_tipo, perfil_sugerido INTO l_idesc, l_modo, l_dtipo, l_psug
        FROM ac_intencao WHERE codigo = l_int;
      SELECT frase, d INTO l_int_fr, l_dist FROM (
        SELECT frase, VECTOR_DISTANCE(embedding, l_vec, COSINE) d FROM ac_intencao_frase
         WHERE intencao = l_int ORDER BY d FETCH FIRST 1 ROWS ONLY);
      l_int_d := NVL(l_int_d, l_dist);
    END IF;

    -- 2) perfil explícito ("sou cadeirante", "estou de muleta")
    BEGIN
      SELECT i.perfil_sugerido, x.d, x.frase INTO l_perfil, l_pf_d, l_pf_fr FROM (
        SELECT f.intencao, f.frase, VECTOR_DISTANCE(f.embedding, l_vec, COSINE) d
          FROM ac_intencao_frase f JOIN ac_intencao i ON i.codigo = f.intencao
         WHERE i.categoria = 'PERFIL' ORDER BY d FETCH FIRST 1 ROWS ONLY) x
        JOIN ac_intencao i ON i.codigo = x.intencao
       WHERE x.d < c_lim_perfil;
    EXCEPTION WHEN NO_DATA_FOUND THEN l_perfil := NULL;
    END;
    IF l_perfil IS NULL AND REGEXP_LIKE(l_norm, '(cadeira de rodas|cadeirante)') THEN l_perfil := 'CADEIRANTE'; END IF;
    IF l_perfil IS NULL AND REGEXP_LIKE(l_norm, '(muleta|bengala|andador)') THEN l_perfil := 'MOBILIDADE'; END IF;
    IF l_perfil IS NULL AND REGEXP_LIKE(l_norm, '(autis| tea | tdah|neurodiver)') THEN l_perfil := 'NEURODIVERGENTE'; END IF;
    IF l_perfil IS NULL THEN l_perfil := l_psug; END IF;

    -- 4a) lugares por menção literal (híbrido)
    FOR p IN (SELECT codigo, nome FROM ac_ponto
               WHERE evento_id = l_ev AND embedding IS NOT NULL ORDER BY id) LOOP
      FOR k IN 1 .. 8 LOOP
        l_tok := REGEXP_SUBSTR(TRIM(norm(p.nome)), '[a-z0-9]+', 1, k);
        EXIT WHEN l_tok IS NULL;
        CONTINUE WHEN generica(l_tok);
        l_pos := REGEXP_INSTR(l_norm, '[^a-z0-9]' || l_tok || '[^a-z0-9]');
        IF l_pos > 0 THEN
          l_antes := SUBSTR(l_norm, GREATEST(1, l_pos - 30), LEAST(l_pos, 30));
          IF l_origem IS NULL AND REGEXP_LIKE(l_antes, '(estou|to |ta |aqui|perto d|lado d|saindo d|frente d|dentro d)') THEN
            l_origem := p.codigo; l_o_met := 'PALAVRA_CHAVE';
          ELSIF l_destino IS NULL AND REGEXP_LIKE(l_antes, '(para |pra |ate |ir |cheg|onde fica|quero|preciso)') THEN
            l_destino := p.codigo; l_d_met := 'PALAVRA_CHAVE';
          END IF;
          EXIT;
        END IF;
      END LOOP;
    END LOOP;

    -- 4b) lugares por vetor no trecho da frase
    IF l_origem IS NULL THEN
      l_origem := lugar_por_vetor(l_ev, trecho_apos(l_norm, '(estou|to|fiquei) (no|na|em|perto do|perto da|ao lado do|ao lado da)'), l_dist);
      IF l_origem IS NOT NULL THEN l_o_met := 'VECTOR_SEARCH'; END IF;
    END IF;
    IF l_destino IS NULL AND l_int IS NULL THEN
      l_destino := lugar_por_vetor(l_ev, trecho_apos(l_norm, '(ir para|ir pra|ir ao|ir a|chegar no|chegar na|onde fica|onde e)'), l_dist);
      IF l_destino IS NOT NULL THEN l_d_met := 'VECTOR_SEARCH'; END IF;
    END IF;

    -- destino a partir da necessidade
    IF l_destino IS NULL AND l_dtipo IS NOT NULL AND l_dtipo <> 'SAIDA' THEN
      BEGIN
        SELECT codigo INTO l_destino FROM (
          SELECT codigo FROM ac_ponto WHERE evento_id = l_ev AND tipo = l_dtipo AND codigo IS NOT NULL
           ORDER BY CASE WHEN LOWER(nome) LIKE '%brigada%' OR LOWER(nome) LIKE '%enfermaria%' THEN 0 ELSE 1 END, id
           FETCH FIRST 1 ROWS ONLY);
        l_d_met := 'NECESSIDADE';
      EXCEPTION WHEN NO_DATA_FOUND THEN NULL;
      END;
    END IF;

    -- JSON explicável
    o.put('texto', p_texto);
    o.put('entendido', l_int IS NOT NULL OR l_perfil IS NOT NULL OR l_origem IS NOT NULL OR l_destino IS NOT NULL);
    IF l_int IS NOT NULL THEN
      j := JSON_OBJECT_T();
      j.put('codigo', l_int); j.put('descricao', l_idesc);
      IF l_metodo = 'VECTOR_SEARCH' THEN j.put('confianca', ROUND(GREATEST(0, 1 - l_int_d), 2)); END IF;
      j.put('frase_parecida', l_int_fr); j.put('metodo', l_metodo);
      o.put('necessidade', j);
    END IF;
    IF l_perfil IS NOT NULL THEN
      j := JSON_OBJECT_T();
      j.put('codigo', l_perfil);
      IF l_pf_d IS NOT NULL THEN
        j.put('confianca', ROUND(1 - l_pf_d, 2)); j.put('frase_parecida', l_pf_fr); j.put('metodo', 'VECTOR_SEARCH');
      ELSE
        j.put('metodo', CASE WHEN l_psug = l_perfil THEN 'NECESSIDADE' ELSE 'PALAVRA_CHAVE' END);
      END IF;
      o.put('perfil', j);
    END IF;
    IF l_origem IS NOT NULL THEN
      SELECT nome INTO l_nome FROM ac_ponto WHERE evento_id = l_ev AND codigo = l_origem;
      j := JSON_OBJECT_T(); j.put('codigo', l_origem); j.put('nome', l_nome); j.put('metodo', l_o_met);
      o.put('origem', j);
    END IF;
    IF l_destino IS NOT NULL THEN
      SELECT nome INTO l_nome FROM ac_ponto WHERE evento_id = l_ev AND codigo = l_destino;
      j := JSON_OBJECT_T(); j.put('codigo', l_destino); j.put('nome', l_nome); j.put('metodo', l_d_met);
      o.put('destino', j);
    END IF;
    o.put('modo', CASE WHEN l_modo = 'SAIDA' THEN 'saida' WHEN l_destino IS NOT NULL THEN 'rota' END);

    -- resposta em linguagem natural (informa; a pessoa decide)
    IF l_origem IS NOT NULL THEN
      SELECT nome INTO l_nome FROM ac_ponto WHERE evento_id = l_ev AND codigo = l_origem;
      l_resp := 'você está em ' || l_nome;
    END IF;
    IF l_modo = 'SAIDA' THEN
      l_resp := l_resp || CASE WHEN l_resp IS NOT NULL THEN ' e ' END || 'precisa sair com segurança';
    ELSIF l_destino IS NOT NULL THEN
      SELECT nome INTO l_nome FROM ac_ponto WHERE evento_id = l_ev AND codigo = l_destino;
      l_resp := l_resp || CASE WHEN l_resp IS NOT NULL THEN ' e ' END || 'quer chegar em ' || l_nome;
    END IF;
    IF l_resp IS NOT NULL THEN l_resp := 'Entendi: ' || l_resp || '.'; END IF;
    IF l_perfil IS NOT NULL THEN
      SELECT nome INTO l_nome FROM ac_perfil WHERE codigo = l_perfil;
      l_resp := l_resp || ' Sugeri o perfil ' || l_nome || ' — pode trocar se não for você.';
    END IF;
    IF l_resp IS NULL THEN
      l_resp := 'Não entendi ainda. Tente algo como: "estou no stand da Oracle, o barulho está insuportável" ou "onde fica o banheiro adaptado?".';
    END IF;
    o.put('resposta', TRIM(l_resp));
    o.put('modelo', 'DOC_MODEL (all_MiniLM_L12_v2 ONNX, 384 dims, in-database)');
    RETURN o.to_clob;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20404, 'Evento não encontrado: ' || p_evento);
  END;

  PROCEDURE api_interpretar(p_evento VARCHAR2, p_body CLOB) IS
    j     JSON_OBJECT_T;
    l_res CLOB;
    l_off PLS_INTEGER := 1;
    o     JSON_OBJECT_T;
  BEGIN
    BEGIN
      j := JSON_OBJECT_T.parse(NVL(p_body, '{}'));
    EXCEPTION WHEN OTHERS THEN raise_application_error(-20400, 'Corpo JSON inválido');
    END;
    l_res := interpretar_json(p_evento, j.get_string('texto'));
    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
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
END ac_assistente;
/

BEGIN
  ORDS.define_template('rotas.v1', 'eventos/:evento/assistente');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/assistente', 'POST', ORDS.source_type_plsql,
    'BEGIN ac_assistente.api_interpretar(:evento, :body_text); END;');
  COMMIT;
END;
/

SELECT object_name, object_type, status FROM user_objects WHERE object_name = 'AC_ASSISTENTE';
