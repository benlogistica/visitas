-- Sprint 9.32.469: só admin aprova, rejeita, desativa ou reativa instituição.
-- A tela de instituições da nutricionista reaproveitava a do admin e mostrava os
-- botões de aprovar/rejeitar; o banco aceitava porque a nutri pode editar.
-- Editar os dados continua liberado. Testado em transação desfeita.
create or replace function public.instituicoes_proteger_decisao()
returns trigger language plpgsql as $fn$
begin
  if current_user in ('anon', 'authenticated') and not coalesce(public.app_eh_admin(), false) then
    if (old.pendente_aprovacao is true and new.pendente_aprovacao is false)
       or (new.ativo is distinct from old.ativo) then
      raise exception 'Só o administrador aprova, rejeita ou desativa instituição.';
    end if;
  end if;
  return new;
end $fn$;
drop trigger if exists instituicoes_proteger_decisao on public.instituicoes;
create trigger instituicoes_proteger_decisao before update on public.instituicoes
  for each row execute function public.instituicoes_proteger_decisao();
-- APLICADO em 24/09/2026.

-- Sprint 9.32.470: instituição sem CNPJ pode ser conferida pela equipe como
-- pessoa física ou "não possui" (tela Mapear CNPJs, aba "Conferidas sem CNPJ").
alter table public.instituicoes add column if not exists cnpj_situacao text;
alter table public.instituicoes drop constraint if exists instituicoes_cnpj_situacao_chk;
alter table public.instituicoes add constraint instituicoes_cnpj_situacao_chk
  check (cnpj_situacao is null or cnpj_situacao in ('pessoa_fisica', 'nao_possui'));
alter table public.instituicoes add column if not exists cnpj_situacao_por uuid;
alter table public.instituicoes add column if not exists cnpj_situacao_em timestamptz;
-- "Hospital kennedy" (endereço/bairro/cidade = "Teste", 0 visitas) desativado a pedido.
-- APLICADO em 24/09/2026.
