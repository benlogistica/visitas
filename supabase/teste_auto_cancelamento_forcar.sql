-- ============================================================================
-- teste_auto_cancelamento_forcar.sql · teste rápido
-- ============================================================================
-- Cria 2 agendamentos vencidos há mais de 72h (FORA da janela do modal) e
-- executa manualmente a função do cron pra forçar o auto-cancelamento.
-- Eles vão aparecer na tab "Auto-cancelamentos" do /admin/auto-fechamentos.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) Cria os agendamentos vencidos
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_user_id   uuid;
  v_inst_ids  uuid[];
BEGIN
  -- Pega o user pelo email
  SELECT id INTO v_user_id
    FROM usuarios
   WHERE email = 'eduaoe@gmail.com'           -- ← ajustar se precisar
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não encontrado pro email informado.';
  END IF;

  -- Pega 2 instituições ativas aleatórias
  SELECT array_agg(id) INTO v_inst_ids
    FROM (SELECT id FROM instituicoes WHERE ativo = true ORDER BY random() LIMIT 2) sub;

  IF v_inst_ids IS NULL OR array_length(v_inst_ids, 1) < 1 THEN
    RAISE EXCEPTION 'Nenhuma instituição ativa encontrada.';
  END IF;

  -- Cenário A: 5 dias atrás (vai virar auto_72h)
  INSERT INTO visitas (
    nutricionista_id, instituicao_id, data_visita, horario_inicio,
    status, resumo,
    checkin_manual, flag_gps_divergente, flag_horario_fora_margem,
    flag_sem_checkin, flag_sem_checkout
  ) VALUES (
    v_user_id,
    v_inst_ids[1],
    (NOW() - interval '5 days')::date,
    '10:00:00',
    'agendada',
    'TESTE auto-cancel — 5 dias atrás (fora da janela 72h)',
    false, false, false, false, false
  );

  -- Cenário B: 4 dias atrás
  IF array_length(v_inst_ids, 1) >= 2 THEN
    INSERT INTO visitas (
      nutricionista_id, instituicao_id, data_visita, horario_inicio,
      status, resumo,
      checkin_manual, flag_gps_divergente, flag_horario_fora_margem,
      flag_sem_checkin, flag_sem_checkout
    ) VALUES (
      v_user_id,
      v_inst_ids[2],
      (NOW() - interval '4 days')::date,
      '14:00:00',
      'agendada',
      'TESTE auto-cancel — 4 dias atrás (fora da janela 72h)',
      false, false, false, false, false
    );
  END IF;

  RAISE NOTICE '✅ Agendamentos vencidos criados pro user_id = %', v_user_id;
END $$;

-- ---------------------------------------------------------------------------
-- 2) Confere quem está elegível pro auto-cancelamento (preview)
-- ---------------------------------------------------------------------------
SELECT
  v.id,
  i.nome AS instituicao,
  v.data_visita,
  v.horario_inicio,
  ((v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp
   + interval '72 hours') AS vencimento_72h,
  ROUND(EXTRACT(EPOCH FROM (NOW() - ((v.data_visita::text || ' ' || COALESCE(v.horario_inicio::text, '23:59'))::timestamp + interval '72 hours'))) / 3600, 1) AS horas_apos_vencimento,
  v.resumo
  FROM visitas v
  JOIN instituicoes i ON i.id = v.instituicao_id
  JOIN usuarios u ON u.id = v.nutricionista_id
 WHERE u.email = 'eduaoe@gmail.com'
   AND v.status = 'agendada'
   AND v.resumo LIKE 'TESTE auto-cancel%'
 ORDER BY v.data_visita;

-- ---------------------------------------------------------------------------
-- 3) FORÇA execução do auto-cancelamento (sem esperar o cron de hora em hora)
-- ---------------------------------------------------------------------------
SELECT * FROM auto_cancelar_agendamentos_72h();

-- ---------------------------------------------------------------------------
-- 4) Confere que viraram cancelada com origem 'auto_72h'
-- ---------------------------------------------------------------------------
SELECT
  v.id,
  i.nome AS instituicao,
  v.data_visita,
  v.horario_inicio,
  v.status,
  v.cancelamento_origem,
  v.cancelamento_motivo,
  v.cancelado_em,
  v.cancelado_por
  FROM visitas v
  JOIN instituicoes i ON i.id = v.instituicao_id
  JOIN usuarios u ON u.id = v.nutricionista_id
 WHERE u.email = 'eduaoe@gmail.com'
   AND v.resumo LIKE 'TESTE auto-cancel%'
 ORDER BY v.data_visita;

-- ============================================================================
-- COMO TESTAR NA TELA
-- ============================================================================
-- Depois de rodar tudo:
-- 1. Loga como admin no app
-- 2. Vai em /admin/auto-fechamentos
-- 3. Clica na tab "Auto-cancelamentos" — vai mostrar 2 (ou +) com pill vermelha "Auto"
-- 4. Verifica:
--    - 4 KPIs no topo
--    - Ranking "Quem mais deixou expirar" — você aparece com 2 cancelamentos
--    - Lista detalhada com motivo "Auto: sem ação em 72h após o horário"
--    - cancelado_por = NULL (sistema)

-- ============================================================================
-- LIMPEZA (depois do teste)
-- ============================================================================
-- DELETE FROM visitas
--  WHERE nutricionista_id = (SELECT id FROM usuarios WHERE email = 'eduaoe@gmail.com')
--    AND resumo LIKE 'TESTE auto-cancel%';
