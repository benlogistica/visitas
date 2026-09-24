// =============================================================================
// Edge Function: send-email   |   versão 9.32.464
// =============================================================================
// Source-of-truth do código que está deployado no Supabase
//   (Edge Functions → send-email → Code).
//
// Sprint 9.32.464 — FECHADA:
//   Antes aceitava {to, subject, html} de qualquer um que tivesse a chave
//   pública (que está no index.html) — dava pra usar o SMTP da B&N para mandar
//   qualquer e-mail para qualquer endereço.
//   Agora só aceita {id}. A mensagem mora na tabela public.email_fila, que só
//   o banco escreve (funções _email_enfileirar, email_enviar_admin,
//   email_cadastro_recebido, recuperacao_solicitar — ver email_fila_servidor.sql).
//   Um id inventado não acha nada; um id real já enviado não reenvia.
//
// Sprint 9.32.204 (fix do "=20"): o HTML é minificado antes de ir ao denomailer.
//
// Secrets (Edge Functions → Secrets):
//   SMTP_HOST, SMTP_PORT, SMTP_USER, SMTP_PASS, SMTP_FROM_NAME
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (já vêm por padrão)
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

function minifyEmailHtml(html: string): string {
  return (html || "")
    .replace(/\r/g, "")
    .replace(/\n[ \t]*/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/>\s+</g, "><")
    .trim();
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function resposta(obj: unknown, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return resposta({ error: "method" }, 405);

  let id = "";
  try {
    const body = await req.json();
    id = String(body?.id || "");
  } catch (_) { /* corpo inválido */ }
  if (!UUID_RE.test(id)) return resposta({ error: "id" }, 400);

  const db = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Reserva a mensagem: só pega se ainda estiver pendente e for recente.
  // Duas chamadas com o mesmo id não mandam o e-mail duas vezes.
  const umaHoraAtras = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const { data: msg, error: errClaim } = await db
    .from("email_fila")
    .update({ status: "enviando" })
    .eq("id", id)
    .eq("status", "pendente")
    .gt("criado_em", umaHoraAtras)
    .select("id, para, assunto, html, texto, origem")
    .maybeSingle();

  if (errClaim) {
    console.error("send-email: erro ao ler a fila:", errClaim.message);
    return resposta({ error: "fila" }, 500);
  }
  if (!msg) return resposta({ ok: true, skipped: true });

  try {
    const client = new SMTPClient({
      connection: {
        hostname: Deno.env.get("SMTP_HOST")!,
        port: Number(Deno.env.get("SMTP_PORT") || "465"),
        tls: true,
        auth: {
          username: Deno.env.get("SMTP_USER")!,
          password: Deno.env.get("SMTP_PASS")!,
        },
      },
    });
    await client.send({
      from: `${Deno.env.get("SMTP_FROM_NAME") || "B&N Logística"} <${
        Deno.env.get("SMTP_FROM") || Deno.env.get("SMTP_USER")
      }>`,
      to: msg.para,
      subject: msg.assunto,
      content: msg.texto || "Veja em HTML.",
      html: msg.html ? minifyEmailHtml(msg.html) : undefined,
    });
    await client.close();

    // Enviado: apaga o conteúdo (o de recuperação tem o código de 6 dígitos).
    await db.from("email_fila").update({
      status: "enviado",
      enviado_em: new Date().toISOString(),
      html: null,
      texto: null,
      assunto: String(msg.origem || "").startsWith("recuperacao:") ? "[recuperação de senha]" : msg.assunto,
    }).eq("id", msg.id);

    return resposta({ ok: true });
  } catch (e) {
    const erro = String((e as Error)?.message || e).slice(0, 500);
    console.error("send-email: falha no SMTP:", erro);
    await db.from("email_fila").update({ status: "erro", erro }).eq("id", msg.id);
    return resposta({ error: "smtp" }, 500);
  }
});
