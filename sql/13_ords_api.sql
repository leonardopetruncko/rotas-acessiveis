-- =====================================================================
-- 13 — API REST (ORDS) que o React consome
-- Base: https://<host>/ords/acesso_app/api/v1/
--   GET  eventos                                           lista de eventos
--   GET  eventos/:evento                                   mapa (evento, perfis, áreas, pontos, trechos, reportes)
--   GET  eventos/:evento/rota?perfil=&origem=&destino=     rota sugerida p/ um perfil
--   GET  eventos/:evento/comparar?origem=&destino=         mesma viagem, todos os perfis
--   GET  eventos/:evento/saida?perfil=&origem=             saída mais segura + alternativas
--   POST eventos/:evento/reportes   {"ponto","tipo","usuario","detalhe"}   CHEIO|BARULHO|BLOQUEIO|LIBERADO
--   POST eventos/:evento/reset                             restaura o cenário da demo
-- Público (sem auth) — dados SINTÉTICOS de demo. Recriar o módulo é idempotente.
-- =====================================================================
BEGIN
  ORDS.define_module(
    p_module_name    => 'rotas.v1',
    p_base_path      => '/api/v1/',
    p_items_per_page => 0,
    p_status         => 'PUBLISHED',
    p_comments       => 'Rotas Acessíveis — Tech4Change 2026');

  ORDS.define_template('rotas.v1', 'eventos');
  ORDS.define_handler('rotas.v1', 'eventos', 'GET', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_eventos; END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento');
  ORDS.define_handler('rotas.v1', 'eventos/:evento', 'GET', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_mapa(:evento); END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento/rota');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/rota', 'GET', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_rota(:evento, :perfil, :origem, :destino); END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento/comparar');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/comparar', 'GET', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_comparar(:evento, :origem, :destino); END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento/saida');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/saida', 'GET', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_saida(:evento, :perfil, :origem); END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento/reportes');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/reportes', 'POST', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_reportar(:evento, :body_text); END;');

  ORDS.define_template('rotas.v1', 'eventos/:evento/reset');
  ORDS.define_handler('rotas.v1', 'eventos/:evento/reset', 'POST', ORDS.source_type_plsql,
    'BEGIN ac_rotas.api_reset(:evento); END;');

  COMMIT;
END;
/

SELECT m.name, t.uri_template, h.method
  FROM user_ords_modules m
  JOIN user_ords_templates t ON t.module_id = m.id
  JOIN user_ords_handlers h ON h.template_id = t.id
 WHERE m.name = 'rotas.v1'
 ORDER BY t.uri_template, h.method;
