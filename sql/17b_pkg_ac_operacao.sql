-- =====================================================================
-- 17b — PACKAGE AC_OPERACAO: painel do organizador, evacuação, decisões humanas,
--        kit de validação com usuários e treino da IA com curadoria humana
-- =====================================================================
CREATE OR REPLACE PACKAGE ac_operacao AUTHID DEFINER AS
  FUNCTION painel_json(p_evento VARCHAR2) RETURN CLOB;
  FUNCTION rotulos_json RETURN CLOB;
  FUNCTION tarefas_json(p_evento VARCHAR2) RETURN CLOB;

  PROCEDURE api_painel      (p_evento VARCHAR2);
  PROCEDURE api_rotulos;
  PROCEDURE api_tarefas     (p_evento VARCHAR2);
  PROCEDURE api_decisao     (p_evento VARCHAR2, p_body CLOB);
  PROCEDURE api_evacuacao   (p_evento VARCHAR2, p_body CLOB);
  PROCEDURE api_participante(p_evento VARCHAR2, p_body CLOB);
  PROCEDURE api_execucao    (p_evento VARCHAR2, p_body CLOB);
  PROCEDURE api_ensinar     (p_evento VARCHAR2, p_body CLOB);
END ac_operacao;
/

CREATE OR REPLACE PACKAGE BODY ac_operacao AS

  FUNCTION evento_id(p VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    SELECT id INTO l FROM ac_evento WHERE codigo = UPPER(TRIM(p));
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20404, 'Evento não encontrado: ' || p);
  END;

  PROCEDURE exigir_pin(p_ev NUMBER, p_pin VARCHAR2) IS
    l ac_evento.pin_organizador%TYPE;
  BEGIN
    SELECT pin_organizador INTO l FROM ac_evento WHERE id = p_ev;
    IF l IS NOT NULL AND NVL(p_pin, '-') <> l THEN
      raise_application_error(-20403, 'PIN do organizador inválido');
    END IF;
  END;

  PROCEDURE responder(p_json CLOB, p_status PLS_INTEGER DEFAULT 200) IS
    l_off PLS_INTEGER := 1;
  BEGIN
    OWA_UTIL.status_line(p_status, NULL, FALSE);
    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    HTP.p('Cache-Control: no-store');
    OWA_UTIL.http_header_close;
    WHILE l_off <= NVL(DBMS_LOB.getlength(p_json), 0) LOOP
      HTP.prn(DBMS_LOB.substr(p_json, 8000, l_off));
      l_off := l_off + 8000;
    END LOOP;
  END;

  PROCEDURE erro(p_code NUMBER, p_msg VARCHAR2) IS
    o JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    ROLLBACK;
    o.put('status', 'ERRO');
    o.put('mensagem', REGEXP_REPLACE(p_msg, '^ORA-\d+: ', ''));
    responder(o.to_clob, CASE p_code WHEN -20400 THEN 400 WHEN -20403 THEN 403 WHEN -20404 THEN 404 ELSE 500 END);
  END;

  FUNCTION corpo(p CLOB) RETURN JSON_OBJECT_T IS
  BEGIN
    RETURN JSON_OBJECT_T.parse(NVL(p, '{}'));
  EXCEPTION WHEN OTHERS THEN
    raise_application_error(-20400, 'Corpo JSON inválido');
  END;

  -- ------------------------------------------------------------------ painel
  FUNCTION painel_json(p_evento VARCHAR2) RETURN CLOB IS
    l_ev NUMBER := evento_id(p_evento);
    l CLOB;
  BEGIN
    SELECT JSON_OBJECT(
      'gerado_em' VALUE TO_CHAR(SYSTIMESTAMP AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI:SS'),
      'kpis' VALUE JSON_OBJECT(
        'reportes_30min'     VALUE (SELECT COUNT(*) FROM ac_reporte WHERE evento_id = l_ev AND criado_em > SYSTIMESTAMP - INTERVAL '30' MINUTE),
        'corredores_criticos' VALUE (SELECT COUNT(DISTINCT REGEXP_REPLACE(via, ' \(.*\)$')) FROM ac_trecho WHERE evento_id = l_ev AND (lotacao >= 4 OR ruido >= 5)),
        'pontos_bloqueados'  VALUE (SELECT COUNT(*) FROM ac_ponto WHERE evento_id = l_ev AND bloqueado = 'S'),
        'conversas'          VALUE (SELECT COUNT(*) FROM ac_conversa_log WHERE evento_id = l_ev),
        'taxa_entendimento'  VALUE (SELECT ROUND(100 * AVG(CASE WHEN entendeu = 'S' THEN 1 ELSE 0 END)) FROM ac_conversa_log WHERE evento_id = l_ev),
        'decisoes'           VALUE (SELECT COUNT(*) FROM ac_decisao WHERE evento_id = l_ev),
        'pct_seguiu'         VALUE (SELECT ROUND(100 * AVG(CASE WHEN decisao = 'SEGUIU' THEN 1 ELSE 0 END)) FROM ac_decisao WHERE evento_id = l_ev),
        'participantes_teste' VALUE (SELECT COUNT(*) FROM ac_val_participante WHERE evento_id = l_ev)),
      'evacuacao' VALUE (SELECT JSON_OBJECT('ativa' VALUE CASE WHEN COUNT(*) > 0 THEN 'S' ELSE 'N' END,
                                            'mensagem' VALUE MAX(mensagem),
                                            'desde' VALUE TO_CHAR(MAX(iniciada_em) AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI'))
                           FROM ac_evacuacao WHERE evento_id = l_ev AND encerrada_em IS NULL),
      'corredores' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('via' VALUE via, 'lotacao' VALUE lot, 'ruido' VALUE rui, 'bloqueado' VALUE bloq)
                                ORDER BY lot DESC, rui DESC RETURNING CLOB)
                         FROM (SELECT REGEXP_REPLACE(t.via, ' \(.*\)$') via, MAX(t.lotacao) lot, MAX(t.ruido) rui,
                                      MAX(CASE WHEN t.bloqueado = 'S' OR pa.bloqueado = 'S' OR pb.bloqueado = 'S' THEN 'S' ELSE 'N' END) bloq
                                 FROM ac_trecho t JOIN ac_ponto pa ON pa.id = t.ponto_a JOIN ac_ponto pb ON pb.id = t.ponto_b
                                WHERE t.evento_id = l_ev GROUP BY REGEXP_REPLACE(t.via, ' \(.*\)$'))), '[]') FORMAT JSON,
      'reportes' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('tipo' VALUE tipo, 'lugar' VALUE nome, 'por' VALUE reportado_por,
                              'em' VALUE TO_CHAR(criado_em AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI')) ORDER BY criado_em DESC RETURNING CLOB)
                       FROM (SELECT r.tipo, p.nome, r.reportado_por, r.criado_em FROM ac_reporte r JOIN ac_ponto p ON p.id = r.ponto_id
                              WHERE r.evento_id = l_ev ORDER BY r.criado_em DESC FETCH FIRST 12 ROWS ONLY)), '[]') FORMAT JSON,
      'intencoes' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('rotulo' VALUE rotulo, 'total' VALUE n) ORDER BY n DESC RETURNING CLOB)
                        FROM (SELECT NVL(CASE WHEN intencao = 'FAQ' THEN 'FAQ:' || faq_chave ELSE intencao END, 'NAO_ENTENDEU') rotulo, COUNT(*) n
                                FROM ac_conversa_log WHERE evento_id = l_ev
                               GROUP BY NVL(CASE WHEN intencao = 'FAQ' THEN 'FAQ:' || faq_chave ELSE intencao END, 'NAO_ENTENDEU')
                               ORDER BY n DESC FETCH FIRST 10 ROWS ONLY)), '[]') FORMAT JSON,
      'para_revisar' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE id, 'texto' VALUE texto,
                                  'obtido' VALUE NVL(CASE WHEN intencao = 'FAQ' THEN 'FAQ:' || faq_chave ELSE intencao END, 'NAO_ENTENDEU'),
                                  'confianca' VALUE confianca,
                                  'em' VALUE TO_CHAR(criado_em AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24:MI')) ORDER BY criado_em DESC RETURNING CLOB)
                           FROM (SELECT * FROM ac_conversa_log WHERE evento_id = l_ev AND revisado = 'N'
                                    AND (entendeu = 'N' OR metodo = 'PALAVRA_CHAVE' OR confianca < 0.65)
                                  ORDER BY criado_em DESC FETCH FIRST 25 ROWS ONLY)), '[]') FORMAT JSON,
      'decisoes_por_perfil' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('perfil' VALUE perfil, 'seguiu' VALUE seguiu, 'outra' VALUE outra) RETURNING CLOB)
                         FROM (SELECT NVL(perfil, '-') perfil, COUNT(CASE WHEN decisao = 'SEGUIU' THEN 1 END) seguiu,
                                      COUNT(CASE WHEN decisao <> 'SEGUIU' THEN 1 END) outra
                                 FROM ac_decisao WHERE evento_id = l_ev GROUP BY NVL(perfil, '-'))), '[]') FORMAT JSON,
      'validacao' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('tarefa' VALUE tarefa, 'condicao' VALUE condicao, 'n' VALUE n,
                               'segundos_medio' VALUE seg, 'confianca_media' VALUE conf, 'facilidade_media' VALUE fac, 'pct_concluiu' VALUE pct)
                               ORDER BY tarefa, condicao DESC RETURNING CLOB)
                        FROM (SELECT e.tarefa, e.condicao, COUNT(*) n, ROUND(AVG(e.segundos)) seg, ROUND(AVG(e.confianca), 1) conf,
                                     ROUND(AVG(e.facilidade), 1) fac, ROUND(100 * AVG(CASE WHEN e.concluiu = 'S' THEN 1 ELSE 0 END)) pct
                                FROM ac_val_execucao e JOIN ac_val_participante p ON p.id = e.participante_id
                               WHERE p.evento_id = l_ev GROUP BY e.tarefa, e.condicao)), '[]') FORMAT JSON,
      'frases_coletadas' VALUE (SELECT COUNT(*) FROM ac_val_execucao e JOIN ac_val_participante p ON p.id = e.participante_id
                                 WHERE p.evento_id = l_ev AND e.frase IS NOT NULL)
      RETURNING CLOB)
      INTO l FROM dual;
    RETURN l;
  END;

  FUNCTION rotulos_json RETURN CLOB IS
    l CLOB;
  BEGIN
    SELECT JSON_OBJECT('rotulos' VALUE JSON_ARRAYAGG(JSON_OBJECT('rotulo' VALUE rotulo, 'descricao' VALUE descricao) ORDER BY grupo, rotulo RETURNING CLOB)
                       RETURNING CLOB)
      INTO l FROM (
        SELECT codigo rotulo, descricao, 1 grupo FROM ac_intencao WHERE categoria IN ('PERGUNTA', 'NECESSIDADE')
        UNION ALL
        SELECT DISTINCT 'FAQ:' || chave, SUBSTR(MAX(resposta) OVER (PARTITION BY chave), 1, 80), 2 FROM ac_faq);
    RETURN l;
  END;

  FUNCTION tarefas_json(p_evento VARCHAR2) RETURN CLOB IS
    l CLOB;
  BEGIN
    SELECT JSON_OBJECT('tarefas' VALUE NVL(JSON_ARRAYAGG(JSON_OBJECT('codigo' VALUE codigo, 'enunciado' VALUE enunciado, 'perfil' VALUE perfil,
             'origem' VALUE origem, 'destino' VALUE destino, 'modo' VALUE modo, 'intencao' VALUE intencao) ORDER BY codigo RETURNING CLOB), '[]') FORMAT JSON
             RETURNING CLOB)
      INTO l FROM ac_val_tarefa WHERE evento_codigo = UPPER(TRIM(p_evento));
    RETURN l;
  END;

  -- ------------------------------------------------------------------ API
  PROCEDURE api_painel(p_evento VARCHAR2) IS
  BEGIN
    responder(painel_json(p_evento));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_rotulos IS
  BEGIN
    responder(rotulos_json);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_tarefas(p_evento VARCHAR2) IS
  BEGIN
    responder(tarefas_json(p_evento));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_decisao(p_evento VARCHAR2, p_body CLOB) IS
    l_ev NUMBER := evento_id(p_evento);
    j JSON_OBJECT_T := corpo(p_body);
    l_dec VARCHAR2(20) := UPPER(j.get_string('decisao'));
    l_perfil VARCHAR2(30) := SUBSTR(j.get_string('perfil'), 1, 30);
    l_ori VARCHAR2(40) := SUBSTR(j.get_string('origem'), 1, 40);
    l_dest VARCHAR2(40) := SUBSTR(j.get_string('destino'), 1, 40);
    l_modo VARCHAR2(10) := SUBSTR(j.get_string('modo'), 1, 10);
    l_cam VARCHAR2(1000) := SUBSTR(j.get_string('caminho'), 1, 1000);
  BEGIN
    IF l_dec NOT IN ('SEGUIU', 'OUTRA_OPCAO', 'TROCOU_PERFIL') OR l_dec IS NULL THEN
      raise_application_error(-20400, 'decisao deve ser SEGUIU, OUTRA_OPCAO ou TROCOU_PERFIL');
    END IF;
    INSERT INTO ac_decisao (evento_id, perfil, origem, destino, modo, caminho, decisao)
    VALUES (l_ev, l_perfil, l_ori, l_dest, l_modo, l_cam, l_dec);
    COMMIT;
    responder('{"status":"OK"}', 201);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_evacuacao(p_evento VARCHAR2, p_body CLOB) IS
    l_ev NUMBER := evento_id(p_evento);
    j JSON_OBJECT_T := corpo(p_body);
    l_ativa BOOLEAN;
    l_msg VARCHAR2(400) := SUBSTR(j.get_string('mensagem'), 1, 400);
  BEGIN
    exigir_pin(l_ev, j.get_string('pin'));
    IF NOT j.has('ativa') OR NOT j.get('ativa').is_boolean THEN
      raise_application_error(-20400, 'Informe "ativa": true ou false');
    END IF;
    l_ativa := j.get_boolean('ativa');
    UPDATE ac_evacuacao SET encerrada_em = SYSTIMESTAMP WHERE evento_id = l_ev AND encerrada_em IS NULL;
    IF l_ativa THEN
      INSERT INTO ac_evacuacao (evento_id, mensagem) VALUES (l_ev, l_msg);
    END IF;
    COMMIT;
    responder(CASE WHEN l_ativa THEN '{"status":"OK","mensagem":"Evacuação acionada. Todos os aparelhos recebem a saída segura em até 6 segundos."}'
                   ELSE '{"status":"OK","mensagem":"Evacuação encerrada."}' END);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_participante(p_evento VARCHAR2, p_body CLOB) IS
    l_ev NUMBER := evento_id(p_evento);
    j JSON_OBJECT_T := corpo(p_body);
    l_id NUMBER;
    l_apelido VARCHAR2(60) := SUBSTR(TRIM(j.get_string('apelido')), 1, 60);
    l_perfil VARCHAR2(30) := SUBSTR(j.get_string('perfil'), 1, 30);
    l_faixa VARCHAR2(20) := SUBSTR(j.get_string('faixa_etaria'), 1, 20);
  BEGIN
    IF NOT j.has('consentimento') OR NOT j.get('consentimento').is_boolean OR NOT j.get_boolean('consentimento') THEN
      raise_application_error(-20400, 'O participante precisa dar consentimento (LGPD) antes do teste');
    END IF;
    IF l_apelido IS NULL THEN
      raise_application_error(-20400, 'Informe um apelido (não use o nome real)');
    END IF;
    INSERT INTO ac_val_participante (evento_id, apelido, perfil, faixa_etaria, consentimento)
    VALUES (l_ev, l_apelido, l_perfil, l_faixa, 'S')
    RETURNING id INTO l_id;
    COMMIT;
    responder('{"status":"OK","id":' || l_id || '}', 201);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_execucao(p_evento VARCHAR2, p_body CLOB) IS
    l_ev NUMBER := evento_id(p_evento);
    j JSON_OBJECT_T := corpo(p_body);
    l_pid NUMBER := j.get_number('participante_id');
    l_ok NUMBER;
    l_tarefa VARCHAR2(10) := SUBSTR(j.get_string('tarefa'), 1, 10);
    l_cond VARCHAR2(10) := UPPER(j.get_string('condicao'));
    l_seg NUMBER := j.get_number('segundos');
    l_conc VARCHAR2(1) := CASE WHEN j.has('concluiu') AND j.get('concluiu').is_boolean AND j.get_boolean('concluiu') THEN 'S' ELSE 'N' END;
    l_conf NUMBER := j.get_number('confianca');
    l_fac NUMBER := j.get_number('facilidade');
    l_com VARCHAR2(1000) := SUBSTR(j.get_string('comentario'), 1, 1000);
    l_frase VARCHAR2(400) := SUBSTR(j.get_string('frase'), 1, 400);
  BEGIN
    SELECT COUNT(*) INTO l_ok FROM ac_val_participante WHERE id = l_pid AND evento_id = l_ev;
    IF l_ok = 0 THEN raise_application_error(-20404, 'Participante não encontrado'); END IF;
    INSERT INTO ac_val_execucao (participante_id, tarefa, condicao, segundos, concluiu, confianca, facilidade, comentario, frase)
    VALUES (l_pid, l_tarefa, l_cond, l_seg, l_conc, l_conf, l_fac, l_com, l_frase);
    COMMIT;
    responder('{"status":"OK"}', 201);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  -- curadoria humana: o organizador ensina a resposta certa; a frase vira exemplo vetorizado
  PROCEDURE api_ensinar(p_evento VARCHAR2, p_body CLOB) IS
    l_ev NUMBER := evento_id(p_evento);
    j JSON_OBJECT_T := corpo(p_body);
    l_rot VARCHAR2(80) := UPPER(TRIM(j.get_string('rotulo')));
    l_txt VARCHAR2(400) := SUBSTR(TRIM(j.get_string('texto')), 1, 400);
    l_log NUMBER := CASE WHEN j.has('log_id') THEN j.get_number('log_id') END;
    l_faq NUMBER;
    l_n NUMBER;
  BEGIN
    exigir_pin(l_ev, j.get_string('pin'));
    IF l_log IS NOT NULL AND l_txt IS NULL THEN
      SELECT SUBSTR(texto, 1, 400) INTO l_txt FROM ac_conversa_log WHERE id = l_log AND evento_id = l_ev;
    END IF;
    IF l_txt IS NULL OR l_rot IS NULL THEN raise_application_error(-20400, 'Informe texto (ou log_id) e rotulo'); END IF;

    IF l_rot = 'IGNORAR' THEN
      NULL;
    ELSIF l_rot LIKE 'FAQ:%' THEN
      SELECT MAX(id) KEEP (DENSE_RANK FIRST ORDER BY evento_codigo NULLS LAST) INTO l_faq
        FROM ac_faq WHERE chave = SUBSTR(l_rot, 5) AND (evento_codigo IS NULL OR evento_codigo = UPPER(TRIM(p_evento)));
      IF l_faq IS NULL THEN raise_application_error(-20404, 'FAQ não encontrado: ' || l_rot); END IF;
      INSERT INTO ac_faq_pergunta (faq_id, pergunta, origem, embedding)
      SELECT l_faq, l_txt, 'ENSINADA', VECTOR_EMBEDDING(doc_model USING l_txt AS data) FROM dual;
    ELSE
      SELECT COUNT(*) INTO l_n FROM ac_intencao WHERE codigo = l_rot;
      IF l_n = 0 THEN raise_application_error(-20404, 'Intenção não encontrada: ' || l_rot); END IF;
      INSERT INTO ac_intencao_frase (intencao, frase, embedding)
      SELECT l_rot, l_txt, VECTOR_EMBEDDING(doc_model USING l_txt AS data) FROM dual;
    END IF;

    IF l_log IS NOT NULL THEN
      UPDATE ac_conversa_log SET revisado = 'S', rotulo = l_rot WHERE id = l_log AND evento_id = l_ev;
    END IF;
    COMMIT;
    responder('{"status":"OK","mensagem":"' || CASE WHEN l_rot = 'IGNORAR' THEN 'Marcado como revisado.'
              ELSE 'Aprendido: a partir de agora frases parecidas vão para ' || l_rot || '.' END || '"}', 201);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;
END ac_operacao;
/

BEGIN
  ORDS.define_template('rotas.v1', 'eventos/:evento/painel');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/painel', 'GET', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_painel(:evento); END;');
  ORDS.define_template('rotas.v1', 'rotulos');
  ORDS.define_handler('rotas.v1', 'rotulos', 'GET', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_rotulos; END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/validacao/tarefas');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/validacao/tarefas', 'GET', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_tarefas(:evento); END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/decisoes');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/decisoes', 'POST', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_decisao(:evento, :body_text); END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/evacuacao');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/evacuacao', 'POST', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_evacuacao(:evento, :body_text); END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/validacao/participantes');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/validacao/participantes', 'POST', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_participante(:evento, :body_text); END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/validacao/execucoes');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/validacao/execucoes', 'POST', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_execucao(:evento, :body_text); END;');
  ORDS.define_template('rotas.v1', 'eventos/:evento/treino/ensinar');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/treino/ensinar', 'POST', ORDS.source_type_plsql, 'BEGIN ac_operacao.api_ensinar(:evento, :body_text); END;');
  COMMIT;
END;
/

SELECT object_name, object_type, status FROM user_objects WHERE object_name = 'AC_OPERACAO';
