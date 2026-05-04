// =============================================================================
// Edge Function: notif-to-email   |   versão 9.32.235
// =============================================================================
// Source-of-truth do código que está deployado no Supabase
//   (Edge Functions → notif-to-email → Via Editor).
//
// COMO FUNCIONA:
//   1. Database Webhook do Supabase escuta INSERTs na tabela `notificacoes`
//      e faz POST aqui com payload `{ type, table, record, old_record }`.
//   2. Esta função busca:
//        a) o user destino (email, nome) via service_role
//        b) gera o template B&N apropriado pro tipo de notificação
//        c) chama a Edge Function `send-email` (que já existe) pra enviar
//   3. Falha sai silenciosa pra não bloquear inserção da notificação.
//
// IMPORTANTE — TODOS OS ADMINS:
//   Os triggers SQL já existentes (migrations 19/20/25/26) criam 1 linha de
//   notificação POR DESTINATÁRIO. Então pra notificações tipo admin
//   (conta_pendente, instituicao_sugerida, etc.), cada admin tem a própria
//   linha — e cada um recebe seu próprio e-mail. Não precisa replicar aqui.
//
// SETUP NO SUPABASE:
//   1. Database → Webhooks → Create new hook
//      Name: notif_email_on_insert
//      Table: public.notificacoes
//      Events: ✓ Insert
//      Type: Supabase Edge Function
//      Function: notif-to-email
//      Method: POST
//      HTTP Headers: (deixa default — Supabase passa o JWT da request)
//   2. Save.
//
// SECRETS NECESSÁRIOS (Edge Functions → Manage secrets):
//   SUPABASE_URL          — URL do projeto (já existe)
//   SUPABASE_SERVICE_ROLE_KEY  — service role key pra ler usuarios sem RLS
//   SUPABASE_ANON_KEY     — pra chamar send-email
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Tipos: cada um vira título + corpo do e-mail
const TIPO_TEMPLATE: Record<string, { titulo: string; cta?: string; }> = {
  // --- Pro nutri ---
  visita_aprovada_pos_revisao: { titulo: "Visita aprovada", cta: "Ver visita" },
  instituicao_aprovada:        { titulo: "Instituição aprovada" },
  instituicao_rejeitada:       { titulo: "Instituição rejeitada" },
  objetivo_aprovado:           { titulo: "Objetivo aprovado" },
  objetivo_rejeitado:          { titulo: "Objetivo rejeitado" },
  conta_aprovada:              { titulo: "Conta aprovada", cta: "Acessar plataforma" },
  visita_devolvida_revisao:    { titulo: "Visita devolvida pra revisão", cta: "Revisar visita" },
  agendamento_atribuido:       { titulo: "Novo agendamento atribuído", cta: "Ver agenda" },
  agendamento_sugerido:        { titulo: "Agendamento sugerido", cta: "Aceitar ou recusar" },
  categoria_aprovada:          { titulo: "Categoria profissional aprovada" }, // 9.32.255
  // 9.32.261: avisos de visita aberta (Tipo A — só sininho nas 2h e 4h, sem template)
  // 6h e auto-fechado SIM têm template (mandam e-mail)
  visita_aviso_6h_final:       { titulo: "Último aviso: visita aberta há 6 horas", cta: "Encerrar agora" },
  visita_auto_fechada:         { titulo: "Visita encerrada automaticamente", cta: "Ver rascunho" },

  // --- Pro admin ---
  conta_pendente:              { titulo: "Novo cadastro aguardando aprovação", cta: "Revisar cadastro" },
  instituicao_sugerida:        { titulo: "Nova instituição sugerida", cta: "Aprovar instituição" },
  objetivo_sugerido:           { titulo: "Novo objetivo sugerido", cta: "Aprovar objetivo" },
  categoria_sugerida:          { titulo: "Nova categoria profissional sugerida", cta: "Aprovar categoria" }, // 9.32.255
  visita_reenviada:            { titulo: "Visita reenviada após revisão", cta: "Ver fila de revisão" },
  visita_flagueada:            { titulo: "Visita com divergências", cta: "Ver fila de revisão" },
  agendamento_aceito:          { titulo: "Agendamento aceito pelo profissional" },
  agendamento_recusado:        { titulo: "Agendamento recusado pelo profissional" },
  admin_visita_auto_fechada:   { titulo: "Visita auto-fechada pelo sistema", cta: "Ver visita" }, // 9.32.261
};

const SITE_URL = "https://www.benlogistica.com.br";

// Minifica HTML (mesma estratégia da send-email — evita =20 em quoted-printable)
function minifyEmailHtml(html: string): string {
  return (html || "")
    .replace(/\r/g, "")
    .replace(/\n[ \t]*/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/>\s+</g, "><")
    .trim();
}

