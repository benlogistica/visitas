-- ============================================================================
-- ultima_atividade.sql · Sprint 9.32.355
-- ============================================================================
-- Adiciona coluna pra rastrear quando o usuario realmente abriu o app
-- (diferente de ultimo_login, que so muda quando digita senha).
-- ============================================================================

ALTER TABLE usuarios
  ADD COLUMN IF NOT EXISTS ultima_atividade timestamptz;

COMMENT ON COLUMN usuarios.ultima_atividade IS
  'Sprint 9.32.355: timestamp da ultima vez que o usuario abriu o app com sessao valida (atualizado no boot, nao no login).';

-- Inicializa com ultimo_login pros existentes (melhor que NULL)
UPDATE usuarios SET ultima_atividade = COALESCE(ultima_atividade, ultimo_login);

-- Index pra ordenar/filtrar
CREATE INDEX IF NOT EXISTS usuarios_ultima_atividade_idx
  ON usuarios(ultima_atividade DESC NULLS LAST);

NOTIFY pgrst, 'reload schema';

-- Verificacao
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'usuarios' AND column_name = 'ultima_atividade';
