-- =====================================================================
-- 12 — MOTOR DE ROTAS v2 (package AC_ROTAS)
--  * Dijkstra ponderado por perfil, sem gravar nada (dá pra chamar em SELECT)
--  * custo do trecho = distancia * (1 + (ruido-1)*peso_ruido/10 + (lotacao-1)*peso_lotacao/10)
--    (multiplicativo: quebrar um corredor em vários trechos não muda o custo)
--  * escada/degrau bloqueado se o perfil evita escada; ponto/trecho bloqueado = intransponível
--  * rota_saida: calcula TODAS as saídas e ranqueia -> sugere uma, mostra as outras.
--    A IA informa; a pessoa decide.
--  * api_*: handlers do ORDS (JSON + status HTTP)
-- =====================================================================
CREATE OR REPLACE PACKAGE ac_rotas AUTHID DEFINER AS
  FUNCTION eventos_json RETURN CLOB;
  FUNCTION mapa_json      (p_evento VARCHAR2) RETURN CLOB;
  FUNCTION rota_json      (p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) RETURN CLOB;
  FUNCTION comparar_json  (p_evento VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) RETURN CLOB;
  FUNCTION rota_saida_json(p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2) RETURN CLOB;
  FUNCTION reportar_json  (p_evento VARCHAR2, p_ponto VARCHAR2, p_tipo VARCHAR2, p_usuario VARCHAR2 DEFAULT NULL, p_detalhe VARCHAR2 DEFAULT NULL) RETURN CLOB;
  PROCEDURE reset_demo    (p_evento VARCHAR2);

  -- ORDS
  PROCEDURE api_eventos;
  PROCEDURE api_mapa    (p_evento VARCHAR2);
  PROCEDURE api_rota    (p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2);
  PROCEDURE api_comparar(p_evento VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2);
  PROCEDURE api_saida   (p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2);
  PROCEDURE api_reportar(p_evento VARCHAR2, p_body CLOB);
  PROCEDURE api_reset   (p_evento VARCHAR2);
END ac_rotas;
/

