-- =============================================================================
-- RESET PARA PRODUÇÃO — B&N Logística   |   sprint 9.32.251
-- =============================================================================
-- Apaga TODOS os dados operacionais (visitas, instituições, usuários, anexos,
-- notificações, etc), mantendo apenas o ADMIN MASTER e as configurações do sistema
-- (frases motivacionais, categorias profissionais, configurações_sistema).
--
-- ⚠️ ATENÇÃO ⚠️
--   Esse script é DESTRUTIVO. Antes de rodar:
--     1. Tenha backup do banco (Supabase → Settings → Database → Backups
--        ou faça dump manual pelo painel)
--     2. Verifique o email do admin master abaixo (linha ~34)
--     3. Rode bloco por bloco (não selecione tudo de uma vez)
--     4. Verifique o resultado de cada bloco antes de prosseguir
--
-- COMO RODAR:
--   Painel Supabase → SQL Editor → New query → cola um BLOCO por vez → Run
--   Cada bloco está delimitado por "===== BLOCO N: ... =====".
-- =============================================================================


-- ===== ANTES DE TUDO: confirmar email do admin que vai sobreviver =====
-- Roda isso primeiro pra confirmar que o admin existe:
SELECT id, nome, email, perfil, super_admin, status
  FROM public.usuarios
 WHERE email = 'eduaoe@gmail.com';
-- Se o resultado tiver 0 linhas, PARE e ajuste o email no SQL antes de seguir.


-- =============================================================================
-- ===== BLOCO 1: BACKUP DE EMERGÊNCIA (snapshot em tabelas _bkp_resetXXX) =====
-- =============================================================================
-- Cria cópias snapshot. Se algo der errado, você consegue voltar com INSERTs.
-- As tabelas _bkp_reset20260503 podem ser dropadas depois (1-2 semanas) quando
-- tudo estiver OK em produção.
--
-- Substitua "20260503" pela data de HOJE no formato AAAAMMDD se quiser.

CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_visitas               AS SELECT * FROM public.visitas;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_visitas_objetivos    AS SELECT * FROM public.visitas_objetivos;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_visitas_profissionais AS SELECT * FROM public.visitas_profissionais;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_visita_anexos        AS SELECT * FROM public.visita_anexos;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_solicitacoes_reabertura AS SELECT * FROM public.solicitacoes_reabertura;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_notificacoes         AS SELECT * FROM public.notificacoes;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_profissionais        AS SELECT * FROM public.profissionais;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_instituicoes         AS SELECT * FROM public.instituicoes;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_itens_padronizados   AS SELECT * FROM public.itens_padronizados;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_itens_padronizados_log AS SELECT * FROM public.itens_padronizados_log;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_usuarios             AS SELECT * FROM public.usuarios;
CREATE TABLE IF NOT EXISTS public._bkp_reset20260503_objetivos_visita     AS SELECT * FROM public.objetivos_visita;

-- Verificação: contagem dos backups
SELECT 'visitas' tabela, count(*) FROM public._bkp_reset20260503_visitas UNION ALL
SELECT 'visitas_objetivos', count(*) FROM public._bkp_reset20260503_visitas_objetivos UNION ALL
SELECT 'visitas_profissionais', count(*) FROM public._bkp_reset20260503_visitas_profissionais UNION ALL
SELECT 'visita_anexos', count(*) FROM public._bkp_reset20260503_visita_anexos UNION ALL
SELECT 'solicitacoes_reabertura', count(*) FROM public._bkp_reset20260503_solicitacoes_reabertura UNION ALL
SELECT 'notificacoes', count(*) FROM public._bkp_reset20260503_notificacoes UNION ALL
SELECT 'profissionais', count(*) FROM public._bkp_reset20260503_profissionais UNION ALL
SELECT 'instituicoes', count(*) FROM public._bkp_reset20260503_instituicoes UNION ALL
SELECT 'itens_padronizados', count(*) FROM public._bkp_reset20260503_itens_padronizados UNION ALL
SELECT 'itens_padronizados_log', count(*) FROM public._bkp_reset20260503_itens_padronizados_log UNION ALL
SELECT 'usuarios', count(*) FROM public._bkp_reset20260503_usuarios UNION ALL
SELECT 'objetivos_visita', count(*) FROM public._bkp_reset20260503_objetivos_visita;


-- =============================================================================
-- ===== BLOCO 2: DELETE OPERACIONAL — visitas e tudo que depende delas =====
-- =============================================================================
-- Roda como transação: se der erro em qualquer linha, dá ROLLBACK manual.
-- ORDEM importa por causa de FKs (filhas primeiro, pais depois).

BEGIN;

-- 2.1 — Anexos das visitas (linhas no banco; arquivos no Storage vão no BLOCO 4)
DELETE FROM public.visita_anexos;

-- 2.2 — Tabelas de junção (objetivos e profissionais por visita)
DELETE FROM public.visitas_objetivos;
DELETE FROM public.visitas_profissionais;

-- 2.3 — Solicitações de reabertura
DELETE FROM public.solicitacoes_reabertura;

-- 2.4 — Visitas (todas — agendamentos, sugestões, rascunhos, completas, aprovadas)
DELETE FROM public.visitas;

-- 2.5 — Notificações (zera tudo, ninguém vai querer ver notif de visitas que não existem)
DELETE FROM public.notificacoes;

