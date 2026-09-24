-- =============================================================================
-- Sprint 9.32.464 — fecha a send-email (fila de e-mails no servidor)
--                 + chave do arquivo de faturamento
-- =============================================================================
-- ANTES: a Edge Function send-email aceitava {to, subject, html} de qualquer um
--        que tivesse a chave pública (que está no index.html). Dava pra usar o
--        SMTP da B&N para mandar qualquer e-mail, para qualquer endereço.
-- AGORA: a send-email só aceita {id}. Ela busca a mensagem nesta fila (que só o
--        banco escreve) e envia. Quem chama de fora, sem uma mensagem legítima
--        já enfileirada, não consegue mandar nada.
--
-- Quem enfileira (todas SECURITY DEFINER, o app nunca escreve direto na fila):
--   _email_enfileirar(...)          interna; ninguém de fora executa
--   email_enviar_admin(...)         só admin (aprovação de cadastro, teste SMTP)
--   email_cadastro_recebido(cpf)    pré-login; só para conta PENDENTE, 1 vez,
--                                   com texto fixo, para o e-mail da própria conta
--   recuperacao_solicitar(cpf)      já existia; passa a usar a fila
--   email_status(id)                só admin; o teste SMTP mostra se chegou
--
-- =============================================================================

-- 0) Segredos do servidor (ninguém de fora lê) ---------------------------------
create table if not exists public.app_segredos (
  nome  text primary key,
  valor text not null
);
alter table public.app_segredos enable row level security;
revoke all on public.app_segredos from anon, authenticated;

-- anon key: copiada da função de recuperação já existente (não é digitada aqui)
do $do$
declare v text;
begin
  v := substring(pg_get_functiondef('public.recuperacao_solicitar(text)'::regprocedure)
                 from 'Bearer ([A-Za-z0-9._-]+)');
  if v is not null then
    insert into public.app_segredos values ('anon_key', v)
    on conflict (nome) do update set valor = excluded.valor;
  end if;
end $do$;

-- chave AES do faturamento: gerada AQUI, no banco. Depois é copiada uma vez
-- para o arquivo local faturamento.key (fora do git), que o atualizar_index.py usa.
insert into public.app_segredos
values ('faturamento_chave', encode(extensions.gen_random_bytes(32), 'base64'))
on conflict (nome) do nothing;

-- 1) A fila ------------------------------------------------------------------
create table if not exists public.email_fila (
  id          uuid primary key default gen_random_uuid(),
  para        text not null,
  assunto     text not null,
  html        text,
  texto       text,
  origem      text not null,
  status      text not null default 'pendente',   -- pendente | enviando | enviado | erro
  erro        text,
  criado_em   timestamptz not null default now(),
  enviado_em  timestamptz
);
create index if not exists email_fila_origem_idx on public.email_fila (origem);
alter table public.email_fila enable row level security;
revoke all on public.email_fila from anon, authenticated;

-- 2) Enfileirar + acordar a send-email ----------------------------------------
create or replace function public._email_enfileirar(
  p_para text, p_assunto text, p_html text, p_texto text, p_origem text)
returns uuid language plpgsql security definer
set search_path = public, extensions as $fn$
declare v_id uuid;
begin
  if coalesce(trim(p_para), '') = '' or p_para !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'destinatario_invalido';
  end if;
  insert into email_fila (para, assunto, html, texto, origem)
  values (lower(trim(p_para)), p_assunto, p_html, p_texto, p_origem)
  returning id into v_id;

  perform net.http_post(
    url     := 'https://qrlnbtxscjrmnpfjbtvv.supabase.co/functions/v1/send-email',
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
                 'Bearer ' || (select valor from app_segredos where nome = 'anon_key')),
    body    := jsonb_build_object('id', v_id)
  );
  return v_id;
end $fn$;
revoke all on function public._email_enfileirar(text, text, text, text, text) from public, anon, authenticated;

