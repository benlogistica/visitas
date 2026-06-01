-- ============================================================================
-- limpar_visitas_eduardo_marques.sql · LIMPEZA DAS VISITAS DO EDUARDO MARQUES
-- ============================================================================
-- ⚠ AÇÃO DESTRUTIVA — leia antes de rodar
--
-- Remove TODAS as visitas pertencentes ao Eduardo Marques (Farmacêutico,
-- email edustsbr@gmail.com, CPF 123.456.789-00).
--
-- NÃO confunde com o admin Eduardo Marques (eduaoe@gmail.com) — o filtro
-- usa o email correto e o usuário do admin permanece intocado.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Confirma o ID (deve retornar 1 linha)
-- ----------------------------------------------------------------------------
SELECT id, nome, cpf, email FROM usuarios WHERE email = 'edustsbr@gmail.com';

-- ----------------------------------------------------------------------------
-- 2. PREVIEW
-- ----------------------------------------------------------------------------
WITH alvo AS (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com' LIMIT 1)
SELECT
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo))                              AS total_visitas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo) AND v.status = 'agendada')    AS agendamentos,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo) AND v.status = 'completa')    AS completas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo) AND v.status = 'cancelada')   AS canceladas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo) AND v.status = 'rascunho')    AS rascunhos,
  (SELECT COUNT(*) FROM visitas_objetivos     vo WHERE vo.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS vinculos_objetivos,
  (SELECT COUNT(*) FROM visitas_profissionais vp WHERE vp.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS vinculos_profissionais,
  (SELECT COUNT(*) FROM visita_anexos         va WHERE va.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS anexos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura sr WHERE sr.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS solicit_reabertura;

-- ============================================================================
-- 3. EXECUTAR — em transação
-- ============================================================================
BEGIN;

DELETE FROM solicitacoes_reabertura
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com'));

DELETE FROM visita_anexos
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com'));

DELETE FROM visitas_objetivos
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com'));

DELETE FROM visitas_profissionais
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com'));

DELETE FROM visitas
 WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com');

-- Verificação
WITH alvo AS (SELECT id FROM usuarios WHERE email = 'edustsbr@gmail.com' LIMIT 1)
SELECT
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM alvo)) AS visitas_apos,
  (SELECT COUNT(*) FROM visitas_objetivos     vo WHERE vo.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS objetivos_apos,
  (SELECT COUNT(*) FROM visitas_profissionais vp WHERE vp.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS profs_apos,
  (SELECT COUNT(*) FROM visita_anexos         va WHERE va.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS anexos_apos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura sr WHERE sr.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM alvo))) AS solicit_apos;

-- Tudo zero? COMMIT;
-- Algo errado? troca por: ROLLBACK;
COMMIT;
