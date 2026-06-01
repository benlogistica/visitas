-- ============================================================================
-- profissao_outro_pendente.sql · Sprint 9.32.349
-- ============================================================================
-- Adiciona suporte ao fluxo de "Profissão · Outro (especificar)" com aprovação
-- pelo admin (mesmo padrão do objetivos_pendente_aprovacao).
-- ============================================================================

ALTER TABLE profissionais
  ADD COLUMN IF NOT EXISTS profissao_outro_pendente boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS profissao_outro_sugerido_por uuid REFERENCES usuarios(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS profissao_outro_sugerido_em timestamptz DEFAULT now();

COMMENT ON COLUMN profissionais.profissao_outro_pendente IS
  'Sprint 9.32.349: true quando nutri sugeriu cargo livre via "Outro" e admin ainda não aprovou/normalizou.';
COMMENT ON COLUMN profissionais.profissao_outro_sugerido_por IS
  'Sprint 9.32.349: id do nutri que sugeriu o cargo personalizado.';
COMMENT ON COLUMN profissionais.profissao_outro_sugerido_em IS
  'Sprint 9.32.349: timestamp da sugestão.';

-- Índice parcial pra admin filtrar pendentes rapidamente
CREATE INDEX IF NOT EXISTS profissionais_profissao_outro_pendente_idx
  ON profissionais(profissao_outro_pendente)
  WHERE profissao_outro_pendente = true;

-- Recarrega cache do PostgREST
NOTIFY pgrst, 'reload schema';

-- Verificação
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'profissionais'
   AND column_name IN ('profissao_outro_pendente', 'profissao_outro_sugerido_por', 'profissao_outro_sugerido_em')
 ORDER BY column_name;
