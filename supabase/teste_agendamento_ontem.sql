-- ============================================================================
-- teste_agendamento_ontem.sql · teste rápido
-- ============================================================================
-- Cria 1 agendamento com data de ontem na agenda do user.
-- Quando você abrir a página inicial (ou recarregar), o modal "O que aconteceu?"
-- abre automaticamente em ~600ms com esse agendamento listado.
-- ============================================================================

INSERT INTO visitas (
  nutricionista_id,
  instituicao_id,
  data_visita,
  horario_inicio,
  status,
  resumo,
  checkin_manual,
  flag_gps_divergente,
  flag_horario_fora_margem,
  flag_sem_checkin,
  flag_sem_checkout
)
SELECT
  u.id,
  (SELECT id FROM instituicoes WHERE ativo = true ORDER BY random() LIMIT 1),
  CURRENT_DATE - 1,                                    -- ontem
  '10:00:00',                                          -- às 10:00
  'agendada',
  'TESTE — agendamento de ontem (modal 72h)',
  false, false, false, false, false
  FROM usuarios u
 WHERE u.email = 'eduaoe@gmail.com'                    -- ajustar se precisar
 LIMIT 1;

-- Verificação: retorna o agendamento criado
SELECT
  v.id,
  i.nome AS instituicao,
  v.data_visita,
  v.horario_inicio,
  v.status
  FROM visitas v
  JOIN instituicoes i ON i.id = v.instituicao_id
  JOIN usuarios   u ON u.id = v.nutricionista_id
 WHERE u.email = 'eduaoe@gmail.com'
   AND v.resumo = 'TESTE — agendamento de ontem (modal 72h)'
 ORDER BY v.id DESC
 LIMIT 1;

-- ============================================================================
-- LIMPEZA (depois do teste)
-- ============================================================================
-- DELETE FROM visitas
--  WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'eduaoe@gmail.com')
--    AND resumo = 'TESTE — agendamento de ontem (modal 72h)';
