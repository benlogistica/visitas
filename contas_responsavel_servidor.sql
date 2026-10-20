-- =============================================================================
-- Sprint 9.32.487 — Responsável pela conta (instituição visitada por mais de um)
-- =============================================================================
-- Pedido da Paula: quando dois assessores visitam a mesma instituição, o
-- faturamento tem que ir para um só (ex.: Santa Casa e Mont Serrat são do
-- Reinaldo, e o faturamento aparecia também para a Andressa).
--
-- Regra: o responsável é quem o admin definir (instituicoes.responsavel_conta_id).
-- Sem definição, vale quem mais visitou (visitadores ativos primeiro; empate =
-- visita mais recente). Performance e ROI da Equipe contam o faturamento da
-- instituição só para o responsável.
-- =============================================================================

alter table public.instituicoes add column if not exists responsavel_conta_id uuid references public.usuarios(id);

-- Só admin define o responsável.
create or replace function public.instituicoes_proteger_responsavel()
returns trigger language plpgsql as $fn$
begin
  if current_user in ('anon', 'authenticated') and not coalesce(public.app_eh_admin(), false) then
    if tg_op = 'INSERT' then
      new.responsavel_conta_id := null;
    elsif new.responsavel_conta_id is distinct from old.responsavel_conta_id then
      raise exception 'Só o administrador define o responsável pela conta.';
    end if;
  end if;
  return new;
end $fn$;
drop trigger if exists instituicoes_proteger_responsavel on public.instituicoes;
create trigger instituicoes_proteger_responsavel before insert or update on public.instituicoes
  for each row execute function public.instituicoes_proteger_responsavel();

-- Responsável efetivo de cada instituição. Admin recebe todas; o visitador, só as que ele visitou.
create or replace function public.contas_responsaveis()
returns table (instituicao_id uuid, responsavel_id uuid, responsavel_nome text, definido boolean,
               visitadores jsonb)
language sql stable security definer set search_path = public as $fn$
  with c as (
    select v.instituicao_id, v.nutricionista_id, count(*) as n, max(v.data_visita) as ult,
           (u.status = 'ativo' and not coalesce(u.arquivado, false)) as ativo, u.nome
      from visitas v join usuarios u on u.id = v.nutricionista_id
     where v.checkin_timestamp is not null and v.cancelado_em is null and v.instituicao_id is not null
       and u.perfil = 'nutricionista'
     group by v.instituicao_id, v.nutricionista_id, u.status, u.arquivado, u.nome),
  r as (
    select c.*, row_number() over (partition by c.instituicao_id order by c.ativo desc, c.n desc, c.ult desc) as rk
      from c),
  agg as (
    select instituicao_id, jsonb_agg(jsonb_build_object('id', nutricionista_id, 'nome', nome, 'visitas', n, 'ativo', ativo)
                                     order by n desc) as vis
      from c group by instituicao_id)
  select i.id,
         coalesce(i.responsavel_conta_id, r.nutricionista_id),
         u.nome,
         i.responsavel_conta_id is not null,
         coalesce(agg.vis, '[]'::jsonb)
    from instituicoes i
    left join r   on r.instituicao_id = i.id and r.rk = 1
    left join agg on agg.instituicao_id = i.id
    left join usuarios u on u.id = coalesce(i.responsavel_conta_id, r.nutricionista_id)
   where coalesce(public.app_identificado(), false)
     and (i.responsavel_conta_id is not null or r.nutricionista_id is not null)
     and (coalesce(public.app_eh_admin(), false)
          or exists (select 1 from visitas v2 where v2.instituicao_id = i.id
                       and v2.nutricionista_id = public.app_usuario_id()));
$fn$;
revoke all on function public.contas_responsaveis() from public;
grant execute on function public.contas_responsaveis() to anon, authenticated;

-- Pedido da Paula: Santa Casa de Santos e Hospital Mont Serrat são do Reinaldo.
update public.instituicoes
   set responsavel_conta_id = (select id from public.usuarios where nome ilike 'reinaldo macedo%' limit 1)
 where id in (select id from public.instituicoes where nome in ('Santa Casa de Santos', 'Hospital Mont Serrat'));

select 'aplicado' as ok;
