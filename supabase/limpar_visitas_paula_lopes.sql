-- ============================================================================
-- limpar_visitas_paula_lopes.sql · LIMPEZA DAS VISITAS DA PAULA LOPES
-- ============================================================================
-- ⚠ AÇÃO DESTRUTIVA — leia antes de rodar
--
-- Remove TODAS as visitas (em qualquer status: agendada, completa, cancelada...)
-- pertencentes à Paula Lopes (email medina.pa@gmail.com).
--
-- NÃO mexe em:
--   - Usuário Paula Lopes (continua cadastrado)
--   - Visitas de outros nutris
--   - Instituições, profissionais, etc.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Confirma o ID da Paula (deve retornar exatamente 1 linha)
-- ----------------------------------------------------------------------------
SELECT id, nome, email FROM usuarios WHERE email = 'medina.pa@gmail.com';

-- ----------------------------------------------------------------------------
-- 2. PREVIEW — quantos registros serão removidos
-- ----------------------------------------------------------------------------
WITH paula AS (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com' LIMIT 1)
SELECT
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula))                              AS total_visitas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula) AND v.status = 'agendada')    AS agendamentos,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula) AND v.status = 'completa')    AS completas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula) AND v.status = 'cancelada')   AS canceladas,
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula) AND v.status = 'rascunho')    AS rascunhos,
  (SELECT COUNT(*) FROM visitas_objetivos     vo WHERE vo.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS vinculos_objetivos,
  (SELECT COUNT(*) FROM visitas_profissionais vp WHERE vp.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS vinculos_profissionais,
  (SELECT COUNT(*) FROM visita_anexos         va WHERE va.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS anexos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura sr WHERE sr.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS solicit_reabertura;

-- ============================================================================
-- 3. EXECUTAR — em transação pra poder reverter
-- ============================================================================
BEGIN;

-- Ordem importa por causa de FK (filhos primeiro)
DELETE FROM solicitacoes_reabertura
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com'));

DELETE FROM visita_anexos
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com'));

DELETE FROM visitas_objetivos
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com'));

DELETE FROM visitas_profissionais
 WHERE visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com'));

DELETE FROM visitas
 WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com');

-- Verificação dentro da transação
WITH paula AS (SELECT id FROM usuarios WHERE email = 'medina.pa@gmail.com' LIMIT 1)
SELECT
  (SELECT COUNT(*) FROM visitas v WHERE v.nutricionista_id = (SELECT id FROM paula)) AS visitas_apos,
  (SELECT COUNT(*) FROM visitas_objetivos     vo WHERE vo.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS objetivos_apos,
  (SELECT COUNT(*) FROM visitas_profissionais vp WHERE vp.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS profs_apos,
  (SELECT COUNT(*) FROM visita_anexos         va WHERE va.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS anexos_apos,
  (SELECT COUNT(*) FROM solicitacoes_reabertura sr WHERE sr.visita_id IN (SELECT id FROM visitas WHERE nutricionista_id = (SELECT id FROM paula))) AS solicit_apos;

-- ⚠ DECIDA:
--   Se os 5 contadores acima são TODOS ZERO e está tudo OK, rode:
COMMIT;
--   Se algo deu errado, rode: ROLLBACK;
