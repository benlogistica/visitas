-- ============================================================================
-- debug_agenda_ana_paula.sql · diagnostico
-- ============================================================================
-- Investigar por que Ana Paula Moré não vê os próprios agendamentos.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Quantos usuários existem com "ana paula" no nome ou email?
--    (descobrir se tem cadastro duplicado)
-- ----------------------------------------------------------------------------
SELECT id, nome, email, cpf, perfil, status, criado_em, ultimo_login
  FROM usuarios
 WHERE LOWER(nome) LIKE '%ana paula%mor%'
    OR LOWER(email) LIKE '%anapaula%'
    OR LOWER(email) LIKE '%ana.paula%'
 ORDER BY criado_em;

-- ----------------------------------------------------------------------------
-- 2. Todos os agendamentos atribuídos pra qualquer Ana Paula
-- ----------------------------------------------------------------------------
SELECT
  v.id,
  u.nome           AS nutricionista,
  u.email          AS email_nutri,
  v.nutricionista_id,
  i.nome           AS instituicao,
  v.data_visita,
  v.horario_inicio,
  v.status,
  v.atribuido_por,
  ua.nome          AS quem_atribuiu,
  v.criado_em
  FROM visitas v
  JOIN usuarios u ON u.id = v.nutricionista_id
  LEFT JOIN usuarios ua ON ua.id = v.atribuido_por
  JOIN instituicoes i ON i.id = v.instituicao_id
 WHERE LOWER(u.nome) LIKE '%ana paula%mor%'
   AND v.status IN ('agendada', 'sugerida', 'rascunho', 'cancelada')
 ORDER BY v.criado_em DESC
 LIMIT 30;

-- ----------------------------------------------------------------------------
-- 3. Quebra por status (pra ver se algum ficou 'sugerida' aguardando aceite)
-- ----------------------------------------------------------------------------
SELECT v.status, COUNT(*) AS qtd
  FROM visitas v
  JOIN usuarios u ON u.id = v.nutricionista_id
 WHERE LOWER(u.nome) LIKE '%ana paula%mor%'
 GROUP BY v.status
 ORDER BY qtd DESC;

-- ----------------------------------------------------------------------------
-- 4. RLS está habilitada na tabela visitas?
-- ----------------------------------------------------------------------------
SELECT schemaname, tablename, rowsecurity
  FROM pg_tables
 WHERE schemaname = 'public'
   AND tablename = 'visitas';

-- ----------------------------------------------------------------------------
-- 5. Quais policies existem na tabela visitas?
-- ----------------------------------------------------------------------------
SELECT policyname, cmd, qual, with_check
  FROM pg_policies
 WHERE schemaname = 'public'
   AND tablename = 'visitas';
