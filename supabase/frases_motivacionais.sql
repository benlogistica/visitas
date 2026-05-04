-- =============================================================================
-- frases_motivacionais.sql   |   sprint 9.32.233
-- =============================================================================
-- Garante o schema da tabela `frases_motivacionais`, RLS, e popula com as 25
-- frases default se a tabela estiver vazia. Idempotente — pode rodar múltiplas
-- vezes sem efeitos colaterais.
--
-- COMO RODAR:
--   1. Painel Supabase → SQL Editor → New query
--   2. Cola o conteúdo INTEIRO deste arquivo
--   3. Clique em RUN
-- =============================================================================

-- ===== 1. TABELA =====
CREATE TABLE IF NOT EXISTS public.frases_motivacionais (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  texto       text NOT NULL,
  autor       text,
  ativa       boolean NOT NULL DEFAULT true,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  criado_por  uuid REFERENCES public.usuarios(id) ON DELETE SET NULL
);

-- Garante que colunas necessárias existem (se a tabela já foi criada num esquema antigo)
ALTER TABLE public.frases_motivacionais
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid();
ALTER TABLE public.frases_motivacionais
  ADD COLUMN IF NOT EXISTS ativa boolean NOT NULL DEFAULT true;
ALTER TABLE public.frases_motivacionais
  ADD COLUMN IF NOT EXISTS criado_em timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.frases_motivacionais
  ADD COLUMN IF NOT EXISTS criado_por uuid;

CREATE INDEX IF NOT EXISTS frases_motivacionais_ativa_idx
  ON public.frases_motivacionais(ativa);


-- ===== 2. RLS (abertas — projeto usa auth custom, mesma estratégia de visita_anexos) =====
ALTER TABLE public.frases_motivacionais ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "open_select_frases_motivacionais" ON public.frases_motivacionais;
CREATE POLICY "open_select_frases_motivacionais"
  ON public.frases_motivacionais FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "open_insert_frases_motivacionais" ON public.frases_motivacionais;
CREATE POLICY "open_insert_frases_motivacionais"
  ON public.frases_motivacionais FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "open_update_frases_motivacionais" ON public.frases_motivacionais;
CREATE POLICY "open_update_frases_motivacionais"
  ON public.frases_motivacionais FOR UPDATE
  TO anon, authenticated
  USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "open_delete_frases_motivacionais" ON public.frases_motivacionais;
CREATE POLICY "open_delete_frases_motivacionais"
  ON public.frases_motivacionais FOR DELETE
  TO anon, authenticated
  USING (true);


-- ===== 3. SEED — popula com as 25 frases default se a tabela estiver vazia =====
INSERT INTO public.frases_motivacionais (texto, autor)
SELECT v.texto, v.autor
FROM (VALUES
  ('Grandes conquistas começam com pequenas atitudes diárias.', NULL),
  ('O sucesso é a soma de pequenos esforços repetidos dia após dia.', 'Robert Collier'),
  ('Acredite em você e na sua capacidade de transformar o dia.', NULL),
  ('A jornada de mil milhas começa com um único passo.', 'Lao Tsé'),
  ('Foco, disciplina e gratidão constroem dias extraordinários.', NULL),
  ('Cada manhã é uma nova página em branco — escreva algo bom.', NULL),
  ('Você é mais forte do que imagina. Confie no processo.', NULL),
  ('Pequenos progressos ainda são progressos. Continue avançando.', NULL),
  ('A gratidão transforma o que temos em suficiente.', NULL),
  ('Não espere o momento perfeito. Torne o momento perfeito.', NULL),
  ('Acredite no poder de começar de novo, quantas vezes forem necessárias.', NULL),
  ('A diferença entre o possível e o impossível está na sua determinação.', 'Tommy Lasorda'),
  ('Persista. A cada dia você fica mais perto do que deseja.', NULL),
  ('A disciplina é a ponte entre os sonhos e a realização.', 'Jim Rohn'),
  ('Respire fundo, levante a cabeça e siga em frente. Você consegue.', NULL),
  ('Seja a energia que você quer atrair.', NULL),
  ('Não conte os dias — faça os dias contarem.', 'Muhammad Ali'),
  ('Sorria. Isso já é metade do caminho.', NULL),
  ('Seu único limite é você mesmo.', NULL),
  ('Coragem não é ausência de medo — é agir apesar dele.', NULL),
  ('A consistência é mais importante que a perfeição.', NULL),
  ('Cada passo conta. Mesmo os pequenos.', NULL),
  ('Você não precisa ser perfeito. Precisa ser presente.', NULL),
  ('Celebre suas pequenas vitórias. Elas pavimentam o caminho das grandes.', NULL),
  ('Enquanto você respira, há tempo pra recomeçar.', NULL)
) AS v(texto, autor)
WHERE NOT EXISTS (SELECT 1 FROM public.frases_motivacionais LIMIT 1);


-- ===== VERIFICAÇÃO =====
-- SELECT count(*) total, count(*) FILTER (WHERE ativa) ativas FROM public.frases_motivacionais;
