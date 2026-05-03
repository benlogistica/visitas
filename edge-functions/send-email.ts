// =============================================================================
// Edge Function: send-email   |   versão 9.32.204
// =============================================================================
// Source-of-truth do código que está deployado no Supabase
//   (Edge Functions → send-email → Via Editor).
//
// Sprint 9.32.204 (fix do "=20"):
//   - O denomailer envia HTML em quoted-printable. Quando o HTML que chega aqui
//     tem trailing whitespace ou indentação de template literal (ex.: `\n        <p>`),
//     esses espaços em fim de linha são codificados como "=20" + soft line break.
//     Em alguns gateways SMTP do provedor emailemnuvem.com.br (LDVnet), o soft
//     line break é removido mas o "=20" sobrevive literal — vazando no corpo do
//     e-mail renderizado.
//
//   - Solução: minificar o HTML server-side antes de passar para o denomailer.
//     Remove \n + indentação após e espaços entre tags. HTML é resiliente a
//     remoção de whitespace fora de <pre>/<textarea>, então é seguro.
//
// Secrets esperados (configurados em Edge Functions → Manage secrets):
//   SMTP_HOST=smtp.emailemnuvem.com.br
//   SMTP_PORT=465
//   SMTP_USER=atendimento@benlogistica.com.br
//   SMTP_PASS=<senha>
//   SMTP_FROM_NAME=B&N Logística
// =============================================================================

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

/**
 * Minifica HTML para evitar que trailing whitespace e indentação virem "=20"
 * literais no e-mail renderizado (problema do quoted-printable + gateway SMTP).
 *
 * - Remove CRs.
 * - Remove \n seguido de indentação.
 * - Colapsa runs de espaços em um único espaço.
 * - Remove espaços entre tags (>< sem nada no meio).
 * - Faz trim das pontas.
 *
 * NÃO usar dentro de <pre> ou <textarea> — mas e-mails B&N não usam essas tags.
 */
function minifyEmailHtml(html: string): string {
  return (html || "")
    .replace(/\r/g, "")
    .replace(/\n[ \t]*/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/>\s+</g, "><")
    .trim();
}

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { to, subject, html, text } = await req.json();
    if (!to || !subject || (!html && !text)) {
      return new Response(
        JSON.stringify({ error: "Faltam: to, subject, html|text" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 9.32.204: minifica o HTML antes de enviar (fix do =20)
    const htmlClean = html ? minifyEmailHtml(html) : undefined;

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
      to,
      subject,
      content: text || "Veja em HTML.",
      html: htmlClean || undefined,
    });

    await client.close();

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("send-email error:", e);
    return new Response(
      JSON.stringify({ error: String((e as Error)?.message || e) }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});
