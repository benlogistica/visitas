-- =============================================================================
-- Sprint 9.32.470 — limpeza automática das notificações (roda todo dia)
-- =============================================================================
-- Havia ~3 mil notificações não lidas: o sininho do admin vivia em "99+" e
-- deixava de avisar alguma coisa. A maioria já estava resolvida (visita já
-- aprovada, instituição já decidida). Todo dia, às 03h (Brasília):
--   1. marca como lida o que já foi resolvido:
--      - visita sinalizada / reenviada / auto-fechada cuja visita já foi
--        aprovada ou cancelada (ou não existe mais);
--      - instituição sugerida que já foi aprovada, rejeitada ou desativada;
--   2. marca como lida qualquer notificação com mais de 30 dias;
--   3. apaga as lidas com mais de 90 dias.
-- =============================================================================

create or replace function public.notificacoes_limpeza()
returns jsonb language plpgsql security definer
set search_path = public as $fn$
declare n1 int; n2 int; n3 int; n4 int;
begin
  update notificacoes n set lida = true, lida_em = now()
   where not n.lida
     and n.tipo in ('visita_flagueada', 'visita_reenviada', 'admin_visita_auto_fechada')
     and not exists (
       select 1 from visitas v
        where v.id::text = coalesce(n.objeto_id, substring(n.link from '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'))
          and v.status not in ('aprovada_pos_revisao', 'cancelada'));
  get diagnostics n1 = row_count;

  update notificacoes n set lida = true, lida_em = now()
   where not n.lida and n.tipo = 'instituicao_sugerida'
     and not exists (select 1 from instituicoes i
                      where i.id::text = n.objeto_id and i.pendente_aprovacao and i.ativo);
  get diagnostics n2 = row_count;

  update notificacoes set lida = true, lida_em = now()
   where not lida and criado_em < now() - interval '30 days';
  get diagnostics n3 = row_count;

  delete from notificacoes
   where lida and coalesce(lida_em, criado_em) < now() - interval '90 days'
     and criado_em < now() - interval '90 days';
  get diagnostics n4 = row_count;

  return jsonb_build_object('visitas_resolvidas', n1, 'instituicoes_resolvidas', n2,
                            'antigas_lidas', n3, 'apagadas', n4);
end $fn$;
revoke all on function public.notificacoes_limpeza() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'limpar-notificacoes';
select cron.schedule('limpar-notificacoes', '0 6 * * *', $$select public.notificacoes_limpeza()$$);

-- APLICADO em 24/09/2026 e rodado uma vez na hora.
