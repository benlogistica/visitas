-- =============================================================================
-- visita_anexos.sql   |   sprint 9.32.211
-- =============================================================================
-- Setup completo pra anexos em relatórios de visita:
--   1. Bucket 'visita-anexos' (privado, 10 MB max, MIME whitelist)
--   2. Tabela 'visita_anexos' (metadata dos arquivos)
--   3. Trigger pra enforçar limite de 5 anexos por visita
--   4. RLS policies (abertas — projeto usa auth custom, não Supabase Auth)
--   5. Storage policies (idem)
--
-- COMO RODAR:
--   1. Abra o painel do Supabase → SQL Editor → New query
--   2. Cole o conteúdo INTEIRO deste arquivo
--   3. Clique em RUN
--   4. Confira que não houve erro (ignore avisos "already exists" ao re-rodar)
--
-- AVISO DE SEGURANÇA:
--   Como o projeto B&N usa autenticação custom (CPF + senha em tabela 'usuarios')
--   em vez de Supabase Auth (JWT), as RLS policies aqui são "abertas" — qualquer
--   request com a anon key consegue ler/escrever. A segurança real fica no front
--   (validação client-side + UX que só mostra os anexos da visita atual).
--
--   Pra hardening futuro, considerar:
--     - Migrar pra Supabase Auth (RLS proper com auth.uid())
--     - Edge Function 'upload-anexo' que valida user via header e usa service_role
--     - Auditoria no banco (tabela log_anexos com IP/user-agent)
-- =============================================================================


-- =============================================================================
-- 1. BUCKET
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'visita-anexos',
  'visita-anexos',
  false,                      -- privado: download só via signed URL
  10485760,                   -- 10 MB por arquivo
  ARRAY[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;


-- =============================================================================
-- 2. TABELA visita_anexos
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.visita_anexos (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  visita_id       uuid NOT NULL REFERENCES public.visitas(id) ON DELETE CASCADE,
  nome_original   text NOT NULL,
  mime_type       text NOT NULL,
  tamanho_bytes   bigint NOT NULL CHECK (tamanho_bytes > 0 AND tamanho_bytes <= 10485760),
  caminho_storage text NOT NULL UNIQUE,
  enviado_por     uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  enviado_em      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.visita_anexos IS
  'Metadata de arquivos anexados em relatórios de visita. O conteúdo binário fica no bucket Storage visita-anexos.';

COMMENT ON COLUMN public.visita_anexos.caminho_storage IS
  'Path do arquivo dentro do bucket visita-anexos. Formato: <visita_id>/<timestamp>_<nome_seguro>';

CREATE INDEX IF NOT EXISTS visita_anexos_visita_id_idx
  ON public.visita_anexos(visita_id);

CREATE INDEX IF NOT EXISTS visita_anexos_enviado_por_idx
  ON public.visita_anexos(enviado_por);


-- =============================================================================
-- 3. TRIGGER — limite de 5 anexos por visita
-- =============================================================================

CREATE OR REPLACE FUNCTION public.check_max_anexos_visita()
RETURNS TRIGGER AS $$
DECLARE
  qtd INT;
BEGIN
  SELECT COUNT(*) INTO qtd
  FROM public.visita_anexos
  WHERE visita_id = NEW.visita_id;

  IF qtd >= 5 THEN
    RAISE EXCEPTION 'Limite de 5 anexos por visita atingido (visita_id=%)', NEW.visita_id
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_max_anexos ON public.visita_anexos;

CREATE TRIGGER trg_check_max_anexos
  BEFORE INSERT ON public.visita_anexos
  FOR EACH ROW
  EXECUTE FUNCTION public.check_max_anexos_visita();


-- =============================================================================
-- 4. RLS — tabela visita_anexos
-- =============================================================================
-- Como o projeto usa auth custom (não JWT), as policies são abertas.
-- A segurança real fica no front + validação client-side.

ALTER TABLE public.visita_anexos ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "open_select_visita_anexos" ON public.visita_anexos;
CREATE POLICY "open_select_visita_anexos"
  ON public.visita_anexos
  FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "open_insert_visita_anexos" ON public.visita_anexos;
CREATE POLICY "open_insert_visita_anexos"
  ON public.visita_anexos
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "open_delete_visita_anexos" ON public.visita_anexos;
CREATE POLICY "open_delete_visita_anexos"
  ON public.visita_anexos
  FOR DELETE
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "open_update_visita_anexos" ON public.visita_anexos;
CREATE POLICY "open_update_visita_anexos"
  ON public.visita_anexos
  FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);


-- =============================================================================
-- 5. STORAGE policies — bucket visita-anexos
-- =============================================================================

DROP POLICY IF EXISTS "open_select_storage_visita_anexos" ON storage.objects;
CREATE POLICY "open_select_storage_visita_anexos"
  ON storage.objects
  FOR SELECT
  TO anon, authenticated
  USING (bucket_id = 'visita-anexos');

DROP POLICY IF EXISTS "open_insert_storage_visita_anexos" ON storage.objects;
CREATE POLICY "open_insert_storage_visita_anexos"
  ON storage.objects
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (bucket_id = 'visita-anexos');

DROP POLICY IF EXISTS "open_delete_storage_visita_anexos" ON storage.objects;
CREATE POLICY "open_delete_storage_visita_anexos"
  ON storage.objects
  FOR DELETE
  TO anon, authenticated
  USING (bucket_id = 'visita-anexos');


-- =============================================================================
-- VERIFICAÇÃO PÓS-EXECUÇÃO (rode estes SELECTs depois pra confirmar)
-- =============================================================================
-- SELECT * FROM storage.buckets WHERE id = 'visita-anexos';
-- SELECT * FROM information_schema.tables WHERE table_name = 'visita_anexos';
-- SELECT policyname FROM pg_policies WHERE tablename = 'visita_anexos';
-- SELECT policyname FROM pg_policies WHERE tablename = 'objects' AND schemaname = 'storage'
--   AND policyname LIKE '%visita_anexos%';
