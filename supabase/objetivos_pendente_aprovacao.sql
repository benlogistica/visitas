-- ============================================================================
-- objetivos_pendente_aprovacao.sql · Sprint 9.32.331i
-- ============================================================================
-- Adiciona colunas que faltam em objetivos_visita pra suportar o fluxo
-- de "Outros (especificar)" — nutri sugere objetivo que admin aprova depois.
-- ============================================================================

ALTER TABLE objetivos_visita
  ADD COLUMN IF NOT EXISTS pendente_aprovacao boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS sugerido_por uuid REFERENCES usuarios(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS sugerido_em timestamptz DEFAULT now();

COMMENT ON COLUMN objetivos_visita.pendente_aprovacao IS
  'Sprint 9.32.331i: true quando nutri sugeriu mas admin ainda não aprovou.';
COMMENT ON COLUMN objetivos_visita.sugerido_por IS
  'Sprint 9.32.331i: id do usuario que sugeriu o objetivo (nutri).';
COMMENT ON COLUMN objetivos_visita.sugerido_em IS
  'Sprint 9.32.331i: timestamp da sugestão.';

-- Índice pra admin filtrar pendentes rapidamente
CREATE INDEX IF NOT EXISTS objetivos_visita_pendentes_idx
  ON objetivos_visita(pendente_aprovacao)
  WHERE pendente_aprovacao = true;

-- Recarrega cache do PostgREST (necessário pra colunas novas aparecerem na API)
NOTIFY pgrst, 'reload schema';

-- Verificação
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'objetivos_visita'
   AND column_name IN ('pendente_aprovacao', 'sugerido_por', 'sugerido_em')
 ORDER BY column_name;
