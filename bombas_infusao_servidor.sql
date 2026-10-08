-- =============================================================================
-- Sprint 9.32.481 — Controle de bombas de infusão (comodato)
-- =============================================================================
-- Pedido da Paula: cada visitador registra as bombas que deixou nos hospitais
-- (comodato). O admin acompanha tudo num painel gerencial.
--
-- Quem vê o quê:
--   - visitador: só as bombas no nome dele (responsavel_id = ele)
--   - admin: todas; pode transferir de um visitador para outro e excluir
--   - o visitador só exclui o que ele mesmo lançou nas últimas 24 h (erro de lançamento)
-- Uma bomba (marca + número de série) não pode estar ativa em dois lugares ao
-- mesmo tempo. Depois de retirada, ela pode ser entregue de novo (novo registro).
-- Toda mudança fica no histórico (bombas_infusao_eventos), gravado pelo banco.
-- =============================================================================

create table if not exists public.bombas_infusao (
  id                    uuid primary key default gen_random_uuid(),
  instituicao_id        uuid not null references public.instituicoes(id),
  responsavel_id        uuid not null references public.usuarios(id),
  marca                 text not null,
  numero_serie          text not null,
  data_entrega          date not null,
  calibracao_vencimento date,
  status                text not null default 'em_uso',
  manutencao_desde      date,
  data_retirada         date,
  observacao            text,
  criado_por            uuid,
  criado_em             timestamptz not null default now(),
  atualizado_por        uuid,
  atualizado_em         timestamptz not null default now(),
  constraint bombas_marca_chk    check (marca in ('Compact Ella', 'Kangaroo')),
  constraint bombas_status_chk   check (status in ('em_uso', 'manutencao', 'retirada')),
  constraint bombas_serie_chk    check (length(btrim(numero_serie)) between 1 and 60 and numero_serie !~ '[<>]'),
  constraint bombas_obs_chk      check (observacao is null or (length(observacao) <= 500 and observacao !~ '[<>]')),
  constraint bombas_retirada_chk check ((status = 'retirada') = (data_retirada is not null)),
  constraint bombas_datas_chk    check (data_retirada is null or data_retirada >= data_entrega)
);

create unique index if not exists bombas_serie_ativa_uk
  on public.bombas_infusao (marca, upper(btrim(numero_serie))) where status <> 'retirada';
create index if not exists bombas_responsavel_idx on public.bombas_infusao (responsavel_id);
create index if not exists bombas_instituicao_idx on public.bombas_infusao (instituicao_id);

create table if not exists public.bombas_infusao_eventos (
  id         bigserial primary key,
  bomba_id   uuid not null references public.bombas_infusao(id) on delete cascade,
  tipo       text not null,
  detalhe    jsonb,
  usuario_id uuid,
  criado_em  timestamptz not null default now()
);
create index if not exists bombas_eventos_bomba_idx on public.bombas_infusao_eventos (bomba_id, criado_em);

-- Antes de gravar: padroniza o número de série, carimba quem/quando e impede que o
-- visitador coloque bomba no nome de outra pessoa.
create or replace function public.bombas_infusao_antes()
returns trigger language plpgsql set search_path = public as $fn$
declare
  v_eu  uuid    := public.app_usuario_id();
  v_adm boolean := coalesce(public.app_eh_admin(), false);
begin
  new.numero_serie := upper(btrim(new.numero_serie));
  if tg_op = 'INSERT' then
    new.criado_por := v_eu;
    new.criado_em  := now();
    if new.responsavel_id is null then new.responsavel_id := v_eu; end if;
  else
    new.criado_por := old.criado_por;
    new.criado_em  := old.criado_em;
  end if;
  if current_user in ('anon', 'authenticated') and not v_adm
     and new.responsavel_id is distinct from v_eu then
    raise exception 'A bomba só pode ficar no seu nome. Para transferir, fale com o administrador.';
  end if;
  if new.status = 'manutencao' then
    if tg_op = 'INSERT' or old.status <> 'manutencao' then
      new.manutencao_desde := coalesce(new.manutencao_desde, current_date);
    end if;
  else
    new.manutencao_desde := null;
  end if;
  if new.status <> 'retirada' then new.data_retirada := null; end if;
  new.atualizado_por := v_eu;
  new.atualizado_em  := now();
  return new;
end $fn$;
drop trigger if exists bombas_infusao_antes on public.bombas_infusao;
create trigger bombas_infusao_antes before insert or update on public.bombas_infusao
  for each row execute function public.bombas_infusao_antes();

