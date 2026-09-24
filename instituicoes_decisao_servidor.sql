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
