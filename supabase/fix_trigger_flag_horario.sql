-- ============================================================================
-- fix_trigger_flag_horario.sql · Sprint 9.32.328
-- ============================================================================
-- Corrige bug no trigger tg_visitas_calcular_flags:
--   - ANTES: NEW.checkin_timestamp::TIME → extrai TIME em UTC (errado!)
--   - DEPOIS: AT TIME ZONE 'America/Sao_Paulo' antes de extrair → TIME local
--
-- Bug fazia visitas legítimas (HH:MM declarado = HH:MM real em SP) virarem flag=true
-- porque diff em UTC sempre dava 3h (= 180min) > 90min margem.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.tg_visitas_calcular_flags()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
    inst_lat DECIMAL;
    inst_lon DECIMAL;
    dist DECIMAL;
BEGIN
    -- Distância do check-in vs instituição
    IF NEW.checkin_latitude IS NOT NULL AND NEW.checkin_longitude IS NOT NULL THEN
        SELECT latitude, longitude INTO inst_lat, inst_lon
        FROM instituicoes WHERE id = NEW.instituicao_id;

        dist := calcular_distancia_metros(
            NEW.checkin_latitude, NEW.checkin_longitude, inst_lat, inst_lon
        );
        NEW.distancia_checkin_metros := dist;
        NEW.flag_gps_divergente := (dist > 500);
    END IF;

    -- Flags de ausência
    NEW.flag_sem_checkin := (NEW.checkin_timestamp IS NULL AND NEW.status != 'rascunho');
    NEW.flag_sem_checkout := (NEW.checkout_timestamp IS NULL AND NEW.status != 'rascunho');

    -- Flag horário fora da margem (1h30 = 5400s)
    -- ⭐ FIX Sprint 9.32.328: converte checkin_timestamp pro timezone São Paulo
    -- antes de extrair TIME, senão compara horario_inicio (BR local) com TIME em UTC.
    IF NEW.horario_inicio IS NOT NULL AND NEW.checkin_timestamp IS NOT NULL THEN
        NEW.flag_horario_fora_margem := ABS(EXTRACT(EPOCH FROM (
            NEW.horario_inicio - (NEW.checkin_timestamp AT TIME ZONE 'America/Sao_Paulo')::TIME
        ))) > 5400;  -- 1h30 = 5400 segundos
    END IF;

    NEW.atualizado_em := NOW();
    RETURN NEW;
END;
$function$;

-- ============================================================================
-- Recalcular flag pra todas as visitas existentes (forçando o trigger via UPDATE)
-- ============================================================================
-- Como o trigger é BEFORE UPDATE, esse UPDATE no-op recalcula automaticamente
UPDATE visitas SET atualizado_em = atualizado_em;

-- Verificação
SELECT
  COUNT(*) FILTER (WHERE flag_horario_fora_margem = true) AS com_flag_apos_fix,
  COUNT(*) AS total_visitas
  FROM visitas;