-- Depois de gravar: registra o que mudou no histórico.
create or replace function public.bombas_infusao_historico()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_eu uuid := public.app_usuario_id();
begin
  if tg_op = 'INSERT' then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, 'entrega', jsonb_build_object('instituicao_id', new.instituicao_id,
            'data', new.data_entrega, 'status', new.status), v_eu);
    return new;
  end if;
  if new.status is distinct from old.status then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, case new.status when 'manutencao' then 'manutencao'
                                    when 'retirada'   then 'retirada'
                                    else case when old.status = 'retirada' then 'reativada' else 'volta_uso' end end,
            jsonb_build_object('de', old.status, 'para', new.status, 'data_retirada', new.data_retirada), v_eu);
  end if;
  if new.responsavel_id is distinct from old.responsavel_id then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, 'transferencia', jsonb_build_object('de', old.responsavel_id, 'para', new.responsavel_id), v_eu);
  end if;
  if new.instituicao_id is distinct from old.instituicao_id then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, 'troca_hospital', jsonb_build_object('de', old.instituicao_id, 'para', new.instituicao_id), v_eu);
  end if;
  if new.calibracao_vencimento is distinct from old.calibracao_vencimento then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, 'calibracao', jsonb_build_object('de', old.calibracao_vencimento, 'para', new.calibracao_vencimento), v_eu);
  end if;
  if (new.marca, new.numero_serie, new.data_entrega, coalesce(new.observacao, ''))
     is distinct from (old.marca, old.numero_serie, old.data_entrega, coalesce(old.observacao, '')) then
    insert into bombas_infusao_eventos (bomba_id, tipo, detalhe, usuario_id)
    values (new.id, 'edicao', jsonb_build_object('marca', new.marca, 'numero_serie', new.numero_serie,
            'data_entrega', new.data_entrega), v_eu);
  end if;
  return new;
end $fn$;
drop trigger if exists bombas_infusao_historico on public.bombas_infusao;
create trigger bombas_infusao_historico after insert or update on public.bombas_infusao
  for each row execute function public.bombas_infusao_historico();

-- Travas
alter table public.bombas_infusao enable row level security;
alter table public.bombas_infusao_eventos enable row level security;

drop policy if exists bombas_ver on public.bombas_infusao;
create policy bombas_ver on public.bombas_infusao for select
  using (coalesce(public.app_eh_admin(), false) or responsavel_id = public.app_usuario_id());

drop policy if exists bombas_criar on public.bombas_infusao;
create policy bombas_criar on public.bombas_infusao for insert
  with check (coalesce(public.app_identificado(), false)
              and (coalesce(public.app_eh_admin(), false) or responsavel_id = public.app_usuario_id()));

drop policy if exists bombas_editar on public.bombas_infusao;
create policy bombas_editar on public.bombas_infusao for update
  using      (coalesce(public.app_eh_admin(), false) or responsavel_id = public.app_usuario_id())
  with check (coalesce(public.app_eh_admin(), false) or responsavel_id = public.app_usuario_id());

drop policy if exists bombas_apagar on public.bombas_infusao;
create policy bombas_apagar on public.bombas_infusao for delete
  using (coalesce(public.app_eh_admin(), false)
         or (responsavel_id = public.app_usuario_id() and criado_por = public.app_usuario_id()
             and criado_em > now() - interval '24 hours'));

drop policy if exists bombas_eventos_ver on public.bombas_infusao_eventos;
create policy bombas_eventos_ver on public.bombas_infusao_eventos for select
  using (coalesce(public.app_eh_admin(), false)
         or exists (select 1 from public.bombas_infusao b
                     where b.id = bomba_id and b.responsavel_id = public.app_usuario_id()));

revoke all on public.bombas_infusao from anon, authenticated;
grant select, insert, update, delete on public.bombas_infusao to anon, authenticated;
revoke all on public.bombas_infusao_eventos from anon, authenticated;
grant select on public.bombas_infusao_eventos to anon, authenticated;
revoke all on sequence public.bombas_infusao_eventos_id_seq from anon, authenticated;

-- APLICADO em 07/10/2026 pelo SQL Editor, depois de testado em transação desfeita
-- (nutri cria; não põe no nome de outro; não vê/edita/apaga a dos outros; série ativa
-- duplicada bloqueada; histórico só o banco grava; admin vê e transfere; sem login não vê nada).
