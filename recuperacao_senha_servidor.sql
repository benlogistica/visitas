-- Sprint 9.32.463: recuperação de senha no servidor + travas de cadastro e de perfil
-- APLICADA em 24/09/2026 pelo SQL Editor. __ANON__ = a anon key pública (CONFIG.SUPABASE_ANON_KEY do index.html).
-- app_eh_admin() devolve NULL quando o crachá não traz perfil: por isso o coalesce(..., false).
begin;

-- 1) Códigos de recuperação: só o hash, com validade e limite de tentativas.
create table if not exists public.recuperacao_senha (
  id          uuid primary key default gen_random_uuid(),
  usuario_id  uuid not null references public.usuarios(id) on delete cascade,
  codigo_hash text not null,
  expira_em   timestamptz not null,
  tentativas  int not null default 0,
  usado_em    timestamptz,
  criado_em   timestamptz not null default now()
);
create index if not exists recuperacao_senha_usuario_idx on public.recuperacao_senha (usuario_id, criado_em desc);
alter table public.recuperacao_senha enable row level security;
revoke all on public.recuperacao_senha from anon, authenticated;

-- 2) Solicitar: gera o código NO SERVIDOR e manda o e-mail daqui. O navegador nunca vê o código.
create or replace function public.recuperacao_solicitar(p_cpf text)
returns json language plpgsql security definer
set search_path = public, extensions as $fn$
declare
  v_dig text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  u record; v_b bytea; v_codigo text; v_recentes int; v_mask text; v_nome text; v_html text;
begin
  if length(v_dig) <> 11 then
    return json_build_object('ok', false, 'motivo', 'cpf_invalido');
  end if;
  select id, nome, email into u from usuarios
   where regexp_replace(cpf, '\D', '', 'g') = v_dig and coalesce(arquivado, false) = false
   limit 1;
  if not found then return json_build_object('ok', false, 'motivo', 'nao_encontrado'); end if;
  if coalesce(trim(u.email), '') = '' then return json_build_object('ok', false, 'motivo', 'sem_email'); end if;
  v_mask := regexp_replace(u.email, '^(.)[^@]*(@.*)$', '\1***\2');

  -- no máximo 3 códigos a cada 15 minutos por conta
  select count(*) into v_recentes from recuperacao_senha
   where usuario_id = u.id and criado_em > now() - interval '15 minutes';
  if v_recentes >= 3 then
    return json_build_object('ok', true, 'limitado', true, 'email', v_mask);
  end if;

  v_b := gen_random_bytes(3);
  v_codigo := lpad((((get_byte(v_b,0) << 16) | (get_byte(v_b,1) << 8) | get_byte(v_b,2)) % 1000000)::text, 6, '0');
  update recuperacao_senha set usado_em = now() where usuario_id = u.id and usado_em is null;
  insert into recuperacao_senha (usuario_id, codigo_hash, expira_em)
  values (u.id, encode(digest(v_codigo || ':' || u.id::text, 'sha256'), 'hex'), now() + interval '15 minutes');

  v_nome := coalesce(nullif(split_part(coalesce(u.nome, ''), ' ', 1), ''), 'Usuário');
  v_html := '<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"></head>'
    || '<body style="margin:0;padding:0;background:#f3f4f6;font-family:Arial,sans-serif;color:#0A1F5C;">'
    || '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:32px 16px;"><tr><td align="center">'
    || '<table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#fff;border-radius:16px;overflow:hidden;">'
    || '<tr><td style="background:#0A1F5C;padding:24px 32px;"><div style="font-size:13px;letter-spacing:1.4px;color:#8BC63F;font-weight:700;text-transform:uppercase;">B&amp;N Logística</div>'
    || '<div style="font-size:22px;font-weight:700;color:#fff;margin-top:6px;">Código de recuperação de senha</div></td></tr>'
    || '<tr><td style="padding:32px;font-size:15px;line-height:1.6;">'
    || '<p>Olá, <strong>' || replace(replace(v_nome, '<', ''), '>', '') || '</strong>!</p>'
    || '<p>Recebemos uma solicitação para redefinir a senha da sua conta. Use o código abaixo para continuar:</p>'
    || '<div style="margin:24px 0;text-align:center;"><div style="display:inline-block;background:#f3f4f6;border:2px solid #8BC63F;border-radius:12px;padding:18px 36px;font-family:Courier New,monospace;font-size:32px;font-weight:700;letter-spacing:0.4em;color:#0A1F5C;">' || v_codigo || '</div></div>'
    || '<p style="font-size:13px;color:#6b7280;text-align:center;">Este código expira em <strong>15 minutos</strong>.</p>'
    || '<p>Se você não pediu para redefinir a senha, ignore este e-mail e sua senha continua a mesma.</p></td></tr>'
    || '<tr><td style="padding:20px 32px;background:#f9fafb;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;">Por segurança, nunca compartilhe esse código. A B&amp;N Logística nunca pede seu código por telefone ou WhatsApp.<br><br>Dúvidas: atendimento@benlogistica.com.br</td></tr>'
    || '</table></td></tr></table></body></html>';

  -- 9.32.464: vai pela fila (a send-email não aceita mais to/subject/html de fora)
  perform _email_enfileirar(
    u.email,
    '[B&N Logística] Código de recuperação: ' || v_codigo,
    v_html,
    'Olá, ' || v_nome || E'!\n\nSeu código de recuperação de senha é: ' || v_codigo || E'\n\nEle expira em 15 minutos.\n\nSe você não pediu, ignore este e-mail.',
    'recuperacao:' || u.id::text);
  return json_build_object('ok', true, 'email', v_mask);