CREATE OR REPLACE PACKAGE BODY ac_rotas AS
  c_inf CONSTANT NUMBER := 1e12;

  TYPE t_num   IS TABLE OF NUMBER INDEX BY PLS_INTEGER;
  TYPE r_aresta IS RECORD (trecho_id NUMBER, viz NUMBER);
  TYPE t_lista IS TABLE OF r_aresta INDEX BY PLS_INTEGER;
  TYPE t_adj   IS TABLE OF t_lista INDEX BY PLS_INTEGER;
  TYPE r_trecho IS RECORD (distancia NUMBER, via VARCHAR2(120), escada VARCHAR2(1), ruido NUMBER, lotacao NUMBER);
  TYPE t_trechos IS TABLE OF r_trecho INDEX BY PLS_INTEGER;
  TYPE r_perfil IS RECORD (codigo VARCHAR2(30), nome VARCHAR2(80), evita VARCHAR2(1), pr NUMBER, pl NUMBER, vel NUMBER);
  TYPE r_busca IS RECORD (dist t_num, prev t_num, prevt t_num, tr t_trechos, origem NUMBER);
  TYPE r_resumo IS RECORD (ok BOOLEAN := FALSE, custo NUMBER, metros NUMBER := 0, max_r NUMBER := 0, max_l NUMBER := 0,
                           escada BOOLEAN := FALSE, pts t_num, trs t_num);

  -- ------------------------------------------------------------------ lookups
  FUNCTION evento_id(p_codigo VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    IF p_codigo IS NULL THEN raise_application_error(-20400, 'Parâmetro obrigatório: evento'); END IF;
    SELECT id INTO l FROM ac_evento WHERE codigo = UPPER(TRIM(p_codigo));
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20404, 'Evento não encontrado: ' || p_codigo);
  END;

  FUNCTION ponto_id(p_evento NUMBER, p_codigo VARCHAR2, p_param VARCHAR2) RETURN NUMBER IS
    l NUMBER;
  BEGIN
    IF p_codigo IS NULL THEN raise_application_error(-20400, 'Parâmetro obrigatório: ' || p_param); END IF;
    SELECT id INTO l FROM ac_ponto WHERE evento_id = p_evento AND codigo = UPPER(TRIM(p_codigo));
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20404, 'Ponto não encontrado (' || p_param || '): ' || p_codigo);
  END;

  FUNCTION perfil(p_codigo VARCHAR2) RETURN r_perfil IS
    l r_perfil;
  BEGIN
    IF p_codigo IS NULL THEN raise_application_error(-20400, 'Parâmetro obrigatório: perfil'); END IF;
    SELECT codigo, nome, evita_escada, peso_ruido, peso_lotacao, NVL(velocidade_ms, 1.2)
      INTO l.codigo, l.nome, l.evita, l.pr, l.pl, l.vel
      FROM ac_perfil WHERE codigo = UPPER(TRIM(p_codigo));
    RETURN l;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    raise_application_error(-20404, 'Perfil não encontrado: ' || p_codigo);
  END;

  FUNCTION ponto_obj(p_id NUMBER) RETURN JSON_OBJECT_T IS
    o JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    FOR p IN (SELECT codigo, nome, tipo, x, y FROM ac_ponto WHERE id = p_id) LOOP
      o.put('codigo', p.codigo); o.put('nome', p.nome); o.put('tipo', p.tipo);
      o.put('x', p.x); o.put('y', p.y);
    END LOOP;
    RETURN o;
  END;

  FUNCTION ponto_nome(p_id NUMBER) RETURN VARCHAR2 IS
    l ac_ponto.nome%TYPE;
  BEGIN
    SELECT nome INTO l FROM ac_ponto WHERE id = p_id;
    RETURN l;
  END;

  -- ------------------------------------------------------------------ Dijkstra
  FUNCTION buscar(p_evento NUMBER, p_perfil r_perfil, p_origem NUMBER) RETURN r_busca IS
    b      r_busca;
    l_adj  t_adj;
    l_vazia t_lista;
    l_bloq t_num;
    l_vis  t_num;
    l_u    NUMBER;
    l_best NUMBER;
    l_k    NUMBER;
    l_v    NUMBER;
    l_t    NUMBER;
    l_c    NUMBER;

    PROCEDURE ligar(a NUMBER, v NUMBER, t NUMBER) IS
      e r_aresta;
    BEGIN
      IF NOT l_adj.EXISTS(a) THEN l_adj(a) := l_vazia; END IF;
      e.trecho_id := t; e.viz := v;
      l_adj(a)(l_adj(a).COUNT + 1) := e;
    END;
  BEGIN
    b.origem := p_origem;
    FOR p IN (SELECT id, bloqueado FROM ac_ponto WHERE evento_id = p_evento ORDER BY id) LOOP
      b.dist(p.id) := c_inf;
      l_vis(p.id)  := 0;
      l_bloq(p.id) := CASE p.bloqueado WHEN 'S' THEN 1 ELSE 0 END;
    END LOOP;

    FOR t IN (SELECT id, ponto_a, ponto_b, distancia, via, tem_escada, ruido, lotacao
                FROM ac_trecho WHERE evento_id = p_evento AND bloqueado = 'N' ORDER BY id) LOOP
      b.tr(t.id).distancia := t.distancia;
      b.tr(t.id).via       := t.via;
      b.tr(t.id).escada    := t.tem_escada;
      b.tr(t.id).ruido     := t.ruido;
      b.tr(t.id).lotacao   := t.lotacao;
      IF NOT (p_perfil.evita = 'S' AND t.tem_escada = 'S') THEN
        ligar(t.ponto_a, t.ponto_b, t.id);
        ligar(t.ponto_b, t.ponto_a, t.id);
      END IF;
    END LOOP;

    b.dist(p_origem) := 0;
    LOOP
      l_u := NULL; l_best := c_inf;
      l_k := b.dist.FIRST;
      WHILE l_k IS NOT NULL LOOP
        IF l_vis(l_k) = 0 AND b.dist(l_k) < l_best THEN l_best := b.dist(l_k); l_u := l_k; END IF;
        l_k := b.dist.NEXT(l_k);
      END LOOP;
      EXIT WHEN l_u IS NULL;
      l_vis(l_u) := 1;

      IF l_adj.EXISTS(l_u) THEN
        FOR i IN 1 .. l_adj(l_u).COUNT LOOP
          l_v := l_adj(l_u)(i).viz;
          l_t := l_adj(l_u)(i).trecho_id;
          IF l_bloq(l_v) = 0 THEN
            l_c := b.dist(l_u) + b.tr(l_t).distancia
                   * (1 + (b.tr(l_t).ruido - 1) * p_perfil.pr / 10 + (b.tr(l_t).lotacao - 1) * p_perfil.pl / 10);
            IF l_c < b.dist(l_v) THEN
              b.dist(l_v) := l_c; b.prev(l_v) := l_u; b.prevt(l_v) := l_t;
            END IF;
          END IF;
        END LOOP;
      END IF;
    END LOOP;
    RETURN b;
  END;

  FUNCTION resumir(b r_busca, p_destino NUMBER) RETURN r_resumo IS
    r     r_resumo;
    l_inv t_num;
    l_trv t_num;
    l_cur NUMBER := p_destino;
  BEGIN
    IF NOT b.dist.EXISTS(p_destino) OR b.dist(p_destino) >= c_inf THEN RETURN r; END IF;
    r.ok := TRUE;
    r.custo := b.dist(p_destino);
    WHILE l_cur <> b.origem LOOP
      l_inv(l_inv.COUNT + 1) := l_cur;
      l_trv(l_trv.COUNT + 1) := b.prevt(l_cur);
      l_cur := b.prev(l_cur);
    END LOOP;
    l_inv(l_inv.COUNT + 1) := b.origem;
    FOR i IN REVERSE 1 .. l_inv.COUNT LOOP r.pts(r.pts.COUNT + 1) := l_inv(i); END LOOP;
    FOR i IN REVERSE 1 .. l_trv.COUNT LOOP
      r.trs(r.trs.COUNT + 1) := l_trv(i);
      r.metros := r.metros + b.tr(l_trv(i)).distancia;
      r.max_r  := GREATEST(r.max_r, b.tr(l_trv(i)).ruido);
      r.max_l  := GREATEST(r.max_l, b.tr(l_trv(i)).lotacao);
      IF b.tr(l_trv(i)).escada = 'S' THEN r.escada := TRUE; END IF;
    END LOOP;
    RETURN r;
  END;

  FUNCTION minutos(p_metros NUMBER, p_vel NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN GREATEST(1, CEIL(p_metros / p_vel / 60));
  END;

  -- ------------------------------------------------------------------ JSON da rota
  FUNCTION rota_obj(p_perfil r_perfil, b r_busca, r r_resumo, p_destino NUMBER, p_ref r_resumo) RETURN JSON_OBJECT_T IS
    o      JSON_OBJECT_T := JSON_OBJECT_T();
    l_pts  JSON_ARRAY_T := JSON_ARRAY_T();
    l_trs  JSON_ARRAY_T := JSON_ARRAY_T();
    l_ins  JSON_ARRAY_T := JSON_ARRAY_T();
    l_ale  JSON_ARRAY_T := JSON_ARRAY_T();
    l_evi  JSON_ARRAY_T := JSON_ARRAY_T();
    l_t    JSON_OBJECT_T;
    l_via  VARCHAR2(120);
    l_m    NUMBER := 0;
    l_msg  VARCHAR2(4000);
    l_vistos VARCHAR2(4000) := '|';
    l_evitas VARCHAR2(1000);
  BEGIN
    l_t := JSON_OBJECT_T();
    l_t.put('codigo', p_perfil.codigo);
    l_t.put('nome', p_perfil.nome);
    o.put('perfil', l_t);
    o.put('origem', ponto_obj(b.origem));
    o.put('destino', ponto_obj(p_destino));

    IF NOT r.ok THEN
      o.put('status', 'SEM_ROTA');
      o.put('mensagem', 'Não encontrei um caminho sem barreiras para o perfil ' || p_perfil.nome
                     || ' até ' || ponto_nome(p_destino) || '. Procure a equipe de apoio mais próxima.');
      RETURN o;
    END IF;

    o.put('status', 'OK');
    o.put('distancia_m', ROUND(r.metros));
    o.put('tempo_min', minutos(r.metros, p_perfil.vel));
    o.put('custo', ROUND(r.custo, 1));
    o.put('tem_escada', r.escada);
    o.put('ruido_max', r.max_r);
    o.put('lotacao_max', r.max_l);

    FOR i IN 1 .. r.pts.COUNT LOOP l_pts.append(ponto_obj(r.pts(i))); END LOOP;
    o.put('pontos', l_pts);

    FOR i IN 1 .. r.trs.COUNT LOOP
      l_t := JSON_OBJECT_T();
      l_t.put('id', r.trs(i));
      l_t.put('via', b.tr(r.trs(i)).via);
      l_t.put('distancia_m', b.tr(r.trs(i)).distancia);
      l_t.put('escada', b.tr(r.trs(i)).escada = 'S');
      l_t.put('ruido', b.tr(r.trs(i)).ruido);
      l_t.put('lotacao', b.tr(r.trs(i)).lotacao);
      l_trs.append(l_t);

      -- instruções: agrupa trechos consecutivos do mesmo corredor
      IF l_via IS NOT NULL AND b.tr(r.trs(i)).via <> l_via THEN
        l_ins.append('Siga por ' || l_via || ' (~' || ROUND(l_m) || ' m) até ' || ponto_nome(r.pts(i)) || '.');
        l_m := 0;
      END IF;
      l_via := b.tr(r.trs(i)).via;
      l_m   := l_m + b.tr(r.trs(i)).distancia;

      IF b.tr(r.trs(i)).ruido >= 4 AND INSTR(l_vistos, '|R:' || l_via || '|') = 0 THEN
        l_ale.append('Barulho alto em ' || l_via || ' (nível ' || b.tr(r.trs(i)).ruido || '/5).');
        l_vistos := l_vistos || 'R:' || l_via || '|';
      END IF;
      IF b.tr(r.trs(i)).lotacao >= 4 AND INSTR(l_vistos, '|L:' || l_via || '|') = 0 THEN
        l_ale.append('Muita gente em ' || l_via || ' (lotação ' || b.tr(r.trs(i)).lotacao || '/5).');
        l_vistos := l_vistos || 'L:' || l_via || '|';
      END IF;
    END LOOP;
    IF l_via IS NOT NULL THEN
      l_ins.append('Siga por ' || l_via || ' (~' || ROUND(l_m) || ' m) até ' || ponto_nome(p_destino) || '.');
    END IF;
    o.put('instrucoes', l_ins);
    o.put('trechos', l_trs);
    o.put('alertas', l_ale);

    -- explicação comparando com a rota mais direta (PADRAO)
    IF p_ref.ok AND p_perfil.codigo <> 'PADRAO' THEN
      IF p_ref.escada AND NOT r.escada THEN l_evi.append('escadas e degraus'); END IF;
      IF p_ref.max_r > r.max_r THEN l_evi.append('barulho (nível ' || p_ref.max_r || ' → ' || r.max_r || ')'); END IF;
      IF p_ref.max_l > r.max_l THEN l_evi.append('aglomeração (lotação ' || p_ref.max_l || ' → ' || r.max_l || ')'); END IF;
    END IF;
    o.put('evita', l_evi);

    l_msg := 'Sugestão para ' || p_perfil.nome || ': ' || ROUND(r.metros) || ' m, cerca de '
          || minutos(r.metros, p_perfil.vel) || ' min.';
    IF l_evi.get_size > 0 THEN
      FOR i IN 0 .. l_evi.get_size - 1 LOOP
        l_evitas := l_evitas || CASE WHEN i > 0 THEN ', ' END || l_evi.get_string(i);
      END LOOP;
      l_msg := l_msg || ' Comparada à rota mais direta, evita ' || l_evitas || '.';
    END IF;
    IF p_ref.ok AND r.metros - p_ref.metros >= 5 THEN
      l_msg := l_msg || ' É ' || ROUND(r.metros - p_ref.metros) || ' m mais longa.';
    END IF;
    IF l_ale.get_size > 0 THEN
      l_msg := l_msg || ' Atenção: ' || l_ale.get_string(0);
    END IF;
    o.put('mensagem', l_msg || ' Você decide se segue.');
    RETURN o;
  END;

  -- ------------------------------------------------------------------ públicas
  FUNCTION eventos_json RETURN CLOB IS
    l CLOB;
  BEGIN
    SELECT JSON_OBJECT('eventos' VALUE NVL((
             SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo' VALUE codigo, 'nome' VALUE nome, 'local' VALUE local,
                                              'descricao' VALUE descricao) ORDER BY id DESC RETURNING CLOB)
               FROM ac_evento WHERE codigo IS NOT NULL), '[]') FORMAT JSON RETURNING CLOB)
      INTO l FROM dual;
    RETURN l;
  END;

  FUNCTION mapa_json(p_evento VARCHAR2) RETURN CLOB IS
    l_id NUMBER := evento_id(p_evento);
    l    CLOB;
  BEGIN
    SELECT JSON_OBJECT(
      'evento' VALUE JSON_OBJECT('codigo' VALUE e.codigo, 'nome' VALUE e.nome, 'local' VALUE e.local,
                                 'largura_px' VALUE e.largura_px, 'altura_px' VALUE e.altura_px,
                                 'escala_m_px' VALUE e.escala_m_px, 'planta_url' VALUE e.planta_url,
                                 'descricao' VALUE e.descricao, 'origem_padrao' VALUE e.origem_padrao),
      'perfis' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo' VALUE codigo, 'nome' VALUE nome,
                            'descricao' VALUE descricao, 'evita_escada' VALUE evita_escada,
                            'velocidade_ms' VALUE velocidade_ms,
                            'peso_ruido' VALUE peso_ruido, 'peso_lotacao' VALUE peso_lotacao)
                          ORDER BY DECODE(codigo, 'PADRAO', 1, 'CADEIRANTE', 2, 'MOBILIDADE', 3, 4) RETURNING CLOB)
                          FROM ac_perfil), '[]') FORMAT JSON,
      'areas' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo' VALUE codigo, 'nome' VALUE nome, 'tipo' VALUE tipo,
                           'x' VALUE x, 'y' VALUE y, 'largura' VALUE largura, 'altura' VALUE altura,
                           'cor' VALUE cor, 'subtitulo' VALUE subtitulo)
                         ORDER BY id RETURNING CLOB)
                         FROM ac_area WHERE evento_id = e.id), '[]') FORMAT JSON,
      'pontos' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('codigo' VALUE codigo, 'nome' VALUE nome, 'tipo' VALUE tipo,
                            'x' VALUE x, 'y' VALUE y, 'bloqueado' VALUE bloqueado)
                          ORDER BY id RETURNING CLOB)
                          FROM ac_ponto WHERE evento_id = e.id), '[]') FORMAT JSON,
      'trechos' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('id' VALUE t.id, 'a' VALUE pa.codigo, 'b' VALUE pb.codigo,
                             'via' VALUE t.via, 'distancia_m' VALUE t.distancia, 'escada' VALUE t.tem_escada,
                             'ruido' VALUE t.ruido, 'lotacao' VALUE t.lotacao,
                             'ruido_base' VALUE t.ruido_base, 'lotacao_base' VALUE t.lotacao_base,
                             'bloqueado' VALUE t.bloqueado)
                           ORDER BY t.id RETURNING CLOB)
                           FROM ac_trecho t
                           JOIN ac_ponto pa ON pa.id = t.ponto_a
                           JOIN ac_ponto pb ON pb.id = t.ponto_b
                          WHERE t.evento_id = e.id), '[]') FORMAT JSON,
      'reportes' VALUE NVL((SELECT JSON_ARRAYAGG(JSON_OBJECT('ponto' VALUE codigo, 'nome' VALUE nome, 'tipo' VALUE tipo,
                              'por' VALUE reportado_por, 'em' VALUE criado_em)
                            ORDER BY criado_em DESC RETURNING CLOB)
                            FROM (SELECT p.codigo, p.nome, r.tipo, r.reportado_por, r.criado_em
                                    FROM ac_reporte r JOIN ac_ponto p ON p.id = r.ponto_id
                                   WHERE r.evento_id = e.id
                                   ORDER BY r.criado_em DESC FETCH FIRST 20 ROWS ONLY)), '[]') FORMAT JSON
      RETURNING CLOB)
      INTO l
      FROM ac_evento e WHERE e.id = l_id;
    RETURN l;
  END;

  FUNCTION rota_json(p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) RETURN CLOB IS
    l_ev  NUMBER   := evento_id(p_evento);
    l_pf  r_perfil := perfil(p_perfil);
    l_ori NUMBER   := ponto_id(l_ev, p_origem, 'origem');
    l_des NUMBER   := ponto_id(l_ev, p_destino, 'destino');
    l_b   r_busca;
    l_ref r_resumo;
  BEGIN
    l_b   := buscar(l_ev, l_pf, l_ori);
    l_ref := resumir(buscar(l_ev, perfil('PADRAO'), l_ori), l_des);
    RETURN rota_obj(l_pf, l_b, resumir(l_b, l_des), l_des, l_ref).to_clob;
  END;

  FUNCTION comparar_json(p_evento VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) RETURN CLOB IS
    l_ev  NUMBER := evento_id(p_evento);
    l_ori NUMBER := ponto_id(l_ev, p_origem, 'origem');
    l_des NUMBER := ponto_id(l_ev, p_destino, 'destino');
    l_ref r_resumo;
    l_b   r_busca;
    l_pf  r_perfil;
    l_arr JSON_ARRAY_T := JSON_ARRAY_T();
    o     JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    l_ref := resumir(buscar(l_ev, perfil('PADRAO'), l_ori), l_des);
    FOR p IN (SELECT codigo FROM ac_perfil ORDER BY DECODE(codigo, 'PADRAO', 1, 'CADEIRANTE', 2, 'MOBILIDADE', 3, 4)) LOOP
      l_pf := perfil(p.codigo);
      l_b  := buscar(l_ev, l_pf, l_ori);
      l_arr.append(rota_obj(l_pf, l_b, resumir(l_b, l_des), l_des, l_ref));
    END LOOP;
    o.put('rotas', l_arr);
    RETURN o.to_clob;
  END;

  FUNCTION rota_saida_json(p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2) RETURN CLOB IS
    l_ev   NUMBER   := evento_id(p_evento);
    l_pf   r_perfil := perfil(p_perfil);
    l_ori  NUMBER   := ponto_id(l_ev, p_origem, 'origem');
    l_b    r_busca;
    l_ids  t_num;
    l_tmp  NUMBER;
    l_r    r_resumo;
    l_best r_resumo;
    l_ref  r_resumo;
    l_bid  NUMBER;
    o      JSON_OBJECT_T;
    l_alt  JSON_ARRAY_T := JSON_ARRAY_T();
    l_ind  JSON_ARRAY_T := JSON_ARRAY_T();
    l_a    JSON_OBJECT_T;
    l_cods JSON_ARRAY_T;
    l_txt  VARCHAR2(1000);
    l_ref_b r_busca;
    l_ref_id NUMBER;
  BEGIN
    l_b := buscar(l_ev, l_pf, l_ori);

    FOR s IN (SELECT id, codigo, nome, bloqueado FROM ac_ponto
               WHERE evento_id = l_ev AND tipo = 'SAIDA' ORDER BY id) LOOP
      IF s.bloqueado = 'S' OR l_b.dist(s.id) >= c_inf THEN
        l_a := JSON_OBJECT_T();
        l_a.put('codigo', s.codigo); l_a.put('nome', s.nome);
        l_a.put('motivo', CASE WHEN s.bloqueado = 'S' THEN 'interditada'
                               ELSE 'sem caminho viável para este perfil' END);
        l_ind.append(l_a);
      ELSE
        l_ids(l_ids.COUNT + 1) := s.id;
      END IF;
    END LOOP;

    -- ordena por custo (poucas saídas: insertion sort)
    FOR i IN 2 .. l_ids.COUNT LOOP
      FOR j IN REVERSE 2 .. i LOOP
        EXIT WHEN l_b.dist(l_ids(j - 1)) <= l_b.dist(l_ids(j));
        l_tmp := l_ids(j); l_ids(j) := l_ids(j - 1); l_ids(j - 1) := l_tmp;
      END LOOP;
    END LOOP;

    IF l_ids.COUNT = 0 THEN
      o := JSON_OBJECT_T();
      o.put('status', 'SEM_ROTA');
      o.put('perfil', l_pf.codigo);
      o.put('origem', ponto_obj(l_ori));
      o.put('mensagem', 'Nenhuma saída alcançável sem barreiras a partir daqui. Permaneça em local seguro e chame a brigada.');
      o.put('indisponiveis', l_ind);
      RETURN o.to_clob;
    END IF;

    -- referência: a saída que o perfil PADRAO pegaria
    l_ref_b := buscar(l_ev, perfil('PADRAO'), l_ori);
    FOR s IN (SELECT id FROM ac_ponto WHERE evento_id = l_ev AND tipo = 'SAIDA' AND bloqueado = 'N') LOOP
      IF l_ref_b.dist(s.id) < c_inf AND (l_ref_id IS NULL OR l_ref_b.dist(s.id) < l_ref_b.dist(l_ref_id)) THEN
        l_ref_id := s.id;
      END IF;
    END LOOP;
    IF l_ref_id IS NOT NULL THEN l_ref := resumir(l_ref_b, l_ref_id); END IF;

    l_bid  := l_ids(1);
    l_best := resumir(l_b, l_bid);
    o := rota_obj(l_pf, l_b, l_best, l_bid, l_ref);

    FOR i IN 2 .. l_ids.COUNT LOOP
      l_r := resumir(l_b, l_ids(i));
      l_a := ponto_obj(l_ids(i));
      l_a.put('distancia_m', ROUND(l_r.metros));
      l_a.put('tempo_min', minutos(l_r.metros, l_pf.vel));
      l_a.put('custo', ROUND(l_r.custo, 1));
      l_a.put('tem_escada', l_r.escada);
      l_a.put('ruido_max', l_r.max_r);
      l_a.put('lotacao_max', l_r.max_l);
      l_cods := JSON_ARRAY_T();
      FOR k IN 1 .. l_r.pts.COUNT LOOP
        l_cods.append(ponto_obj(l_r.pts(k)).get_string('codigo'));
      END LOOP;
      l_a.put('caminho', l_cods);
      l_alt.append(l_a);
      IF i <= 3 THEN
        l_txt := l_txt || CASE WHEN i > 2 THEN '; ' END || ponto_nome(l_ids(i)) || ' (' || ROUND(l_r.metros) || ' m)';
      END IF;
    END LOOP;

    o.put('saida_sugerida', ponto_obj(l_bid));
    o.put('alternativas', l_alt);
    o.put('indisponiveis', l_ind);
    o.put('mensagem', 'Saída sugerida: ' || ponto_nome(l_bid) || '. ' || o.get_string('mensagem')
                   || CASE WHEN l_txt IS NOT NULL THEN ' Outras opções: ' || l_txt || '.' END);
    RETURN o.to_clob;
  END;

  FUNCTION reportar_json(p_evento VARCHAR2, p_ponto VARCHAR2, p_tipo VARCHAR2, p_usuario VARCHAR2 DEFAULT NULL, p_detalhe VARCHAR2 DEFAULT NULL) RETURN CLOB IS
    l_ev   NUMBER := evento_id(p_evento);
    l_pid  NUMBER := ponto_id(l_ev, p_ponto, 'ponto');
    l_tipo VARCHAR2(20) := UPPER(TRIM(p_tipo));
    l_msg  VARCHAR2(400);
    o      JSON_OBJECT_T := JSON_OBJECT_T();
  BEGIN
    IF l_tipo IS NULL OR l_tipo NOT IN ('CHEIO', 'BARULHO', 'BLOQUEIO', 'LIBERADO') THEN
      raise_application_error(-20400, 'tipo deve ser CHEIO, BARULHO, BLOQUEIO ou LIBERADO');
    END IF;

    INSERT INTO ac_reporte (evento_id, ponto_id, tipo, reportado_por, detalhe)
    VALUES (l_ev, l_pid, l_tipo, NVL(SUBSTR(p_usuario, 1, 100), 'anonimo'), SUBSTR(p_detalhe, 1, 400));

    CASE l_tipo
      WHEN 'CHEIO' THEN
        UPDATE ac_trecho SET lotacao = LEAST(lotacao + 1, 5)
         WHERE evento_id = l_ev AND l_pid IN (ponto_a, ponto_b);
        l_msg := 'Lotação aumentada perto de ';
      WHEN 'BARULHO' THEN
        UPDATE ac_trecho SET ruido = LEAST(ruido + 1, 5)
         WHERE evento_id = l_ev AND l_pid IN (ponto_a, ponto_b);
        l_msg := 'Barulho aumentado perto de ';
      WHEN 'BLOQUEIO' THEN
        UPDATE ac_ponto SET bloqueado = 'S' WHERE id = l_pid;
        l_msg := 'Passagem interditada: ';
      WHEN 'LIBERADO' THEN
        UPDATE ac_ponto SET bloqueado = 'N' WHERE id = l_pid;
        UPDATE ac_trecho SET ruido = ruido_base, lotacao = lotacao_base
         WHERE evento_id = l_ev AND l_pid IN (ponto_a, ponto_b);
        l_msg := 'Situação normalizada em ';
    END CASE;
    COMMIT;

    o.put('status', 'OK');
    o.put('tipo', l_tipo);
    o.put('ponto', ponto_obj(l_pid));
    o.put('mensagem', 'Obrigado! ' || l_msg || ponto_nome(l_pid) || '. As rotas já consideram isso.');
    RETURN o.to_clob;
  END;

  PROCEDURE reset_demo(p_evento VARCHAR2) IS
    l_ev NUMBER := evento_id(p_evento);
  BEGIN
    UPDATE ac_trecho SET ruido = ruido_base, lotacao = lotacao_base, bloqueado = 'N' WHERE evento_id = l_ev;
    UPDATE ac_ponto  SET bloqueado = 'N' WHERE evento_id = l_ev;
    DELETE FROM ac_reporte WHERE evento_id = l_ev;
    COMMIT;
  END;

  -- ------------------------------------------------------------------ ORDS
  PROCEDURE responder(p_json CLOB, p_status PLS_INTEGER DEFAULT 200) IS
    l_off PLS_INTEGER := 1;
    l_len PLS_INTEGER := NVL(DBMS_LOB.getlength(p_json), 0);
  BEGIN
    OWA_UTIL.status_line(p_status, NULL, FALSE);
    OWA_UTIL.mime_header('application/json', FALSE, 'UTF-8');
    HTP.p('Cache-Control: no-store');
    OWA_UTIL.http_header_close;
    WHILE l_off <= l_len LOOP
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
    responder(o.to_clob, CASE p_code WHEN -20400 THEN 400 WHEN -20404 THEN 404 ELSE 500 END);
  END;

  PROCEDURE api_eventos IS
  BEGIN
    responder(eventos_json);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_mapa(p_evento VARCHAR2) IS
  BEGIN
    responder(mapa_json(p_evento));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_rota(p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) IS
  BEGIN
    responder(rota_json(p_evento, p_perfil, p_origem, p_destino));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_comparar(p_evento VARCHAR2, p_origem VARCHAR2, p_destino VARCHAR2) IS
  BEGIN
    responder(comparar_json(p_evento, p_origem, p_destino));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_saida(p_evento VARCHAR2, p_perfil VARCHAR2, p_origem VARCHAR2) IS
  BEGIN
    responder(rota_saida_json(p_evento, p_perfil, p_origem));
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_reportar(p_evento VARCHAR2, p_body CLOB) IS
    j JSON_OBJECT_T;
  BEGIN
    BEGIN
      j := JSON_OBJECT_T.parse(NVL(p_body, '{}'));
    EXCEPTION WHEN OTHERS THEN
      raise_application_error(-20400, 'Corpo JSON inválido');
    END;
    responder(reportar_json(p_evento, j.get_string('ponto'), j.get_string('tipo'),
                            j.get_string('usuario'), j.get_string('detalhe')), 201);
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;

  PROCEDURE api_reset(p_evento VARCHAR2) IS
  BEGIN
    reset_demo(p_evento);
    responder('{"status":"OK","mensagem":"Cenário da demo restaurado."}');
  EXCEPTION WHEN OTHERS THEN erro(SQLCODE, SQLERRM);
  END;
END ac_rotas;
/

-- sanity
SELECT object_name, object_type, status FROM user_objects WHERE object_name = 'AC_ROTAS';
