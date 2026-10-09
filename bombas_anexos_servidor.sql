-- =============================================================================
-- Sprint 9.32.483 — Fotos e documentos das bombas de infusão
-- =============================================================================
-- Pedido da Paula: colocar foto da bomba e anexar documentos (contrato de
-- comodato, certificado de calibração, laudo de manutenção...).
--
-- Arquivos no bucket privado "bomba-anexos", na pasta <id da bomba>/.
-- Quem vê a bomba vê os anexos dela (mesmas travas de bombas_infusao):
-- o visitador só os da bomba dele, o admin todos.
-- Remover: quem enviou ou o admin. Máximo de 15 anexos por bomba, 10 MB cada.
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('bomba-anexos', 'bomba-anexos', false, 10485760, array[
  'image/jpeg', 'image/png', 'image/webp',
  'application/pdf', 'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.bombas_infusao_anexos (
  id              uuid primary key default gen_random_uuid(),
  bomba_id        uuid not null references public.bombas_infusao(id) on delete cascade,
  tipo            text not null,
  nome_original   text not null,
  mime_type       text not null,
  tamanho_bytes   integer not null,
  caminho_storage text not null unique,
  enviado_por     uuid,
  enviado_em      timestamptz not null default now(),
  constraint bombas_anexos_tipo_chk check (tipo in ('foto', 'documento')),
  constraint bombas_anexos_nome_chk check (length(nome_original) between 1 and 200 and nome_original !~ '[<>]'),
  constraint bombas_anexos_tam_chk  check (tamanho_bytes between 1 and 10485760),
  constraint bombas_anexos_cam_chk  check (caminho_storage like bomba_id::text || '/%' and position('..' in caminho_storage) = 0)
);
create index if not exists bombas_anexos_bomba_idx on public.bombas_infusao_anexos (bomba_id);

create or replace function public.bombas_anexos_antes()
returns trigger language plpgsql set search_path = public as $fn$
begin
  new.enviado_por := public.app_usuario_id();
  new.enviado_em  := now();
  if (select count(*) from bombas_infusao_anexos where bomba_id = new.bomba_id) >= 15 then
    raise exception 'Limite de 15 anexos por bomba. Remova algum antes de adicionar outro.';
  end if;
  return new;
end $fn$;
drop trigger if exists bombas_anexos_antes on public.bombas_infusao_anexos;
create trigger bombas_anexos_antes before insert on public.bombas_infusao_anexos
  for each row execute function public.bombas_anexos_antes();

alter table public.bombas_infusao_anexos enable row level security;

drop policy if exists bombas_anexos_ver on public.bombas_infusao_anexos;
create policy bombas_anexos_ver on public.bombas_infusao_anexos for select
  using (exists (select 1 from public.bombas_infusao b where b.id = bomba_id));

drop policy if exists bombas_anexos_criar on public.bombas_infusao_anexos;
create policy bombas_anexos_criar on public.bombas_infusao_anexos for insert
  with check (coalesce(public.app_identificado(), false)
              and exists (select 1 from public.bombas_infusao b where b.id = bomba_id));

drop policy if exists bombas_anexos_apagar on public.bombas_infusao_anexos;
create policy bombas_anexos_apagar on public.bombas_infusao_anexos for delete
  using (exists (select 1 from public.bombas_infusao b where b.id = bomba_id)
         and (coalesce(public.app_eh_admin(), false) or enviado_por = public.app_usuario_id()));

revoke all on public.bombas_infusao_anexos from anon, authenticated;
grant select, insert, delete on public.bombas_infusao_anexos to anon, authenticated;

-- Storage: só mexe no arquivo quem enxerga a bomba da pasta.
drop policy if exists bomba_anexos_ver on storage.objects;
create policy bomba_anexos_ver on storage.objects for select
  using (bucket_id = 'bomba-anexos'
         and exists (select 1 from public.bombas_infusao b where b.id::text = (storage.foldername(name))[1]));

drop policy if exists bomba_anexos_enviar on storage.objects;
create policy bomba_anexos_enviar on storage.objects for insert
  with check (bucket_id = 'bomba-anexos'
              and coalesce(public.app_identificado(), false)
              and exists (select 1 from public.bombas_infusao b where b.id::text = (storage.foldername(name))[1]));

drop policy if exists bomba_anexos_apagar on storage.objects;
create policy bomba_anexos_apagar on storage.objects for delete
  using (bucket_id = 'bomba-anexos'
         and exists (select 1 from public.bombas_infusao b where b.id::text = (storage.foldername(name))[1]));

-- APLICADO em 09/10/2026 pelo Edu no SQL Editor (resultado: aplicado).
