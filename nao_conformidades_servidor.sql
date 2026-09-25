-- =============================================================================
-- Sprint 9.32.475 — Não conformidades: envio do relatório por e-mail com PDF
-- =============================================================================
-- Quem pode: admin que é super admin OU recebeu a permissão
-- permissoes.nao_conformidades (concedida pelo super admin na Equipe).
-- O PDF vai como anexo. A fila guarda o anexo só até o envio (a send-email
-- apaga depois de mandar).
-- =============================================================================

alter table public.email_fila add column if not exists anexo_b64  text;
alter table public.email_fila add column if not exists anexo_nome text;
alter table public.email_fila add column if not exists anexo_tipo text;

create or replace function public.app_pode_nc()
returns boolean language sql stable security definer set search_path = public as $fn$
  select exists (
    select 1 from usuarios u
     where u.id = public.app_usuario_id() and u.perfil = 'admin' and u.status = 'ativo'
       and (coalesce(u.super_admin, false) or coalesce((u.permissoes ->> 'nao_conformidades')::boolean, false)));
$fn$;
revoke all on function public.app_pode_nc() from public;
grant execute on function public.app_pode_nc() to anon, authenticated;

create or replace function public.email_enviar_nc(
  p_para text[], p_assunto text, p_html text, p_texto text,
  p_anexo_b64 text default null, p_anexo_nome text default null)
returns json language plpgsql security definer
set search_path = public, extensions as $fn$
declare v_email text; v_id uuid; n int := 0;
begin
  if not public.app_pode_nc() then
    return json_build_object('ok', false, 'error', 'sem_permissao');
  end if;
  if p_para is null or cardinality(p_para) = 0 then
    return json_build_object('ok', false, 'error', 'sem_destinatario');
  end if;
  if cardinality(p_para) > 15 then
    return json_build_object('ok', false, 'error', 'destinatarios_demais');
  end if;
  if p_anexo_b64 is not null and length(p_anexo_b64) > 12000000 then
    return json_build_object('ok', false, 'error', 'anexo_grande_demais');
  end if;
  foreach v_email in array p_para loop
    v_email := lower(trim(v_email));
    continue when v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$';
    insert into email_fila (para, assunto, html, texto, origem, anexo_b64, anexo_nome, anexo_tipo)
    values (v_email, p_assunto, p_html, p_texto, 'nc:' || public.app_usuario_id()::text,
            p_anexo_b64, p_anexo_nome, case when p_anexo_b64 is not null then 'application/pdf' end)
    returning id into v_id;
    perform net.http_post(
      url     := 'https://qrlnbtxscjrmnpfjbtvv.supabase.co/functions/v1/send-email',
      headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization',
                   'Bearer ' || (select valor from app_segredos where nome = 'anon_key')),
      body    := jsonb_build_object('id', v_id));
    n := n + 1;
  end loop;
  return json_build_object('ok', n > 0, 'enviados', n, 'error', case when n = 0 then 'emails_invalidos' end);
end $fn$;
revoke all on function public.email_enviar_nc(text[], text, text, text, text, text) from public;
grant execute on function public.email_enviar_nc(text[], text, text, text, text, text) to anon, authenticated;

-- APLICADO em 25/09/2026.
