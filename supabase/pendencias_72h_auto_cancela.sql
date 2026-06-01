-- ============================================================================
-- pendencias_72h_auto_cancela.sql · Sprint 9.32.339
-- ============================================================================
-- Suporta o fluxo de pendências de 72h:
-- 1. Distinguir cancelamento manual vs automático após 72h sem ação
-- 2. Marcar visitas com check-in tardio (caso "fui, esqueci o check-in")
-- 3. Função + cron pra auto-cancelar agendamentos vencidos > 72h
--
-- Pré-requisito: extensão pg_cron habilitada no Supabase
-- (Dashboard → Database → Extensions → procurar "pg_cron" → Enable)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Novas colunas em visitas
-- ---------------------------------------------------------------------------
ALTER TABLE visitas
  ADD COLUMN IF NOT EXISTS cancelamento_origem text
    DEFAULT 'manual' NOT NULL
    CHECK (cancelamento_origem IN ('manual', 'auto_72h')),
  ADD COLUMN IF NOT EXISTS checkin_retroativo boolean
    DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS checkin_dias_atraso int
    DEFAULT 0;

COMMENT ON COLUMN visitas.cancelamento_origem IS
  'Sprint 9.32.339: origem do cancelamento. "manual" = nutri/admin clicou cancelar; "auto_72h" = sistema cancelou após 72h sem ação.';
COMMENT ON COLUMN visitas.checkin_retroativo IS
  'Sprint 9.32.339: true quando o check-in foi feito após o horário planejado (caso "fui, esqueci o check-in"). Sem GPS obrigatório.';
COMMENT ON COLUMN visitas.checkin_dias_atraso IS
  'Sprint 9.32.339: quantos dias de atraso teve o check-in retroativo. Mostrado como ícone "tardio" no relatório.';

-- ---------------------------------------------------------------------------
-- 2. Index pra filtrar canceladas por origem rapidamente
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS visitas_cancelamento_origem_idx
  ON visitas(cancelamento_origem)
  WHERE status = 'cancelada';

-- ---------------------------------------------------------------------------
-- 3. Função: auto-cancela agendamentos vencidos > 72h
-- ---------------------------------------------------------------------------
-- Critério: status='agendada' AND (data_visita + horario_inicio) + 72h < now()
-- Se horario_inicio for NULL, considera fim do dia (23:59) como referência.
-- Roda como SECURITY DEFINER pra bypassar RLS.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION auto_cancelar_agendamentos_72h()
RETURNS TABLE(
  visita_id uuid,
  instituicao_id uuid,
  nutricionista_id uuid,
  data_visita date,
  horario_inicio time,
  vencimento timestamp
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH atualizadas AS (
    UPDATE visitas v
       SET status              = 'cancelada',
           cancelado_em        = now(),
           cancelado_por       = NULL, -- sistema
           cancelamento_motivo = 'Auto: sem ação em 72h após o horário',
           cancelamento_origem = 'auto_72h'
     WHERE v.status = 'agendada'
       AND (
         (v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp
         AT TIME ZONE 'America/Sao_Paulo'
         + interval '72 hours'
       ) < now()
    RETURNING
      v.id,
      v.instituicao_id,
      v.nutricionista_id,
      v.data_visita,
      v.horario_inicio,
      ((v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp + interval '72 hours') AS vencimento
  )
  SELECT * FROM atualizadas;
END;
$$;

COMMENT ON FUNCTION auto_cancelar_agendamentos_72h IS
  'Sprint 9.32.339: marca como cancelada todos agendamentos cujo horário + 72h já passou. Retorna lista das visitas afetadas pra log.';

-- ---------------------------------------------------------------------------
-- 4. Schedule do cron — roda a cada 1 hora (no minuto 0)
-- ---------------------------------------------------------------------------
-- ⚠ Se já existir um job com o mesmo nome, o reschedule sobrescreve.
DO $$
BEGIN
  -- Remove agendamento anterior se existir (idempotente)
  PERFORM cron.unschedule('auto_cancela_72h')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auto_cancela_72h');
EXCEPTION
  WHEN OTHERS THEN
    -- pg_cron pode não estar habilitado; deixa erro descritivo
    RAISE NOTICE 'pg_cron pode não estar habilitado: %', SQLERRM;
END $$;

SELECT cron.schedule(
  'auto_cancela_72h',
  '0 * * * *',  -- a cada hora cheia
  $$ SELECT auto_cancelar_agendamentos_72h(); $$
);

-- ---------------------------------------------------------------------------
-- 5. Recarrega cache do PostgREST (pra colunas novas aparecerem na API)
-- ---------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- VERIFICAÇÕES (rodar separadamente após migration)
-- ============================================================================

-- Confere as 3 colunas novas
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'visitas'
   AND column_name IN ('cancelamento_origem', 'checkin_retroativo', 'checkin_dias_atraso')
 ORDER BY column_name;

-- Confere o cron foi agendado (deve retornar 1 linha)
SELECT jobid, jobname, schedule, command, active
  FROM cron.job
 WHERE jobname = 'auto_cancela_72h';

-- Estado atual: agendamentos vencidos que SERÃO cancelados na próxima execução
SELECT
  id,
  instituicao_id,
  data_visita,
  horario_inicio,
  ((data_visita::text || ' ' || COALESCE(horario_inicio::text, '23:59'))::timestamp + interval '72 hours') AS vencimento,
  now() - ((data_visita::text || ' ' || COALESCE(horario_inicio::text, '23:59'))::timestamp + interval '72 hours') AS quanto_tempo_passado
  FROM visitas
 WHERE status = 'agendada'
   AND ((data_visita::text || ' ' || COALESCE(horario_inicio::text, '23:59'))::timestamp + interval '72 hours') < now()
 ORDER BY data_visita;

-- ============================================================================
-- TESTE MANUAL (opcional, simula execução do cron)
-- ============================================================================
-- SELECT * FROM auto_cancelar_agendamentos_72h();

-- ============================================================================
-- ROLLBACK (se precisar desfazer)
-- ============================================================================
-- SELECT cron.unschedule('auto_cancela_72h');
-- DROP FUNCTION IF EXISTS auto_cancelar_agendamentos_72h();
-- ALTER TABLE visitas
--   DROP COLUMN IF EXISTS cancelamento_origem,
--   DROP COLUMN IF EXISTS checkin_retroativo,
--   DROP COLUMN IF EXISTS checkin_dias_atraso;
-- DROP INDEX IF EXISTS visitas_cancelamento_origem_idx;
