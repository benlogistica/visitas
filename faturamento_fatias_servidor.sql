-- =============================================================================
-- Sprint 9.32.468 — nutricionista recebe só o faturamento dos próprios hospitais
-- =============================================================================
-- ANTES: a tela de Performance da nutricionista precisava do arquivo INTEIRO de
--        faturamento; a chave ia para qualquer conta ativa e, com ela, dava para
--        abrir o faturamento de todos os clientes.
-- AGORA: - faturamento_chave() (arquivo inteiro) só para ADMIN.
--        - cada cliente PJ tem um arquivo cifrado próprio em fat_cli/ (gerado pelo
--          atualizar_index.py). Nome e chave saem de HMAC da chave mestra.
--        - faturamento_chaves_perf(usuario) entrega só as chaves dos CNPJs das
--          instituições que aquela pessoa visitou. Nutricionista só pede a sua;
--          admin pode pedir de qualquer um (simulação).
-- =============================================================================

create or replace function public.faturamento_chave()
returns text language plpgsql stable security definer
set search_path = public as $fn$
begin
  if not coalesce(app_eh_admin(), false) then
    return null;
  end if;
  return (select valor from app_segredos where nome = 'faturamento_chave');
end $fn$;
revoke all on function public.faturamento_chave() from public;
grant execute on function public.faturamento_chave() to anon, authenticated;

create or replace function public.faturamento_chaves_perf(p_usuario_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public, extensions as $fn$
declare
  v_eu uuid := app_usuario_id();
  v_mestra bytea;
  v_clientes jsonb;
begin
  if v_eu is null or not exists (select 1 from usuarios where id = v_eu and status = 'ativo'
                                   and coalesce(arquivado, false) = false) then
    return null;
  end if;
  if p_usuario_id is distinct from v_eu and not coalesce(app_eh_admin(), false) then
    return null;
  end if;
  v_mestra := decode((select valor from app_segredos where nome = 'faturamento_chave'), 'base64');

  select coalesce(jsonb_agg(jsonb_build_object(
           'cnpj',  c,
           'id',    left(encode(extensions.hmac(convert_to('id:' || c, 'UTF8'), v_mestra, 'sha256'), 'hex'), 24),
           'chave', encode(extensions.hmac(convert_to('k:' || c, 'UTF8'), v_mestra, 'sha256'), 'base64'))), '[]'::jsonb)
    into v_clientes
    from (select distinct regexp_replace(i.cnpj, '\D', '', 'g') as c
            from visitas v join instituicoes i on i.id = v.instituicao_id
           where v.nutricionista_id = p_usuario_id
             and length(regexp_replace(coalesce(i.cnpj, ''), '\D', '', 'g')) in (11, 14)) x;  -- 9.32.472: CPF também

  return jsonb_build_object(
    'comum', jsonb_build_object(
      'id',    left(encode(extensions.hmac(convert_to('id:comum', 'UTF8'), v_mestra, 'sha256'), 'hex'), 24),
      'chave', encode(extensions.hmac(convert_to('k:comum', 'UTF8'), v_mestra, 'sha256'), 'base64')),
    'clientes', v_clientes);
end $fn$;
revoke all on function public.faturamento_chaves_perf(uuid) from public;
grant execute on function public.faturamento_chaves_perf(uuid) to anon, authenticated;

-- 9.32.472: ids (HMAC) das instituições pessoa física, para o atualizar_index.py
-- gerar só as fatias de CPF que interessam (não as 11 mil pessoas físicas).
create or replace function public.faturamento_ids_pf()
returns text[] language sql stable security definer set search_path = public, extensions as $fn$
  select coalesce(array_agg(distinct left(encode(extensions.hmac(convert_to('id:' || c, 'UTF8'),
           decode((select valor from app_segredos where nome = 'faturamento_chave'), 'base64'), 'sha256'), 'hex'), 24)), '{}')
    from (select regexp_replace(cnpj, '\D', '', 'g') c from instituicoes where ativo) x
   where length(c) = 11;
$fn$;
revoke all on function public.faturamento_ids_pf() from public;
grant execute on function public.faturamento_ids_pf() to anon, authenticated;

-- APLICADO em 24/09/2026 pelo SQL Editor.
