-- =============================================================================
-- Sprint 9.32.466 — senha guardada com bcrypt (salt + custo) no servidor
-- =============================================================================
-- ANTES: o banco guardava SHA-256 puro da senha, sem salt. Quem obtivesse os
--        hashes quebrava a maioria das senhas por dicionário em minutos, e duas
--        pessoas com a mesma senha tinham o mesmo hash.
-- AGORA: o app continua mandando o SHA-256 (nada muda no navegador), mas o
--        banco guarda bcrypt(SHA-256) com salt próprio por pessoa e custo 10.
--        Quebrar por dicionário fica milhares de vezes mais lento.
--
--  - gatilho usuarios_senha_bcrypt: qualquer gravação de senha_hash que ainda
--    não seja bcrypt vira bcrypt (cadastro, troca de senha, recuperação).
--  - _senha_confere: compara bcrypt; aceita o formato antigo só por segurança.
--  - autenticar: usa _senha_confere + trava de 10 erros em 15 min por CPF.
--  - conferir_senha: usa _senha_confere e só confere a senha da PRÓPRIA pessoa
--    (antes qualquer um podia testar senha de qualquer id, sem limite).
--  - Todas as senhas existentes são convertidas agora, de uma vez.
-- =============================================================================

create or replace function public._senha_confere(p_guardado text, p_hash text)
returns boolean language sql stable set search_path = public, extensions as $fn$
  select case
    when p_guardado is null or coalesce(p_hash, '') = '' then false
    when p_guardado ~ '^\$2[aby]\$' then extensions.crypt(p_hash, p_guardado) = p_guardado
    else p_guardado = p_hash
  end;
$fn$;
revoke all on function public._senha_confere(text, text) from public, anon, authenticated;

create or replace function public.usuarios_senha_bcrypt()
returns trigger language plpgsql security definer set search_path = public, extensions as $fn$
begin
  if new.senha_hash is not null and new.senha_hash !~ '^\$2[aby]\$' then
    new.senha_hash := extensions.crypt(new.senha_hash, extensions.gen_salt('bf', 10));
  end if;
  return new;
end $fn$;
drop trigger if exists usuarios_senha_bcrypt on public.usuarios;
create trigger usuarios_senha_bcrypt
  before insert or update of senha_hash on public.usuarios
  for each row execute function public.usuarios_senha_bcrypt();

-- Tentativas erradas de login (para travar chute de senha)
create table if not exists public.login_falhas (
  cpf text not null,
  em  timestamptz not null default now()
);
create index if not exists login_falhas_cpf_em on public.login_falhas (cpf, em);
alter table public.login_falhas enable row level security;
revoke all on public.login_falhas from anon, authenticated;

create or replace function public.autenticar(p_cpf text, p_senha_hash text)
returns jsonb language plpgsql security definer
set search_path to 'public', 'pg_temp' as $function$
declare
  v_user jsonb; v_id uuid; v_guardado text;
begin
  delete from login_falhas where em < now() - interval '1 day';
  if (select count(*) from login_falhas
       where cpf = p_cpf and em > now() - interval '15 minutes') >= 10 then
    raise exception 'Muitas tentativas erradas. Aguarde 15 minutos e tente de novo.';
  end if;

  select u.id, u.senha_hash into v_id, v_guardado
    from usuarios u where u.cpf = p_cpf limit 1;

  if v_id is null or not public._senha_confere(v_guardado, p_senha_hash) then
    insert into login_falhas (cpf) values (left(coalesce(p_cpf, ''), 20));
    -- Mesma resposta para CPF inexistente e senha errada.
    return null;
  end if;

  select to_jsonb(u) - 'senha_hash' into v_user from usuarios u where u.id = v_id;
  return v_user;
end $function$;

create or replace function public.conferir_senha(p_usuario_id uuid, p_senha_hash text)
returns boolean language sql security definer
set search_path to 'public', 'pg_temp' as $function$
  select coalesce((
    select public._senha_confere(senha_hash, p_senha_hash)
      from usuarios
     where id = p_usuario_id and p_usuario_id = public.app_usuario_id()
  ), false);
$function$;

-- Converte todas as senhas antigas agora (o gatilho faz o bcrypt)
update public.usuarios set senha_hash = senha_hash
 where senha_hash is not null and senha_hash !~ '^\$2[aby]\$';

-- APLICADO em 24/09/2026 pelo SQL Editor, depois de testado em transação desfeita.
