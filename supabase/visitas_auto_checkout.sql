-- =============================================================================
-- visitas_auto_checkout.sql   |   sprint 9.32.259
-- =============================================================================
-- Adiciona colunas pra controlar avisos de visita aberta + auto-checkout.
-- Também configura pg_cron pra rodar a Edge Function `verificar-visitas-abertas`
-- a cada 15 minutos.
--
-- COMO RODAR:
--   1. Painel Supabase → SQL Editor → New query
--   2. ANTES DE RODAR: substitua os placeholders no BLOCO 4:
--        - <SEU_PROJECT_REF>      → ref do projeto (ex: qrlnbtxscjrmnpfjbtvv)
--        - <SUA_SERVICE_ROLE_KEY> → chave em Settings → API → service_role secret
--   3. Cole o conteúdo INTEIRO e RUN
--
-- IMPORTANTE — NÃO MEXE EM NADA DO GPS / CHECK-IN / TIMER ATUAL.
--   Só lê dados que já existem (checkin_timestamp, checkout_timestamp).
-- =============================================================================


-- ===== BLOCO 1: NOVAS COLUNAS NA TABELA `visitas` =====
ALTER TABLE public.visitas
  ADD COLUMN IF NOT EXISTS aviso_2h_em        timestamptz,
  ADD COLUMN IF NOT EXISTS aviso_4h_em        timestamptz,
  ADD COLUMN IF NOT EXISTS aviso_6h_em        timestamptz,
  ADD COLUMN IF NOT EXISTS checkout_automatico boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS auto_checkout_em   timestamptz;

COMMENT ON COLUMN public.visitas.aviso_2h_em IS 'Quando o aviso "esqueceu checkout 2h" foi disparado';
COMMENT ON COLUMN public.visitas.aviso_4h_em IS 'Quando o aviso "esqueceu checkout 4h" foi disparado';
COMMENT ON COLUMN public.visitas.aviso_6h_em IS 'Quando o aviso "último alerta antes do auto-fechamento" foi disparado';
COMMENT ON COLUMN public.visitas.checkout_automatico IS 'TRUE quando o sistema fechou a visita por inatividade (>6h30 sem checkout)';
COMMENT ON COLUMN public.visitas.auto_checkout_em IS 'Timestamp do auto-fechamento, separado do checkout_timestamp pra auditoria';

-- ===== BLOCO 2: ÍNDICE PARCIAL PRA O CRON RODAR RÁPIDO =====
-- Filtra só visitas em aberto (checkin sim, checkout não)
CREATE INDEX IF NOT EXISTS visitas_em_aberto_idx
  ON public.visitas(checkin_timestamp)
  WHERE checkout_timestamp IS NULL AND checkin_timestamp IS NOT NULL;


-- ===== BLOCO 3: AJUSTE NÃO-RETROATIVO =====
-- Marca todas as visitas atualmente em aberto como "já avisadas" pra evitar
-- avalanche de avisos retroativos no primeiro disparo do cron.
-- Se houver visita realmente esquecida, vc pode reverter manualmente depois.
UPDATE public.visitas
   SET aviso_2h_em = COALESCE(aviso_2h_em, now()),
       aviso_4h_em = COALESCE(aviso_4h_em, now()),
       aviso_6h_em = COALESCE(aviso_6h_em, now())
 WHERE checkin_timestamp IS NOT NULL
   AND checkout_timestamp IS NULL;


-- ===== BLOCO 4: AGENDAR pg_cron PRA RODAR A CADA 15 MIN =====
-- ATENÇÃO: substitua os placeholders abaixo!
--
-- 1. Habilita extensões necessárias (idempotente — não dá erro se já habilitado)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 2. Remove agendamento antigo (caso esteja rodando uma versão anterior)
SELECT cron.unschedule('verificar-visitas-abertas')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'verificar-visitas-abertas');

-- 3. Cria o agendamento — roda a cada 15 minutos
--    ⚠️ TROCAR <SEU_PROJECT_REF> E <SUA_SERVICE_ROLE_KEY> ABAIXO ⚠️
SELECT cron.schedule(
  'verificar-visitas-abertas',     -- nome do job
  '*/15 * * * *',                   -- expressão cron: a cada 15 min
  $$
  SELECT net.http_post(
    url := 'https://<SEU_PROJECT_REF>.supabase.co/functions/v1/verificar-visitas-abertas',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer <SUA_SERVICE_ROLE_KEY>'
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);


-- ===== VERIFICAÇÃO =====
-- Confere que o job foi agendado corretamente:
SELECT jobid, jobname, schedule, active
  FROM cron.job
 WHERE jobname = 'verificar-visitas-abertas';
-- Esperado: 1 linha, active = true, schedule = '*/15 * * * *'

-- Confere as novas colunas:
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'visitas'
   AND column_name IN ('aviso_2h_em','aviso_4h_em','aviso_6h_em','checkout_automatico','auto_checkout_em');
-- Esperado: 5 linhas


-- ===== HELPERS DE DEBUG (rode quando quiser conferir) =====

-- Ver últimas execuções do cron (sucesso/falha):
-- SELECT * FROM cron.job_run_details
--  WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'verificar-visitas-abertas')
--  ORDER BY start_time DESC LIMIT 10;

-- Ver visitas em aberto e quais avisos já foram disparados:
-- SELECT id, nutricionista_id,
--        checkin_timestamp,
--        EXTRACT(EPOCH FROM (now() - checkin_timestamp))/60 AS minutos_aberto,
--        aviso_2h_em, aviso_4h_em, aviso_6h_em,
--        checkout_automatico, auto_checkout_em
--   FROM public.visitas
--  WHERE checkin_timestamp IS NOT NULL AND checkout_timestamp IS NULL
--  ORDER BY checkin_timestamp;

-- Cancelar o cron (se precisar pausar a feature):
-- SELECT cron.unschedule('verificar-visitas-abertas');


-- =============================================================================
-- FIM
-- =============================================================================
