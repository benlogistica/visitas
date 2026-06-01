-- ============================================================================
-- arquivar_usuario.sql · Sprint 9.32.358
-- ============================================================================
-- Adiciona campos pra "arquivar" usuarios — diferente de desativar.
--   - Desativado: nao loga, mas aparece em "Desativados"
--   - Arquivado: nao loga E sai da lista padrao (so aparece com toggle)
-- Histórico (visitas, instituicoes cadastradas, etc.) preservado em ambos os casos.
-- ============================================================================

ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS arquivado boolean DEFAULT false NOT NULL,
  ADD COLUMN IF NOT EXISTS arquivado_em timestamptz,
  ADD COLUMN IF NOT EXISTS arquivado_por uuid REFERENCES usuarios(id) ON DELETE SET NULL;

COMMENT ON COLUMN usuarios.arquivado IS
  'Sprint 9.32.358: true quando o admin removeu o usuario da visualizacao padrao. Diferente de status=inativo (que so impede login). Reversivel.';
COMMENT ON COLUMN usuarios.arquivado_em IS 'Sprint 9.32.358: timestamp do arquivamento.';
COMMENT ON COLUMN usuarios.arquivado_por IS 'Sprint 9.32.358: id do admin que arquivou.';

-- Index parcial pra filtrar arquivados rapidamente
CREATE INDEX IF NOT EXISTS usuarios_arquivado_idx
  ON usuarios(arquivado)
  WHERE arquivado = true;

NOTIFY pgrst, 'reload schema';

-- Verificacao
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'usuarios'
   AND column_name IN ('arquivado', 'arquivado_em', 'arquivado_por')
 ORDER BY column_name;