-- 2.6 — Profissionais (médicos/contatos nas instituições)
DELETE FROM public.profissionais;

-- 2.7 — Itens padronizados (concorrentes mapeados) e log
DELETE FROM public.itens_padronizados_log;
DELETE FROM public.itens_padronizados;

-- 2.8 — Instituições (todos os hospitais)
DELETE FROM public.instituicoes;

-- 2.9 — Usuários (todos exceto o admin master)
--   Mantém EXCLUSIVAMENTE o email 'eduaoe@gmail.com'.
--   Qualquer outro admin / super_admin / nutricionista será apagado.
DELETE FROM public.usuarios
 WHERE email <> 'eduaoe@gmail.com';

-- Verificação dentro da transação — confere o que sobrou
SELECT 'visitas' tabela, count(*) FROM public.visitas UNION ALL
SELECT 'visita_anexos', count(*) FROM public.visita_anexos UNION ALL
SELECT 'visitas_objetivos', count(*) FROM public.visitas_objetivos UNION ALL
SELECT 'visitas_profissionais', count(*) FROM public.visitas_profissionais UNION ALL
SELECT 'solicitacoes_reabertura', count(*) FROM public.solicitacoes_reabertura UNION ALL
SELECT 'notificacoes', count(*) FROM public.notificacoes UNION ALL
SELECT 'profissionais', count(*) FROM public.profissionais UNION ALL
SELECT 'instituicoes', count(*) FROM public.instituicoes UNION ALL
SELECT 'itens_padronizados', count(*) FROM public.itens_padronizados UNION ALL
SELECT 'usuarios', count(*) FROM public.usuarios;

-- ⚠️ Se a verificação tá certa (zeros nas operacionais, 1 em usuarios), faça:
--    COMMIT;
-- Se algo deu errado:
--    ROLLBACK;

-- COMMIT;       <-- descomente e rode pra confirmar
-- ROLLBACK;     <-- descomente e rode pra desfazer


-- =============================================================================
-- ===== BLOCO 3 (OPCIONAL): RESETAR OBJETIVOS DE VISITA E CATEGORIAS =====
-- =============================================================================
-- Se quiser começar com a lista padrão, descomente:
--
-- DELETE FROM public.objetivos_visita;
-- DELETE FROM public.categorias_profissionais;
--
-- ATENÇÃO: depois você precisa popular essas tabelas com os valores que quer.
-- Por padrão recomendamos MANTER esses dados — são listas de configuração
-- razoavelmente estáveis (objetivos comuns: "Apresentação", "Follow-up", etc).


-- =============================================================================
-- ===== BLOCO 4: LIMPAR STORAGE (arquivos físicos dos anexos) =====
-- =============================================================================
-- O bucket "visita-anexos" no Storage do Supabase tem arquivos órfãos agora.
-- Apague-os pra liberar espaço.
--
-- Opção A (interface): Painel → Storage → bucket "visita-anexos" → seleciona
--                      tudo → Delete. Mais visual, recomendado.
--
-- Opção B (SQL avançado): rode o comando abaixo no SQL Editor.
--                         Funciona com Supabase Storage v2.

DELETE FROM storage.objects WHERE bucket_id = 'visita-anexos';

-- Verificação:
SELECT count(*) AS arquivos_restantes
  FROM storage.objects
 WHERE bucket_id = 'visita-anexos';


-- =============================================================================
-- ===== BLOCO 5: VERIFICAÇÃO FINAL =====
-- =============================================================================
-- Roda isso depois de tudo pra confirmar que o sistema tá zerado e o admin
-- continua acessível.

SELECT id, nome, email, perfil, super_admin, status
  FROM public.usuarios;
-- Esperado: 1 linha — seu admin master.

SELECT count(*) AS visitas       FROM public.visitas;        -- esperado 0
SELECT count(*) AS instituicoes  FROM public.instituicoes;   -- esperado 0
SELECT count(*) AS notificacoes  FROM public.notificacoes;   -- esperado 0
SELECT count(*) AS anexos        FROM public.visita_anexos;  -- esperado 0
SELECT count(*) AS profissionais FROM public.profissionais;  -- esperado 0
SELECT count(*) AS itens_padronizados FROM public.itens_padronizados; -- esperado 0


-- =============================================================================
-- ===== BLOCO 6 (DEPOIS DE 1-2 SEMANAS): LIMPAR BACKUPS =====
-- =============================================================================
-- Quando tiver certeza que o sistema em produção tá rodando bem, rode pra
-- liberar espaço no banco:
--
-- DROP TABLE IF EXISTS public._bkp_reset20260503_visitas;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_visitas_objetivos;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_visitas_profissionais;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_visita_anexos;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_solicitacoes_reabertura;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_notificacoes;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_profissionais;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_instituicoes;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_itens_padronizados;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_itens_padronizados_log;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_usuarios;
-- DROP TABLE IF EXISTS public._bkp_reset20260503_objetivos_visita;


-- =============================================================================
-- FIM
-- =============================================================================
-- Próximos passos depois do reset:
--   1. Logar como admin (você) e trocar a senha em /perfil
--   2. Cadastrar primeiros nutricionistas pelo /admin/equipe ou pelo fluxo de
--      auto-cadastro (#/cadastro)
--   3. Cadastrar primeiras instituições em /admin/instituicoes
--   4. Conferir as configurações em /admin/configuracoes (e-mail, frases, etc)
--   5. Subir o sistema pro time
