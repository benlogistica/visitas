-- =============================================================================
-- Sprint 9.32.485 — Documentos anexados em Não conformidades
-- =============================================================================
-- Guarda relatórios em PDF (auditorias, laudos) dentro da tela Não conformidades.
-- Só quem tem acesso a Não conformidades (app_pode_nc) vê, anexa e remove.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('nc-documentos', 'nc-documentos', false, 20971520, array[
  'application/pdf',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.nc_documentos (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null,
  nome_arquivo    text not null,
  mime_type       text not null,
  tamanho_bytes   integer not null,
  caminho_storage text not null unique,
  enviado_por     uuid,
  enviado_em      timestamptz not null default now(),
  constraint nc_doc_titulo_chk check (length(titulo) between 1 and 150 and titulo !~ '[<>]'),
  constraint nc_doc_nome_chk   check (length(nome_arquivo) between 1 and 200 and nome_arquivo !~ '[<>]'),
  constraint nc_doc_tam_chk    check (tamanho_bytes between 1 and 20971520),
  constraint nc_doc_cam_chk    check (position('..' in caminho_storage) = 0)
);

create or replace function public.nc_documentos_antes()
returns trigger language plpgsql set search_path = public as $fn$
begin
  new.enviado_por := public.app_usuario_id();
  new.enviado_em  := now();
  return new;
end $fn$;
drop trigger if exists nc_documentos_antes on public.nc_documentos;
create trigger nc_documentos_antes before insert on public.nc_documentos
  for each row execute function public.nc_documentos_antes();

alter table public.nc_documentos enable row level security;
drop policy if exists nc_doc_ver on public.nc_documentos;
create policy nc_doc_ver on public.nc_documentos for select using (public.app_pode_nc());
drop policy if exists nc_doc_criar on public.nc_documentos;
create policy nc_doc_criar on public.nc_documentos for insert with check (public.app_pode_nc());
drop policy if exists nc_doc_apagar on public.nc_documentos;
create policy nc_doc_apagar on public.nc_documentos for delete using (public.app_pode_nc());
revoke all on public.nc_documentos from anon, authenticated;
grant select, insert, delete on public.nc_documentos to anon, authenticated;

drop policy if exists nc_documentos_ver on storage.objects;
create policy nc_documentos_ver on storage.objects for select
  using (bucket_id = 'nc-documentos' and public.app_pode_nc());
drop policy if exists nc_documentos_enviar on storage.objects;
create policy nc_documentos_enviar on storage.objects for insert
  with check (bucket_id = 'nc-documentos' and public.app_pode_nc());
drop policy if exists nc_documentos_apagar on storage.objects;
create policy nc_documentos_apagar on storage.objects for delete
  using (bucket_id = 'nc-documentos' and public.app_pode_nc());

select 'aplicado' as ok;
-- APLICADO em 09/10/2026 pelo SQL Editor.
