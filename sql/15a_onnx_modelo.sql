-- =====================================================================
-- 15a — Modelo de embedding ONNX DENTRO do banco (roda como ACESSO_APP)
-- Pré-requisito (ADMIN): sql/00_admin_grants.sql
-- all_MiniLM_L12_v2 (384 dims), versão pré-empacotada pela Oracle para 23ai/26ai.
-- O modelo é baixado do Object Storage direto pelo banco e roda in-database:
-- nenhum texto de usuário sai do Oracle para gerar embedding.
-- =====================================================================
BEGIN
  DBMS_VECTOR.DROP_ONNX_MODEL(model_name => 'DOC_MODEL', force => TRUE);
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  DBMS_VECTOR.LOAD_ONNX_MODEL_CLOUD(
    model_name => 'DOC_MODEL',
    credential => NULL,
    uri        => 'https://adwc4pm.objectstorage.us-ashburn-1.oci.customer-oci.com/p/eLddQappgBJ7jNi6Guz9m9LOtYe2u8LWY19GfgU8flFK4N9YgP4kTlrE9Px3pE12/n/adwc4pm/b/OML-Resources/o/all_MiniLM_L12_v2.onnx',
    metadata   => JSON('{"function":"embedding","embeddingOutput":"embedding","input":{"input":["DATA"]}}'));
END;
/
SELECT model_name, mining_function, algorithm, algorithm_type, ROUND(model_size/1024/1024) mb
  FROM user_mining_models WHERE model_name = 'DOC_MODEL';
SELECT VECTOR_DIMENSION_COUNT(VECTOR_EMBEDDING(doc_model USING 'preciso de um lugar calmo' AS data)) dims FROM dual;
