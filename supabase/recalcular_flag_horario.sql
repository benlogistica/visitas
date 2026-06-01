-- ============================================================================
-- recalcular_flag_horario.sql · Sprint 9.32.328 (v2 — fix JSON type)
-- ============================================================================
-- Recalcula flag_horario_fora_margem pra TODAS as visitas usando regra atual:
--   diff_HHMM = | (horario_inicio HH*60+MM) - (checkin_timestamp HH*60+MM em SP) |
--   se diff > 90min → true; senão false
--
-- Margem hardcoded em 90 pra simplificar (default do sistema).
-- Se sua config tem outro valor, edita o "90" abaixo.
-- ============================================================================

UPDATE visitas v
   SET flag_horario_fora_margem = (
     CASE
       -- Sem dados: flag = false
       WHEN v.checkin_timestamp IS NULL OR v.horario_inicio IS NULL THEN false
       -- Compara HH:MM declarado vs HH:MM real (em America/Sao_Paulo)
       WHEN ABS(
         (EXTRACT(HOUR FROM v.horario_inicio::time)::int * 60 + EXTRACT(MINUTE FROM v.horario_inicio::time)::int)
         -
         (EXTRACT(HOUR FROM (v.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo')::time)::int * 60
          + EXTRACT(MINUTE FROM (v.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo')::time)::int)
       ) > 90 THEN true
       ELSE false
     END
   );

-- Verificação
SELECT
  COUNT(*) FILTER (WHERE flag_horario_fora_margem = true) AS com_flag_apos_recalc,
  COUNT(*) AS total_visitas
  FROM visitas;
