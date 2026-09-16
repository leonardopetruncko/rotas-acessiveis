-- Avaliação do AC_ASSISTENTE em frases NÃO usadas no ajuste (held-out). Evento NEXT26.
WITH teste (esp_nec, esp_perfil, esp_origem, esp_destino, texto) AS (
  SELECT 'CRISE_SENSORIAL', 'NEURODIVERGENTE', NULL, 'ACOLH', 'as luzes e a música estão me deixando atordoada' FROM dual UNION ALL
  SELECT 'CRISE_SENSORIAL', 'NEURODIVERGENTE', 'PALCO', 'ACOLH', 'estou do lado do palco principal e não aguento mais essa gritaria' FROM dual UNION ALL
  SELECT 'CRISE_SENSORIAL', 'NEURODIVERGENTE', NULL, 'ACOLH', 'meu sobrinho com TEA entrou em crise' FROM dual UNION ALL
  SELECT 'CRISE_SENSORIAL', 'NEURODIVERGENTE', NULL, 'ACOLH', 'quero um cantinho quieto pra respirar' FROM dual UNION ALL
  SELECT 'BANHEIRO', NULL, NULL, 'WC', 'tem banheiro por aqui?' FROM dual UNION ALL
  SELECT 'BANHEIRO', 'CADEIRANTE', NULL, 'WC', 'meu avô é cadeirante e precisa de um sanitário' FROM dual UNION ALL
  SELECT 'MAL_ESTAR', NULL, NULL, 'BRIG', 'uma pessoa caiu e bateu a cabeça' FROM dual UNION ALL
  SELECT 'MAL_ESTAR', NULL, NULL, 'BRIG', 'estou enjoado e com a vista escurecendo' FROM dual UNION ALL
  SELECT 'MAL_ESTAR', NULL, 'ARENA', 'BRIG', 'estou na arena e minha colega teve uma convulsão' FROM dual UNION ALL
  SELECT 'EMERGENCIA', NULL, NULL, NULL, 'sentiu cheiro de queimado? como a gente sai' FROM dual UNION ALL
  SELECT 'EMERGENCIA', NULL, NULL, NULL, 'o teto está caindo' FROM dual UNION ALL
  SELECT 'EMERGENCIA', 'CADEIRANTE', NULL, NULL, 'sou cadeirante, qual saída eu uso numa emergência' FROM dual UNION ALL
  SELECT 'COMIDA', NULL, NULL, 'ALIM', 'onde vende café' FROM dual UNION ALL
  SELECT 'COMIDA', NULL, NULL, 'ALIM', 'to morrendo de sede' FROM dual UNION ALL
  SELECT 'PALESTRA', NULL, NULL, 'PALCO', 'onde vai ser a apresentação principal' FROM dual UNION ALL
  SELECT NULL, 'MOBILIDADE', NULL, NULL, 'tenho mobilidade reduzida' FROM dual UNION ALL
  SELECT NULL, 'CADEIRANTE', NULL, NULL, 'vim com carrinho de bebê' FROM dual UNION ALL
  SELECT NULL, NULL, 'GCP', 'NVIDIA', 'estou no google cloud, quero ir para a nvidia' FROM dual UNION ALL
  SELECT NULL, NULL, 'STARTUPS', 'LABS', 'saindo das startups, como chego no fiap labs' FROM dual UNION ALL
  SELECT 'BANHEIRO', NULL, 'IBM', 'WC', 'estou perto da IBM, onde tem toalete' FROM dual
), r AS (
  SELECT t.*, JSON(ac_assistente.interpretar_json('NEXT26', t.texto)) j FROM teste t
), c AS (
  SELECT r.*,
         CASE WHEN NVL(esp_nec,'-')     = NVL(JSON_VALUE(j,'$.necessidade.codigo'),'-') THEN 1 ELSE 0 END ok_nec,
         CASE WHEN NVL(esp_perfil,'-')  = NVL(JSON_VALUE(j,'$.perfil.codigo'),'-')      THEN 1 ELSE 0 END ok_perfil,
         CASE WHEN NVL(esp_origem,'-')  = NVL(JSON_VALUE(j,'$.origem.codigo'),'-')      THEN 1 ELSE 0 END ok_origem,
         CASE WHEN NVL(esp_destino,'-') = NVL(JSON_VALUE(j,'$.destino.codigo'),'-')     THEN 1 ELSE 0 END ok_destino
    FROM r
)
SELECT SUBSTR(texto,1,48) texto, ok_nec||ok_perfil||ok_origem||ok_destino acertos,
       JSON_VALUE(j,'$.necessidade.codigo') nec, JSON_VALUE(j,'$.necessidade.metodo') metodo,
       JSON_VALUE(j,'$.perfil.codigo') perfil, JSON_VALUE(j,'$.origem.codigo') ori, JSON_VALUE(j,'$.destino.codigo') dest
  FROM c
UNION ALL
SELECT 'TOTAL (%)', ROUND(AVG(ok_nec)*100)||'/'||ROUND(AVG(ok_perfil)*100)||'/'||ROUND(AVG(ok_origem)*100)||'/'||ROUND(AVG(ok_destino)*100),
       'nec/perfil/origem/destino', ROUND(AVG(CASE WHEN ok_nec+ok_perfil+ok_origem+ok_destino = 4 THEN 1 ELSE 0 END)*100) || '% frases 100% certas', NULL, NULL, NULL
  FROM c;
