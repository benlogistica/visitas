-- ============================================================================
-- Sprint 9.32.306 — Adiciona prazo (72h) pra resposta da revisão devolvida
-- ============================================================================
-- Hoje: quando admin devolve uma visita pro nutri, fica esperando indefinidamente.
-- Solução: coluna `revisao_expira_em` armazena timestamp do prazo (72h após devolver).
-- Front-end seta o valor ao devolver. SQL aqui só cria a coluna + backfill de visitas
-- que já estão em revisão.
-- ============================================================================

-- 1. Cria coluna (idempotente)
ALTER TABLE visitas
  ADD COLUMN IF NOT EXISTS revisao_expira_em timestamptz;

COMMENT ON COLUMN visitas.revisao_expira_em IS
  'Prazo pro nutri responder à revisão devolvida pelo admin. Setado pra revisao_solicitada_em + 72h. Nullado quando revisao_resolvida_em é setado.';

-- 2. Backfill: visitas que ESTÃO em revisão hoje recebem o prazo retroativo
--    (72h a partir de quando o admin devolveu — pode já ter expirado, está OK)
UPDATE visitas
   SET revisao_expira_em = revisao_solicitada_em + INTERVAL '72 hours'
 WHERE revisao_motivo IS NOT NULL
   AND revisao_solicitada_em IS NOT NULL
   AND revisao_resolvida_em IS NULL
   AND revisao_expira_em IS NULL;

-- 3. Verificação
SELECT
  COUNT(*) FILTER (WHERE revisao_motivo IS NOT NULL AND revisao_resolvida_em IS NULL) AS em_revisao,
  COUNT(*) FILTER (WHERE revisao_expira_em IS NOT NULL) AS com_prazo,
  COUNT(*) FILTER (WHERE revisao_expira_em < NOW() AND revisao_resolvida_em IS NULL) AS prazo_ja_expirado
  FROM visitas;
