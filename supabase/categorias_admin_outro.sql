-- =============================================================================
-- categorias_admin_outro.sql   |   sprint 9.32.254
-- =============================================================================
-- Adiciona suporte a "Outro" na tela de cadastro:
--   1. Cria categoria "Administrador" (oficial, já ativa)
--   2. Adiciona coluna pendente_aprovacao em categorias_profissionais
--      pra distinguir categorias sugeridas pelos próprios usuários no cadastro
--      (que ficam aguardando o admin aprovar) das oficiais.
--
-- COMO RODAR:
--   Painel Supabase → SQL Editor → New query → cola tudo → Run
--   Idempotente (pode rodar várias vezes sem duplicar dados).
-- =============================================================================

-- ===== 1. NOVA COLUNA: pendente_aprovacao =====
ALTER TABLE public.categorias_profissionais
  ADD COLUMN IF NOT EXISTS pendente_aprovacao boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS categorias_profissionais_pendente_idx
  ON public.categorias_profissionais(pendente_aprovacao) WHERE pendente_aprovacao = true;


-- ===== 2. SEED: categoria "Administrador" como oficial =====
INSERT INTO public.categorias_profissionais (nome, ativo, pendente_aprovacao)
SELECT 'Administrador', true, false
WHERE NOT EXISTS (
  SELECT 1 FROM public.categorias_profissionais WHERE LOWER(nome) = 'administrador'
);


-- ===== VERIFICAÇÃO =====
SELECT id, nome, ativo, pendente_aprovacao
  FROM public.categorias_profissionais
 ORDER BY pendente_aprovacao DESC, ativo DESC, nome;
-- Esperado: deve aparecer "Administrador" entre as ativas, sem nenhuma pendente
-- (a menos que algum nutri tenha sugerido uma).
