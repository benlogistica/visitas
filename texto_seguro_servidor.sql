-- =============================================================================
-- Sprint 9.32.466 — texto digitado no app não vira código na tela de ninguém
-- =============================================================================
-- O app monta as telas juntando texto do banco dentro do HTML. Um nome de
-- instituição, observação ou motivo com <script>, <img onerror=...> ou uma aspa
-- no lugar certo rodaria código na tela de quem abrisse (inclusive do admin).
--
-- Em vez de caçar as centenas de pontos do app, o banco neutraliza na entrada:
--   * texto comum: < > " ' viram ‹ › ” ’ (parecidos, mas inofensivos)
--   * visitas.resumo (tem formatação do editor): mantém só as tags de
--     formatação — br, div, span, p, b, strong, i, em, u, ul, ol, li — SEM
--     atributos (some style, onclick, onerror...). Qualquer outra tag vira texto.
--   * coluna "link": só aceita caminho interno ("/..." ou "#/..."), senão fica vazio
--   * não mexe em colunas técnicas: *url*, *path*, *arquivo*, *storage*, *hash*,
--     *token*, id e *_id.
-- Vale para o que for gravado daqui para frente (os dados atuais foram
-- conferidos: não havia nada perigoso).
-- =============================================================================

create or replace function public._texto_seguro(p text)
returns text language sql immutable as $fn$
  select translate(p, '<>"''', '‹›”’');
$fn$;

create or replace function public._html_seguro(p text)
returns text language plpgsql immutable as $fn$
declare s text := p;
begin
  if s is null then return null; end if;
  s := regexp_replace(s,
         '<\s*(/?)\s*(br|div|span|p|b|strong|i|em|u|ul|ol|li)\M[^<>]*>',
         chr(1) || '\1\2' || chr(2), 'gi');
  s := translate(s, '<>"''', '‹›”’');
  s := replace(replace(s, chr(1), '<'), chr(2), '>');
  return s;
end $fn$;

create or replace function public.tg_texto_seguro()
returns trigger language plpgsql as $fn$
declare
  j jsonb := to_jsonb(new);
  k text; v jsonb; t text; novo text;
  mudou boolean := false;
begin
  for k, v in select * from jsonb_each(j) loop
    continue when jsonb_typeof(v) <> 'string';
    continue when k ~ '(url|path|arquivo|storage|hash|token)' or k = 'id' or k ~ '_id$';
    t := v #>> '{}';
    if k = 'link' then
      novo := case when t ~ '^[#/][^"''<>[:space:]]*$' then t else null end;
    elsif k = any (tg_argv) then
      novo := public._html_seguro(t);
    elsif t ~ '[<>"'']' then
      novo := public._texto_seguro(t);
    else
      continue;
    end if;
    if novo is distinct from t then
      j := jsonb_set(j, array[k], coalesce(to_jsonb(novo), 'null'::jsonb));
      mudou := true;
    end if;
  end loop;
  if mudou then new := jsonb_populate_record(new, j); end if;
  return new;
end $fn$;

do $do$
declare t text;
begin
  foreach t in array array[
    'usuarios','instituicoes','profissionais','visitas_objetivos','visitas_profissionais',
    'objetivos_visita','funil_indicacoes','funil_itens','solicitacoes_reabertura',
    'visita_anexos','itens_padronizados','notificacoes','visitas_agendadas',
    'categorias_profissionais'] loop
    execute format('drop trigger if exists zz_texto_seguro on public.%I', t);
    execute format('create trigger zz_texto_seguro before insert or update on public.%I
                    for each row execute function public.tg_texto_seguro()', t);
  end loop;
  -- visitas: o resumo tem formatação do editor
  execute 'drop trigger if exists zz_texto_seguro on public.visitas';
  execute 'create trigger zz_texto_seguro before insert or update on public.visitas
           for each row execute function public.tg_texto_seguro(''resumo'')';
end $do$;

-- APLICADO em 24/09/2026 pelo SQL Editor, depois de testado em transação desfeita.
