-- ============================================================================
-- fix_cnpj_persistencia.sql  —  Sprint 9.32.374
-- ----------------------------------------------------------------------------
-- PROBLEMA: o time relata que ao salvar/atribuir o CNPJ de uma instituição,
-- "às vezes salva, às vezes não" — sem nenhuma mensagem de erro (só o verde de
-- sucesso). O código JS envia o cnpj corretamente nos dois fluxos (criar e
-- editar), então a causa está no banco / na camada PostgREST do Supabase.
--
-- Duas causas conhecidas, ambas resolvidas aqui:
--   1) Schema cache do PostgREST desatualizado: depois que a coluna `cnpj` foi
--      criada, o PostgREST pode aceitar o UPDATE e SILENCIOSAMENTE ignorar a
--      coluna em parte das requisições -> parece que salvou mas não salvou.
--   2) Constraint UNIQUE em `cnpj`: impede matriz + filiais (ou re-atribuição)
--      de compartilharem o mesmo CNPJ.
--
-- Como rodar: Supabase -> SQL Editor -> cole tudo -> Run.
-- É IDEMPOTENTE (pode rodar quantas vezes quiser, sem efeito colateral).
-- ============================================================================

-- 1. Garante que a coluna cnpj existe (não faz nada se já existe)
ALTER TABLE public.instituicoes
  ADD COLUMN IF NOT EXISTS cnpj text;

-- 2. Remove qualquer constraint UNIQUE que envolva SÓ a coluna cnpj
DO $$
DECLARE
  v_constraint_name text;
BEGIN
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
    EXECUTE format('ALTER TABLE public.instituicoes DROP CONSTRAINT %I', v_constraint_name);
    RAISE NOTICE '✓ Constraint UNIQUE em cnpj removida: %', v_constraint_name;
  ELSE
    RAISE NOTICE '✓ Nenhuma constraint UNIQUE em cnpj encontrada — OK.';
  END IF;
END $$;

-- 3. Recarrega o schema cache do PostgREST (a correção principal pro
--    "às vezes salva, às vezes não"). Sem isso, o cache antigo continua
--    ignorando a coluna em parte dos workers.
NOTIFY pgrst, 'reload schema';

-- 4. Verificação — confirma que a coluna existe e mostra a contagem atual
SELECT
  (SELECT count(*) FROM public.instituicoes)                          AS total_instituicoes,
  (SELECT count(*) FROM public.instituicoes WHERE cnpj IS NOT NULL)   AS com_cnpj,
  (SELECT count(*) FROM information_schema.columns
     WHERE table_name = 'instituicoes' AND column_name = 'cnpj')      AS coluna_cnpj_existe;

-- Esperado: coluna_cnpj_existe = 1.
-- Depois de rodar, faça um hard reload (Ctrl+Shift+R) no app e teste salvar
-- um CNPJ. Se o app passar a avisar "CNPJ não foi gravado", o cache ainda não
-- propagou — espere 1-2 min e rode o passo 3 (NOTIFY) de novo.