// Template oficial B&N (mesmo do front)
function templateBN(opts: { titulo: string; corpo: string; cta?: string; ctaUrl?: string; rodape?: string }): string {
  const { titulo, corpo, cta, ctaUrl, rodape } = opts;
  const ctaHtml = (cta && ctaUrl)
    ? `<div style="margin:28px 0;text-align:center;"><a href="${ctaUrl}" style="display:inline-block;background:#8BC63F;color:#0A1F5C;font-weight:700;padding:14px 32px;border-radius:10px;text-decoration:none;font-size:15px;">${cta}</a></div>`
    : "";
  const rodapeHtml = rodape || "Você está recebendo este e-mail porque é usuário da plataforma B&N Logística.";
  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${titulo}</title></head>
<body style="margin:0;padding:0;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;color:#0A1F5C;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:32px 16px;">
    <tr><td align="center">
      <table role="presentation" width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 6px 24px rgba(10,31,92,0.08);">
        <tr><td style="background:#0A1F5C;padding:24px 32px;text-align:left;">
          <div style="font-size:13px;letter-spacing:1.4px;color:#8BC63F;font-weight:700;text-transform:uppercase;">B&amp;N Logística</div>
          <div style="font-size:22px;font-weight:700;color:#fff;margin-top:6px;">${titulo}</div>
        </td></tr>
        <tr><td style="padding:32px;font-size:15px;line-height:1.6;color:#0A1F5C;">
          ${corpo}
          ${ctaHtml}
        </td></tr>
        <tr><td style="padding:20px 32px;background:#f9fafb;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;line-height:1.5;">
          ${rodapeHtml}
          <br><br>Em caso de dúvidas, entre em contato: <a href="mailto:atendimento@benlogistica.com.br" style="color:#0A1F5C;">atendimento@benlogistica.com.br</a>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

// 9.32.236: envia e-mail DIRETO via SMTP (igual send-email faz) — evita problema de
// verify_jwt em Edge Functions chamadas via Database Webhook.
async function dispararEmail(to: string, subject: string, html: string, text: string) {
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
  try {
    await client.send({
      from: `${Deno.env.get("SMTP_FROM_NAME") || "B&N Logística"} <${
        Deno.env.get("SMTP_FROM") || Deno.env.get("SMTP_USER")
      }>`,
      to,
      subject,
      content: text || "Veja em HTML.",
      html: minifyEmailHtml(html) || undefined,
    });
  } finally {
    await client.close();
  }
}

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const payload = await req.json();
    const record = payload?.record;
    if (!record || !record.user_id || !record.tipo) {
      return new Response(JSON.stringify({ ok: true, skipped: "sem record/user_id/tipo" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Busca o user destino via service_role (precisa por causa do RLS)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    );
    const { data: user, error: errUser } = await supabase
      .from("usuarios")
      .select("id, nome, email, status")
      .eq("id", record.user_id)
      .maybeSingle();

    if (errUser) throw new Error("Erro ao buscar user: " + errUser.message);
    if (!user) {
      return new Response(JSON.stringify({ ok: true, skipped: "user não encontrado" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!user.email) {
      return new Response(JSON.stringify({ ok: true, skipped: "user sem email" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (user.status !== "ativo") {
      return new Response(JSON.stringify({ ok: true, skipped: "user inativo/bloqueado/pendente" }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. Monta o e-mail conforme o tipo
    const meta = TIPO_TEMPLATE[record.tipo];
    if (!meta) {
      // Tipo desconhecido — pula sem erro
      return new Response(JSON.stringify({ ok: true, skipped: `tipo "${record.tipo}" sem template` }), {
        status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const primeiroNome = (user.nome || "").trim().split(" ")[0] || "Usuário";
    const tituloEmail = `[B&N Logistica] ${meta.titulo}`;
    const corpoTxt = `${record.titulo || meta.titulo}.

${record.mensagem || ""}`.trim();
    const corpoHtml = `
      <p>Olá, <strong>${primeiroNome}</strong>!</p>
      <p>${(record.titulo || meta.titulo).replace(/</g, "&lt;")}.</p>
      ${record.mensagem ? `<p style="background:#f9fafb;border-left:3px solid #8BC63F;padding:12px 16px;border-radius:0 8px 8px 0;color:#374151;">${record.mensagem.replace(/</g, "&lt;")}</p>` : ""}
      <p style="font-size:13px;color:#6b7280;margin-top:18px;">Acesse a plataforma para ver mais detalhes.</p>
    `;
    const ctaUrl = record.link
      ? (record.link.startsWith("http") ? record.link : `${SITE_URL}/${record.link.replace(/^\//, "")}`)
      : SITE_URL;

    const html = templateBN({
      titulo: meta.titulo,
      corpo: corpoHtml,
      cta: meta.cta,
      ctaUrl,
    });

    await dispararEmail(user.email, tituloEmail, html, `Olá ${primeiroNome}!\n\n${corpoTxt}\n\nAcesse: ${SITE_URL}`);

    return new Response(JSON.stringify({ ok: true, sent_to: user.email, tipo: record.tipo }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("notif-to-email error:", e);
    // Retorna 200 pra não bloquear o webhook (Supabase pode reenviar em loop)
    return new Response(JSON.stringify({ ok: false, error: String((e as Error)?.message || e) }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