end $fn$;

-- 3) Confirmar: confere o código (5 tentativas) e, se vier a senha nova, grava.
--    Sem p_senha_hash só valida o código (etapa do código na tela).
create or replace function public.recuperacao_confirmar(p_cpf text, p_codigo text, p_senha_hash text default null)
returns json language plpgsql security definer
set search_path = public, extensions as $fn$
declare
  v_dig text := regexp_replace(coalesce(p_cpf, ''), '\D', '', 'g');
  v_cod text := regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g');
  v_uid uuid; r record;
begin
  select id into v_uid from usuarios
   where regexp_replace(cpf, '\D', '', 'g') = v_dig and coalesce(arquivado, false) = false limit 1;
  if v_uid is null then return json_build_object('ok', false, 'motivo', 'expirado'); end if;

  select * into r from recuperacao_senha
   where usuario_id = v_uid and usado_em is null
   order by criado_em desc limit 1 for update;
  if not found or r.expira_em < now() then return json_build_object('ok', false, 'motivo', 'expirado'); end if;
  if r.tentativas >= 5 then return json_build_object('ok', false, 'motivo', 'bloqueado'); end if;

  if encode(digest(v_cod || ':' || v_uid::text, 'sha256'), 'hex') <> r.codigo_hash then
    update recuperacao_senha set tentativas = tentativas + 1 where id = r.id;
    return json_build_object('ok', false, 'motivo', 'codigo_invalido', 'restantes', greatest(0, 4 - r.tentativas));
  end if;

  if p_senha_hash is null then
    return json_build_object('ok', true, 'etapa', 'codigo_valido');
  end if;
  if p_senha_hash !~ '^[0-9a-f]{64}$' then
    return json_build_object('ok', false, 'motivo', 'senha_invalida');
  end if;

  update usuarios set senha_hash = p_senha_hash where id = v_uid;
  update recuperacao_senha set usado_em = now() where id = r.id;
  return json_build_object('ok', true, 'etapa', 'senha_trocada');
end $fn$;

revoke all on function public.recuperacao_solicitar(text) from public;
revoke all on function public.recuperacao_confirmar(text, text, text) from public;
grant execute on function public.recuperacao_solicitar(text) to anon, authenticated;
grant execute on function public.recuperacao_confirmar(text, text, text) to anon, authenticated;

-- 4) A função antiga devolvia id + e-mail de qualquer CPF. Só a tela de recuperação usava.
revoke execute on function public.dados_recuperacao(text) from public, anon, authenticated;

-- 5) Cadastro público: sem crachá de admin, só nasce conta pendente, de profissional ou atendente, sem permissões.
drop policy if exists usuarios_criar on public.usuarios;
create policy usuarios_criar on public.usuarios for insert to public
with check (
  coalesce(app_eh_admin(), false)
  or (
    status = 'pendente'
    and perfil in ('nutricionista', 'atendente')
    and coalesce(super_admin, false) = false
    and (permissoes is null or permissoes = '{}'::jsonb)
    and aprovado_em is null and aprovado_por is null
    and coalesce(arquivado, false) = false
  )
);

-- 6) Quem está logado edita a própria linha (nome, foto, preferências, senha),
--    mas não os campos que dão poder: perfil, situação, super admin, permissões, aprovação, arquivamento.
--    Só vale para requisições do app (anon/authenticated). Funções do servidor e o painel continuam livres.
create or replace function public.usuarios_proteger_campos()
returns trigger language plpgsql as $fn$
begin
  if current_user in ('anon', 'authenticated') and not coalesce(app_eh_admin(), false) then
    if new.perfil is distinct from old.perfil
       or new.status is distinct from old.status
       or new.super_admin is distinct from old.super_admin
       or new.permissoes is distinct from old.permissoes
       or new.aprovado_em is distinct from old.aprovado_em
       or new.aprovado_por is distinct from old.aprovado_por
       or new.arquivado is distinct from old.arquivado
       or new.cpf is distinct from old.cpf then
      raise exception 'Somente o administrador pode alterar perfil, situação ou permissões da conta.'
        using errcode = '42501';
    end if;
  end if;
  return new;
end $fn$;

drop trigger if exists trg_usuarios_proteger_campos on public.usuarios;
create trigger trg_usuarios_proteger_campos before update on public.usuarios
for each row execute function public.usuarios_proteger_campos();

commit;
