-- =============================================================================
-- visitas_extensao.sql   |   sprint 9.32.269
-- =============================================================================
-- Adiciona suporte a "estender visita +2h" — pra visitas reais longas (cirurgia,
-- atendimento prolongado) que ultrapassam o threshold de 6h30 do auto-fechamento.
--
-- COMO RODAR:
--   Painel Supabase → SQL Editor → New query → cola tudo → Run.
--   Idempotente.
-- =============================================================================

ALTER TABLE public.visitas
  ADD COLUMN IF NOT EXISTS extensao_concedida_em timestamptz;

COMMENT ON COLUMN public.visitas.extensao_concedida_em IS
  'Quando o nutri clicou "Estender +2h" na tela de visita ativa. Se preenchido, o cron de auto-fechamento ignora a visita até checkin_timestamp + 8h30 (em vez de 6h30).';

-- ===== VERIFICAÇÃO =====
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema = 'public' AND table_name = 'visitas'
   AND column_name = 'extensao_concedida_em';
