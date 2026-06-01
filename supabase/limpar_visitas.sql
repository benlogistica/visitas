-- ============================================================================
-- limpar_visitas.sql · LIMPEZA DE TODAS AS VISITAS
-- ============================================================================
-- ⚠⚠⚠  AÇÃO DESTRUTIVA — leia tudo antes de rodar  ⚠⚠⚠
--
-- Esse script remove TODAS as visitas do sistema, incluindo:
--   - Agendamentos (status='agendada', 'sugerida')
--   - Rascunhos (status='rascunho')
--   - Visitas completas, em revisão, canceladas, etc.
--   - Todos os anexos das visitas
--   - Todos os vínculos com objetivos e profissionais
--   - Todas as solicitações de reabertura
--
-- NÃO mexe em:
--   - usuarios (nutricionistas, admins)
--   - instituicoes (hospitais)
--   - profissionais (médicos, etc.)
--   - objetivos_visita
--   - frases motivacionais, configurações, etc.
--
-- ============================================================================
-- RECOMENDADO: rodar dentro de um BEGIN/COMMIT pra poder fazer ROLLBACK
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. PREVIEW — quantos registros serão removidos
-- ----------------------------------------------------------------------------
SELECT
  (SELECT COUNT(*) FROM visitas)                          AS total_visitas,
  (SELECT COUNT(*) FROM visitas WHERE status = 'agendada')      AS agendamentos,
  (SELECT COUNT(*) FROM visitas WHERE status = 'sugerida')      AS sugeridas,
  (SELECT COUNT(*) FROM visitas WHERE status = 'rascunho')      AS rascunhos,
  (SELECT COUNT(*) FROM visitas WHERE status = 'completa')      AS completas,
  (SELECT COUNT(*) FROM visitas WHERE status = 'aprovada_pos_revisao') AS aprovadas,
  (SELECT COUNT(*) FROM visitas WHERE status = 'cancelada')     AS canceladas,
  (SELECT COUNT(*) FROM visitas_objetivos)                AS vinculos_objetivos,
  (SELECT COUNT(*) FROM visitas_profissionais)            AS vinculos_profissionais,
  (SELECT COUNT(*) FROM visita_anexos)                    AS anexos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura)          AS solicitacoes_reabertura;

-- ============================================================================
-- 2. EXECUTAR A LIMPEZA — em transação pra poder reverter
-- ============================================================================

BEGIN;

-- Ordem importa por causa de FK constraints (filhos primeiro)
DELETE FROM solicitacoes_reabertura;
DELETE FROM visita_anexos;
DELETE FROM visitas_objetivos;
DELETE FROM visitas_profissionais;
DELETE FROM visitas;

-- Verificação dentro da transação
SELECT
  (SELECT COUNT(*) FROM visitas)                  AS visitas_apos,
  (SELECT COUNT(*) FROM visitas_objetivos)        AS objetivos_apos,
  (SELECT COUNT(*) FROM visitas_profissionais)    AS profs_apos,
  (SELECT COUNT(*) FROM visita_anexos)            AS anexos_apos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura)  AS solicit_apos;

-- ⚠ DECIDA AGORA:
--   Se os 5 contadores acima são TODOS ZERO e está tudo OK, rode:
COMMIT;
--
--   Se algo deu errado e você quer DESFAZER tudo, rode:
-- ROLLBACK;

-- ============================================================================
-- 3. Verificação pós-commit (rodar separado depois)
-- ============================================================================
-- SELECT
--   'visitas: ' || COUNT(*) FROM visitas
-- UNION ALL SELECT 'visitas_objetivos: ' || COUNT(*) FROM visitas_objetivos
-- UNION ALL SELECT 'visitas_profissionais: ' || COUNT(*) FROM visitas_profissionais
-- UNION ALL SELECT 'visita_anexos: ' || COUNT(*) FROM visita_anexos
-- UNION ALL SELECT 'solicitacoes_reabertura: ' || COUNT(*) FROM solicitacoes_reabertura;