-- 3) Molde B&N (mesmo visual do _emailTemplateBN do app) -----------------------
create or replace function public._email_molde_bn(p_titulo text, p_corpo text, p_rodape text)
returns text language sql immutable as $fn$
  select '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"></head>'
    || '<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,sans-serif;color:#0A1F5C;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:32px 16px;"><tr><td align="center">'
    || '<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#fff;border-radius:16px;overflow:hidden;">'
    || '<tr><td style="background:#0A1F5C;padding:24px 32px;"><div style="font-size:13px;letter-spacing:1.4px;color:#8BC63F;font-weight:700;text-transform:uppercase;">B&amp;N Logística</div>'
    || '<div style="font-size:22px;font-weight:700;color:#fff;margin-top:6px;">' || p_titulo || '</div></td></tr>'
    || '<tr><td style="padding:32px;font-size:15px;line-height:1.6;">' || p_corpo || '</td></tr>'
    || '<tr><td style="padding:20px 32px;background:#f9fafb;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;">'
    || p_rodape || '<br><br>Em caso de dúvidas, entre em contato: atendimento@benlogistica.com.br</td></tr>'
    || '</table></td></tr></table></body></html>';
$fn$;
revoke all on function public._email_molde_bn(text, text, text) from public, anon, authenticated;

-- 4) Admin envia (aprovação de cadastro, teste SMTP) --------------------------
create or replace function public.email_enviar_admin(
  p_para text, p_assunto text, p_html text, p_texto text default null)
returns json language plpgsql security definer
set search_path = public, extensions as $fn$
declare v_id uuid;
begin
  if not coalesce(app_eh_admin(), false) then
    return json_build_object('ok', false, 'error', 'sem_permissao');
  end if;
  v_id := _email_enfileirar(p_para, p_assunto, p_html, p_texto, 'admin:' || app_usuario_id()::text);
  return json_build_object('ok', true, 'id', v_id);
exception when others then
  return json_build_object('ok', false, 'error', sqlerrm);
end $fn$;
revoke all on function public.email_enviar_admin(text, text, text, text) from public;
grant execute on function public.email_enviar_admin(text, text, text, text) to anon, authenticated;

create or replace function public.email_status(p_id uuid)
returns json language plpgsql security definer
set search_path = public as $fn$
declare r record;
begin
  if not coalesce(app_eh_admin(), false) then
    return json_build_object('ok', false, 'error', 'sem_permissao');
  end if;
  select status, erro, enviado_em into r from email_fila where id = p_id;
  if not found then return json_build_object('ok', false, 'error', 'nao_encontrado'); end if;
  return json_build_object('ok', true, 'status', r.status, 'erro', r.erro, 'enviado_em', r.enviado_em);
end $fn$;
revoke all on function public.email_status(uuid) from public;
grant execute on function public.email_status(uuid) to anon, authenticated;

-- 5) "Cadastro recebido" (roda antes do login) --------------------------------
--    Só manda para conta PENDENTE, uma única vez, texto fixo, e-mail da conta.
create or replace function public.email_cadastro_recebido(p_cpf text)
returns json language plpgsql security definer
set search_path = public, extensions as $fn$
declare
  v_dig text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  u record; v_nome text;
begin
  if length(v_dig) <> 11 then return json_build_object('ok', false); end if;
  select id, nome, email into u from usuarios
   where regexp_replace(cpf, '\D', '', 'g') = v_dig and status = 'pendente'
     and coalesce(arquivado, false) = false
   limit 1;
  if not found or coalesce(trim(u.email), '') = '' then return json_build_object('ok', false); end if;
  if exists (select 1 from email_fila where origem = 'cadastro:' || u.id::text) then
    return json_build_object('ok', true, 'repetido', true);
  end if;

  v_nome := coalesce(nullif(split_part(coalesce(u.nome, ''), ' ', 1), ''), 'Profissional');
  v_nome := replace(replace(replace(v_nome, '&', ''), '<', ''), '>', '');
  perform _email_enfileirar(
    u.email,
    '[B&N Logistica] Cadastro recebido',
    _email_molde_bn('Cadastro recebido',
      '<p>Olá, <strong>' || v_nome || '</strong>!</p>'
      || '<p>Recebemos seu cadastro na plataforma <strong>B&amp;N Logística</strong>. Sua conta está aguardando aprovação do administrador.</p>'
      || '<p>Você receberá um novo e-mail assim que for aprovado e poderá começar a usar o sistema.</p>'
      || '<p style="font-size:13px;color:#6b7280;margin-top:24px;">Se você não fez esse cadastro, ignore este e-mail.</p>',
      'Você está recebendo este e-mail porque alguém usou este endereço para se cadastrar no sistema B&amp;N Logística.'),
    'Olá, ' || v_nome || E'!\n\nRecebemos seu cadastro na B&N Logística. Sua conta está aguardando aprovação do administrador.\n\nVocê receberá outro e-mail assim que for aprovado.',
    'cadastro:' || u.id::text);
  return json_build_object('ok', true);
