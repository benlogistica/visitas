-- ============================================================
-- Fix Sprint 9.32.348: empresa_representada aceita multipla selecao
--
-- Bug: ao selecionar 2+ empresas (ex.: "Nutricionais-Santos, Nutricionais-PG"),
-- a constraint CHECK antiga rejeita pq so aceitava 1 valor especifico.
--
-- Fix: dropa a constraint antiga e cria uma nova que valida CSV
-- (cada item separado por virgula tem que estar na lista permitida).
-- ============================================================

BEGIN;

-- 1) Dropa a constraint atual (qualquer que seja o formato dela)
ALTER TABLE visitas DROP CONSTRAINT IF EXISTS visitas_empresa_representada_check;

-- 2) Recria usando regex (Postgres nao permite subquery em CHECK)
--    Padrao: um valor da lista, opcionalmente seguido de ", outro_valor", N vezes
--    Lista permitida: Haverim | Nutricionais-Santos | Nutricionais-PG
--    Aceita virgula com ou sem espaco depois (",foo" ou ", foo")
--    Aceita NULL e string vazia
ALTER TABLE visitas
  ADD CONSTRAINT visitas_empresa_representada_check
  CHECK (
    empresa_representada IS NULL
    OR empresa_representada = ''
    OR empresa_representada ~ '^(Haverim|Nutricionais-Santos|Nutricionais-PG)(,\s*(Haverim|Nutricionais-Santos|Nutricionais-PG))*$'
  );

COMMIT;

-- ============================================================
-- VERIFICACAO
-- ============================================================
-- Lista a nova definicao da constraint
SELECT conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'visitas'::regclass
  AND conname = 'visitas_empresa_representada_check';

-- Testa o regex direto (deve retornar TRUE pros validos e FALSE pros invalidos)
WITH casos(rotulo, valor) AS (VALUES
  ('t1_haverim',             'Haverim'),
  ('t2_santos',              'Nutricionais-Santos'),
  ('t3_pg',                  'Nutricionais-PG'),
  ('t4_dois_a',              'Haverim, Nutricionais-PG'),
  ('t5_dois_b',              'Nutricionais-Santos, Nutricionais-PG'),
  ('t6_tres',                'Haverim, Nutricionais-Santos, Nutricionais-PG'),
  ('t7_sem_espaco',          'Haverim,Nutricionais-PG'),
  ('t8_invalido_outra',      'Outro'),                           -- deve dar FALSE
  ('t9_invalido_meio',       'Haverim, FakeEmpresa'),            -- deve dar FALSE
  ('t10_vazio',              ''),                                -- deve passar pq esta na clausula OR
  ('t11_null',               NULL)
)
SELECT
  rotulo,
  valor,
  (valor IS NULL
    OR valor = ''
    OR valor ~ '^(Haverim|Nutricionais-Santos|Nutricionais-PG)(,\s*(Haverim|Nutricionais-Santos|Nutricionais-PG))*$'
  ) AS aceita
FROM casos;
