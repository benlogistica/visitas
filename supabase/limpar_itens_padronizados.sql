-- ============================================================================
-- limpar_itens_padronizados.sql · LIMPEZA DE TODOS OS ITENS PADRONIZADOS
-- ============================================================================
-- ⚠⚠⚠  AÇÃO DESTRUTIVA — leia tudo antes de rodar  ⚠⚠⚠
--
-- Esse script remove TODOS os itens padronizados do sistema, incluindo:
--   - itens_padronizados (nossos, concorrentes, em negociação, convertidos)
--   - itens_padronizados_log (histórico de mudanças)
--
-- NÃO mexe em:
--   - usuarios, instituicoes, profissionais
--   - visitas, agendamentos
--   - frases, configurações, etc.
--
-- ============================================================================
-- RECOMENDADO: rodar dentro de um BEGIN/COMMIT pra poder fazer ROLLBACK
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PREVIEW — quantos registros serão removidos
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM itens_padronizados)       AS total_itens,
  (SELECT COUNT(*) FROM itens_padronizados WHERE status = 'nosso')          AS nossos,
  (SELECT COUNT(*) FROM itens_padronizados WHERE status = 'em_negociacao')  AS em_negociacao,
  (SELECT COUNT(*) FROM itens_padronizados WHERE status = 'convertido')     AS convertidos,
  (SELECT COUNT(*) FROM itens_padronizados WHERE status = 'concorrente')    AS concorrentes,
  (SELECT COUNT(*) FROM itens_padronizados_log)   AS total_logs;

-- ============================================================================
-- 2. EXECUTAR A LIMPEZA — em transação pra poder reverter
-- ============================================================================

BEGIN;

-- Filhos primeiro (FK)
DELETE FROM itens_padronizados_log;
DELETE FROM itens_padronizados;

-- Verificação dentro da transação
SELECT
  (SELECT COUNT(*) FROM itens_padronizados)      AS itens_apos,
  (SELECT COUNT(*) FROM itens_padronizados_log)  AS logs_apos;

-- ⚠ DECIDA AGORA:
--   Se os 2 contadores acima são ZERO e está tudo OK, rode:
COMMIT;
--
--   Se algo deu errado e você quer DESFAZER tudo, rode:
-- ROLLBACK;

-- ============================================================================
-- 3. Verificação pós-commit (rodar separado depois)
-- ============================================================================
-- SELECT
--   'itens_padronizados: ' || COUNT(*) FROM itens_padronizados
-- UNION ALL SELECT 'itens_padronizados_log: ' || COUNT(*) FROM itens_padronizados_log;