end $fn$;
revoke all on function public.email_cadastro_recebido(text) from public;
grant execute on function public.email_cadastro_recebido(text) to anon, authenticated;

-- 6) Recuperação de senha passa a usar a fila ---------------------------------
--    (aplicado por substituição do bloco net.http_post dentro de
--     recuperacao_solicitar — ver recuperacao_senha_servidor.sql, já atualizado)

-- 7) Quem pode pegar a chave do arquivo de faturamento ------------------------------------------
--    O faturamento_data.enc publicado no site é cifrado (AES-256-GCM). A chave
--    fica aqui e só sai para quem está logado com conta ativa.
create or replace function public.faturamento_chave()
returns text language plpgsql stable security definer
set search_path = public as $fn$
begin
  if not exists (select 1 from usuarios
                  where id = app_usuario_id() and status = 'ativo'
                    and coalesce(arquivado, false) = false) then
    return null;
  end if;
  return (select valor from app_segredos where nome = 'faturamento_chave');
end $fn$;
revoke all on function public.faturamento_chave() from public;
grant execute on function public.faturamento_chave() to anon, authenticated;

-- 8) notificacoes: INSERT era aberto (with check true) -----------------------
--    Qualquer um criava notificação (e e-mail) para qualquer usuário.
--    Agora: logado cria; sem login, só "categoria_sugerida" para admin ativo
--    (é o que o cadastro público faz). Testado com transação desfeita.
create or replace function public.app_usuario_eh_admin_ativo(p_id uuid)
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from usuarios where id = p_id and perfil = 'admin' and status = 'ativo');
$fn$;
revoke all on function public.app_usuario_eh_admin_ativo(uuid) from public;
grant execute on function public.app_usuario_eh_admin_ativo(uuid) to anon, authenticated;

drop policy if exists notif_criar on public.notificacoes;
create policy notif_criar on public.notificacoes for insert with check (
  coalesce(public.app_identificado(), false)
  or (tipo = 'categoria_sugerida' and public.app_usuario_eh_admin_ativo(user_id))
);

-- APLICADO em 24/09/2026 (SQL Editor). recuperacao_solicitar recriada a partir
-- de recuperacao_senha_servidor.sql (agora usa _email_enfileirar).

-- 9) Sprint 9.32.465: nada com < ou > entra pelo cadastro público ----------------
alter table public.usuarios drop constraint if exists usuarios_sem_html;
alter table public.usuarios add constraint usuarios_sem_html
  check (coalesce(nome,'') !~ '[<>]' and coalesce(email,'') !~ '[<>]' and coalesce(telefone,'') !~ '[<>]');
alter table public.categorias_profissionais drop constraint if exists categorias_sem_html;
alter table public.categorias_profissionais add constraint categorias_sem_html
  check (coalesce(nome,'') !~ '[<>]');
drop policy if exists notif_criar on public.notificacoes;
create policy notif_criar on public.notificacoes for insert with check (
  coalesce(public.app_identificado(), false)
  or (tipo = 'categoria_sugerida' and public.app_usuario_eh_admin_ativo(user_id)
      and coalesce(titulo,'') !~ '[<>]' and coalesce(mensagem,'') !~ '[<>]' and coalesce(link,'') !~ '[<>:]')
);
-- APLICADO em 24/09/2026 e testado (update com '<b>' e insert com '<script>' bloqueados).
