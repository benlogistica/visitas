-- ============================================================================
-- insights_ia.sql  —  Sprint 9.32.382
-- ----------------------------------------------------------------------------
-- Cache da análise gerada por IA na aba Insights do Faturamento.
--
-- POR QUE UM CACHE: a análise custa tokens (API paga por uso). Os dados de
-- faturamento só mudam quando você roda o `atualizar_dashboard.bat`, que
-- regenera o JSON e grava um novo `meta.gerado_em`. Então usamos esse carimbo
-- como chave: a IA é chamada UMA vez por sincronização, e todo mundo que abrir
-- a tela depois lê a versão salva — de graça.
--
-- Sem isso, cada abertura da aba seria uma chamada paga gerando o mesmo texto.
--
-- Como rodar: Supabase -> SQL Editor -> cole tudo -> Run.
-- Ao criar a tabela o Supabase avisa sobre RLS: escolha "Run without RLS",
-- para manter a consistência com o resto do projeto (login é customizado).
-- É IDEMPOTENTE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.insights_ia (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- chave de cache: vem de FAT_DATA.meta.gerado_em (muda a cada sync de dados)
  data_hash      text UNIQUE NOT NULL,
  -- a análise em si (JSON serializado: resumo, prioridades, risco, oportunidade)
  analise        text NOT NULL,
  modelo         text,
  tokens_entrada integer,
  tokens_saida   integer,
  periodo_fim    text,          -- só pra auditoria: até quando iam os dados
  gerado_em      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS insights_ia_data_hash_idx ON public.insights_ia (data_hash);
CREATE INDEX IF NOT EXISTS insights_ia_gerado_em_idx ON public.insights_ia (gerado_em DESC);

COMMENT ON TABLE public.insights_ia IS
  'Cache da leitura por IA do faturamento. Uma linha por sincronização de dados (data_hash = meta.gerado_em).';

-- Recarrega o schema cache do PostgREST pra tabela aparecer na API na hora
NOTIFY pgrst, 'reload schema';

-- Verificação
SELECT count(*) AS analises_em_cache FROM public.insights_ia;
