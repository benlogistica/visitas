-- ============================================================================
-- matriz_unidades.sql · Sprint 9.32.360
-- ============================================================================
-- Modelo "matriz + unidades" pra permitir múltiplas instituições com mesmo CNPJ.
--
-- Caso de uso: empresas/hospitais que operam várias unidades (UPA, pronto-socorro,
-- ambulatório) sob o mesmo CNPJ legal mas com nomes/endereços diferentes na operação.
--
-- Modelo:
--   - Matriz: instituicao com matriz_id IS NULL (registro principal)
--   - Unidade: instituicao com matriz_id apontando pra matriz (mesmo CNPJ)
--   - Hierarquia 1 nível só (matriz não pode ser unidade de outra matriz)
-- ============================================================================

-- 1. Coluna matriz_id (self-reference)
ALTER TABLE instituicoes
  ADD COLUMN IF NOT EXISTS matriz_id uuid REFERENCES instituicoes(id) ON DELETE SET NULL;

COMMENT ON COLUMN instituicoes.matriz_id IS
  'Sprint 9.32.360: id da instituição matriz quando este é uma unidade. NULL = é a matriz (ou não tem relação).';

-- Index pra listar unidades de uma matriz rapidamente
CREATE INDEX IF NOT EXISTS instituicoes_matriz_id_idx
  ON instituicoes(matriz_id)
  WHERE matriz_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 2. Verifica e remove constraint UNIQUE em cnpj (se houver)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_constraint_name text;
BEGIN
  -- Acha o nome da constraint UNIQUE que envolve só a coluna cnpj
  SELECT con.conname INTO v_constraint_name
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
   WHERE rel.relname = 'instituicoes'
     AND con.contype = 'u'
     AND att.attname = 'cnpj'
     AND array_length(con.conkey, 1) = 1
   LIMIT 1;

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE instituicoes DROP CONSTRAINT %I', v_constraint_name);
    RAISE NOTICE '✓ Constraint UNIQUE em cnpj removida: %', v_constraint_name;
  ELSE
    RAISE NOTICE '✓ Nenhuma constraint UNIQUE em cnpj encontrada — OK.';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 3. Recarrega cache do PostgREST
-- ----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

-- ----------------------------------------------------------------------------
-- 4. Verificação
-- ----------------------------------------------------------------------------
SELECT column_name, data_type, column_default, is_nullable
  FROM information_schema.columns
 WHERE table_name = 'instituicoes' AND column_name = 'matriz_id';

-- Lista constraints UNIQUE remanescentes em instituicoes
SELECT con.conname, pg_get_constraintdef(con.oid) AS definicao
  FROM pg_constraint con
  JOIN pg_class rel ON rel.oid = con.conrelid
 WHERE rel.relname = 'instituicoes'
   AND con.contype = 'u';
