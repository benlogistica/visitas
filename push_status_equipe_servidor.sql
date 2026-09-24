-- Sprint 9.32.471: admin vê na Equipe quem está com a notificação do celular ativada
-- (sininho verde = recebe o aviso de check-out esquecido; cinza = não recebe).
create or replace function public.push_status_equipe()
returns table (usuario_id uuid, aparelhos int, ultimo_uso timestamptz, inscrito_em timestamptz)
language sql stable security definer set search_path = public as $fn$
  select p.usuario_id, count(*)::int, max(p.ultimo_uso), max(p.criado_em)
    from push_inscricoes p
   where coalesce(public.app_eh_admin(), false)
     and coalesce(p.falhas, 0) < 3
   group by p.usuario_id;
$fn$;
revoke all on function public.push_status_equipe() from public;
grant execute on function public.push_status_equipe() to anon, authenticated;
-- APLICADO em 24/09/2026.
