-- ============================================================================
-- teste_modal_72h_seed.sql · Sprint 9.32.342 (testes)
-- ============================================================================
-- Cria 3 agendamentos vencidos pra testar o modal "O que aconteceu?".
-- Cada um vai aparecer com uma cor de urgência diferente:
--   1) vence em ~3h   → pill VERMELHO  (item ativo no modal)
--   2) vence em ~24h  → pill ÂMBAR     (item recolhido)
--   3) vence em ~48h  → pill VERDE     (item recolhido)
--
-- ⚠ Ajuste o email abaixo se precisar testar com outro usuário.
-- ============================================================================

DO $$
DECLARE
  v_user_id   uuid;
  v_inst_ids  uuid[];
BEGIN
  -- 1) Pega o user pelo email
  SELECT id INTO v_user_id
    FROM usuarios
   WHERE email = 'eduaoe@gmail.com'   -- ← AJUSTAR SE PRECISAR
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não encontrado pro email informado.';
  END IF;

  -- 2) Pega até 3 instituições ativas (aleatórias)
  SELECT array_agg(id) INTO v_inst_ids
    FROM (SELECT id FROM instituicoes WHERE ativo = true ORDER BY random() LIMIT 3) sub;

  IF v_inst_ids IS NULL OR array_length(v_inst_ids, 1) < 1 THEN
    RAISE EXCEPTION 'Nenhuma instituição ativa encontrada.';
  END IF;

  -- ---------------------------------------------------------------------------
  -- Cenário 1: agendamento de 69h atrás (vence em ~3h) — pill VERMELHO
  -- ---------------------------------------------------------------------------
  INSERT INTO visitas (
    nutricionista_id, instituicao_id, data_visita, horario_inicio,
    status, resumo,
    checkin_manual, flag_gps_divergente, flag_horario_fora_margem,
    flag_sem_checkin, flag_sem_checkout
  ) VALUES (
    v_user_id,
    v_inst_ids[1],
    (NOW() - interval '69 hours')::date,
    (NOW() - interval '69 hours')::time,
    'agendada',
    'TESTE 72h — vence em ~3h (pill vermelho)',
    false, false, false, false, false
  );

  -- ---------------------------------------------------------------------------
  -- Cenário 2: agendamento de 48h atrás (vence em ~24h) — pill ÂMBAR
  -- ---------------------------------------------------------------------------
  IF array_length(v_inst_ids, 1) >= 2 THEN
    INSERT INTO visitas (
      nutricionista_id, instituicao_id, data_visita, horario_inicio,
      status, resumo,
      checkin_manual, flag_gps_divergente, flag_horario_fora_margem,
      flag_sem_checkin, flag_sem_checkout
    ) VALUES (
      v_user_id,
      v_inst_ids[2],
      (NOW() - interval '48 hours')::date,
      (NOW() - interval '48 hours')::time,
      'agendada',
      'TESTE 72h — vence em ~24h (pill âmbar)',
      false, false, false, false, false
    );
  END IF;

  -- ---------------------------------------------------------------------------
  -- Cenário 3: agendamento de 24h atrás (vence em ~48h) — pill VERDE
  -- ---------------------------------------------------------------------------
  IF array_length(v_inst_ids, 1) >= 3 THEN
    INSERT INTO visitas (
      nutricionista_id, instituicao_id, data_visita, horario_inicio,
      status, resumo,
      checkin_manual, flag_gps_divergente, flag_horario_fora_margem,
      flag_sem_checkin, flag_sem_checkout
    ) VALUES (
      v_user_id,
      v_inst_ids[3],
      (NOW() - interval '24 hours')::date,
      (NOW() - interval '24 hours')::time,
      'agendada',
      'TESTE 72h — vence em ~48h (pill verde)',
      false, false, false, false, false
    );
  END IF;

  RAISE NOTICE '✅ Agendamentos de teste criados para user_id = %', v_user_id;
END $$;

-- ============================================================================
-- VERIFICAÇÃO — lista os 3 agendamentos de teste recém-criados
-- ============================================================================
SELECT
  v.id,
  i.nome AS instituicao,
  v.data_visita,
  v.horario_inicio,
  ((v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp
   + interval '72 hours') AS vencimento_72h,
  ROUND(EXTRACT(EPOCH FROM (((v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp + interval '72 hours') - NOW())) / 3600, 1) AS resta_horas,
  v.resumo
  FROM visitas v
  JOIN instituicoes i ON i.id = v.instituicao_id
  JOIN usuarios u ON u.id = v.nutricionista_id
 WHERE u.email = 'eduaoe@gmail.com'
   AND v.status = 'agendada'
   AND v.resumo LIKE 'TESTE 72h%'
 ORDER BY v.data_visita, v.horario_inicio;

-- ============================================================================
-- COMO TESTAR
-- ============================================================================
-- 1. Rode o script acima.
-- 2. Abra o app e faça login (ou recarregue a página se já estava logado).
-- 3. Após ~600ms o modal "Você tem N agendamentos pendentes" deve abrir.
-- 4. Teste cada uma das 4 ações:
--    - "Fui, esqueci o check-in" → vai virar visita realizada com chip âmbar "tardio"
--    - "Não fui"                  → vai virar não realizada
--    - "Vou reagendar"            → abre form com data/hora pré-preenchidas
--    - "Cancelar essa visita"     → vira cancelada manual (pill cinza "Manual")
-- 5. Vá em Minhas Visitas → aba Canceladas → veja sub-tabs Manual/Auto/Todas.
-- 6. Vá em Indicadores → veja o card "Auto-cancelamentos (72h)" + gráfico de barras.

-- ============================================================================
-- LIMPEZA — rodar depois do teste pra remover os agendamentos
-- ============================================================================
-- DELETE FROM visitas
--  WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'eduaoe@gmail.com')
--    AND resumo LIKE 'TESTE 72h%';
