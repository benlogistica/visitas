-- ============================================================================
-- debug_flag_horario.sql · Investigar por que tanta visita tá flagada
-- ============================================================================
-- Mostra os valores reais que o cálculo está usando, pra diagnosticar TZ
-- ou outras causas de divergência.
-- ============================================================================

SELECT
  v.id,
  v.checkin_timestamp,
  -- Como está em São Paulo (com AT TIME ZONE)
  TO_CHAR(v.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo', 'HH24:MI') AS checkin_hhmm_sp,
  -- Como está em UTC direto (sem conversão)
  TO_CHAR(v.checkin_timestamp, 'HH24:MI') AS checkin_hhmm_utc,
  -- horario_inicio direto (string)
  v.horario_inicio::text AS horario_inicio_text,
  TO_CHAR(v.horario_inicio::time, 'HH24:MI') AS horario_inicio_hhmm,
  -- Diff em minutos (pelo método atual da SQL)
  ABS(
    (EXTRACT(HOUR FROM v.horario_inicio::time)::int * 60 + EXTRACT(MINUTE FROM v.horario_inicio::time)::int)
    -
    (EXTRACT(HOUR FROM (v.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo')::time)::int * 60
     + EXTRACT(MINUTE FROM (v.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo')::time)::int)
  ) AS diff_min_sp,
  -- Diff alternativa (sem AT TIME ZONE — assume timestamp já em local)
  ABS(
    (EXTRACT(HOUR FROM v.horario_inicio::time)::int * 60 + EXTRACT(MINUTE FROM v.horario_inicio::time)::int)
    -
    (EXTRACT(HOUR FROM v.checkin_timestamp::time)::int * 60
     + EXTRACT(MINUTE FROM v.checkin_timestamp::time)::int)
  ) AS diff_min_direto,
  v.flag_horario_fora_margem AS flag_atual
FROM visitas v
WHERE v.checkin_timestamp IS NOT NULL
  AND v.horario_inicio IS NOT NULL
ORDER BY v.checkin_timestamp DESC
LIMIT 14;
