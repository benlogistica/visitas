-- ============================================================================
-- reagendamentos_e_canceladas.sql · Sprint 9.32.331
-- ============================================================================
-- 1. Adiciona colunas de tracking de reagendamentos
-- 2. Filtros e índices novos pra performance nas listagens
-- ============================================================================

-- 1. Reagendamentos
ALTER TABLE visitas
  ADD COLUMN IF NOT EXISTS qtd_reagendamentos integer DEFAULT 0 NOT NULL,
  ADD COLUMN IF NOT EXISTS data_original date,
  ADD COLUMN IF NOT EXISTS ultimo_reagendamento_em timestamptz,
  ADD COLUMN IF NOT EXISTS motivos_reagendamento jsonb DEFAULT '[]'::jsonb NOT NULL;

COMMENT ON COLUMN visitas.qtd_reagendamentos IS
  'Sprint 9.32.331: quantas vezes a data dessa visita/agendamento foi alterada.';
COMMENT ON COLUMN visitas.data_original IS
  'Sprint 9.32.331: primeira data marcada (preservada após primeiro reagendamento).';
COMMENT ON COLUMN visitas.ultimo_reagendamento_em IS
  'Sprint 9.32.331: timestamp do último reagendamento (pra ordenar/filtrar).';
COMMENT ON COLUMN visitas.motivos_reagendamento IS
  'Sprint 9.32.331: array de objetos com histórico {de, para, em, por, motivo}.';

-- 2. Índices úteis
CREATE INDEX IF NOT EXISTS visitas_qtd_reagendamentos_idx
  ON visitas(qtd_reagendamentos)
  WHERE qtd_reagendamentos > 0;

-- 3. Permite status='cancelada' (verifica se ja existe enum check, etc)
-- Na nossa tabela 'status' e text livre, entao nao precisa mudar enum/constraint.

-- 4. Verificacao
SELECT column_name, data_type, column_default
  FROM information_schema.columns
 WHERE table_name = 'visitas'
   AND column_name IN ('qtd_reagendamentos', 'data_original', 'ultimo_reagendamento_em', 'motivos_reagendamento')
 ORDER BY column_name;
