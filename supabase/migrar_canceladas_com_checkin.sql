-- ============================================================================
-- migrar_canceladas_com_checkin.sql · Sprint 9.32.330
-- ============================================================================
-- Aplica a regra: visita SEM check-in = cancelada / visita COM check-in = não realizada.
--
-- Antes: cancelarVisita() era usada em qualquer cenário, mesmo com check-in feito.
-- Agora: visitas com check-in foram migradas pra "não realizada" (preserva esforço).
-- ============================================================================

-- 1. Diagnóstico — quantas visitas cada categoria
SELECT
  COUNT(*) FILTER (WHERE cancelado_em IS NOT NULL AND checkin_timestamp IS NOT NULL) AS canceladas_com_checkin_a_migrar,
  COUNT(*) FILTER (WHERE cancelado_em IS NOT NULL AND checkin_timestamp IS NULL)     AS canceladas_legitimas_sem_checkin,
  COUNT(*) FILTER (WHERE visita_realizada = false AND cancelado_em IS NULL)          AS nao_realizadas_atuais
  FROM visitas;

-- 2. Migração — visitas com checkin que foram canceladas viram "não realizada"
UPDATE visitas
   SET visita_realizada = false,
       motivo_nao_realizada = COALESCE(motivo_nao_realizada, cancelamento_motivo),
       cancelamento_motivo = NULL,
       cancelado_em = NULL,
       cancelado_por = NULL,
       status = CASE
         WHEN status = 'cancelada' THEN 'completa'
         WHEN status IS NULL THEN 'completa'
         ELSE status
       END
 WHERE cancelado_em IS NOT NULL
   AND checkin_timestamp IS NOT NULL;

-- 3. Confirmação
SELECT
  COUNT(*) FILTER (WHERE cancelado_em IS NOT NULL AND checkin_timestamp IS NOT NULL) AS ainda_inconsistentes_zero_esperado,
  COUNT(*) FILTER (WHERE cancelado_em IS NOT NULL)                                   AS canceladas_total_apos_migracao,
  COUNT(*) FILTER (WHERE visita_realizada = false AND cancelado_em IS NULL)          AS nao_realizadas_total_apos_migracao
  FROM visitas;
