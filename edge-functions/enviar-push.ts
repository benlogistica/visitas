// =============================================================================
// Edge Function: enviar-push   |   versão 9.32.420
// =============================================================================
// O PROBLEMA QUE ELA RESOLVE
// 189 das 1.004 visitas ficaram sem check-out. A função verificar-visitas-abertas
// já criava avisos em 2h, 4h e 6h — mas só dentro do app. E quem esqueceu o
// check-out, por definição, não abriu o app pra ver o aviso.
//
// Esta função pega os avisos recém-criados e entrega como notificação na tela
// do celular, mesmo com o app fechado.
//
// COMO RODA
//   pg_cron chama a cada 5 minutos (ver supabase/push_cron.sql).
//   Só envia avisos ainda não enviados (notificacoes.push_enviado_em IS NULL)
//   e criados na última hora — aviso velho não vira notificação atrasada.
//
// SECRETS NECESSÁRIOS
//   SUPABASE_URL               — já existe
//   SUPABASE_SERVICE_ROLE_KEY  — já existe
//   VAPID_PRIVATE_KEY          — CRIAR (ver VAPID_CHAVES.txt)
//   VAPID_SUBJECT              — CRIAR: mailto:atendimento@benlogistica.com.br
//
// DEPLOY
//   Verify JWT = OFF (quem chama é o cron, com service_role — não um usuário)
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const VAPID_PUBLIC_KEY =
  "BFB4VDUQGmHOmeoZZ5d7Mks4XXByPqIte-ijLJaDZldcSljOrlkdTLcOwPf7rKe1udKnC8fFontjR4oFq_OPhNc";

const SITE_URL = "https://www.benlogistica.com.br";

// Só estes tipos viram notificação no celular. Aviso de check-out esquecido é
// urgente e sensível ao tempo; o resto pode esperar a pessoa abrir o app —
// senão o celular vira uma máquina de apitar e a pessoa desliga tudo.
// Nomes conferidos contra o banco em 12/09/2026 — errar aqui faria a função
// rodar em silêncio, sem nunca enviar nada.
const TIPOS_QUE_VIRAM_PUSH = [
  "visita_aviso_2h",
  "visita_aviso_4h",
  "visita_aviso_6h_final",
  "visita_auto_fechada",
];

const MAX_FALHAS = 5;        // depois disso, a inscrição é descartada
const JANELA_MINUTOS = 60;   // ignora avisos mais velhos que isto

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const privada = Deno.env.get("VAPID_PRIVATE_KEY");
  const assunto = Deno.env.get("VAPID_SUBJECT") || "mailto:atendimento@benlogistica.com.br";

  if (!privada) {
    // Falha clara: sem a chave não há o que fazer, e silêncio aqui viraria
    // "as notificações simplesmente não chegam" — difícil de diagnosticar.
    return new Response(
      JSON.stringify({ erro: "VAPID_PRIVATE_KEY não configurada nos secrets do projeto." }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }

  webpush.setVapidDetails(assunto, VAPID_PUBLIC_KEY, privada);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  const stats = {
    avisos: 0,
    enviados: 0,
    sem_aparelho: 0,
    inscricoes_removidas: 0,
    erros: [] as string[],
  };

  try {
    const desde = new Date(Date.now() - JANELA_MINUTOS * 60_000).toISOString();

    const { data: avisos, error: errAvisos } = await supabase
      .from("notificacoes")
      .select("id, user_id, tipo, titulo, mensagem, link, criado_em")
      .is("push_enviado_em", null)
      .in("tipo", TIPOS_QUE_VIRAM_PUSH)
      .gte("criado_em", desde)
      .order("criado_em", { ascending: true })
      .limit(200);

    if (errAvisos) throw new Error("ler notificacoes: " + errAvisos.message);

    stats.avisos = (avisos || []).length;
    if (stats.avisos === 0) {
      return new Response(JSON.stringify({ ok: true, ...stats }), {
        headers: { ...cors, "Content-Type": "application/json" },
      });
    }

    // Uma consulta só para todos os aparelhos envolvidos.
    const usuarios = [...new Set(avisos!.map((a) => a.user_id).filter(Boolean))];
    const { data: inscricoes, error: errIns } = await supabase
      .from("push_inscricoes")
      .select("id, usuario_id, endpoint, p256dh, auth, falhas")
      .in("usuario_id", usuarios);

    if (errIns) throw new Error("ler push_inscricoes: " + errIns.message);

    const porUsuario = new Map<string, typeof inscricoes>();
    for (const ins of inscricoes || []) {
      const lista = porUsuario.get(ins.usuario_id) || [];
      lista.push(ins);
      porUsuario.set(ins.usuario_id, lista);
    }

    for (const aviso of avisos!) {
      const aparelhos = porUsuario.get(aviso.user_id) || [];

      if (aparelhos.length === 0) {
        stats.sem_aparelho++;
        // Marca como tratado mesmo assim: sem aparelho inscrito, tentar de novo
        // a cada 5 minutos até a janela expirar não levaria a lugar nenhum.
        await supabase.from("notificacoes")
          .update({ push_enviado_em: new Date().toISOString() })
          .eq("id", aviso.id);
        continue;
      }

      const conteudo = JSON.stringify({
        titulo: aviso.titulo || "B&N Logística",
        corpo: aviso.mensagem || "",
        url: aviso.link ? `${SITE_URL}/${String(aviso.link).replace(/^\//, "")}` : SITE_URL,
        // Agrupa por tipo: o aviso de 4h substitui o de 2h na bandeja,
        // em vez de acumular três sobre a mesma visita esquecida.
        tag: `checkout-${aviso.user_id}`,
        fixar: aviso.tipo === "visita_aviso_6h_final",
      });

      for (const ap of aparelhos) {
        try {
          await webpush.sendNotification(
            { endpoint: ap.endpoint, keys: { p256dh: ap.p256dh, auth: ap.auth } },
            conteudo,
          );
          stats.enviados++;
          await supabase.from("push_inscricoes")
            .update({ ultimo_uso: new Date().toISOString(), falhas: 0 })
            .eq("id", ap.id);
        } catch (e) {
          const status = (e as { statusCode?: number }).statusCode;

          // 404/410 = o aparelho desinstalou o app ou revogou a permissão.
          // Não é erro nosso: é lixo, e o certo é limpar na hora.
          if (status === 404 || status === 410) {
            await supabase.from("push_inscricoes").delete().eq("id", ap.id);
            stats.inscricoes_removidas++;
          } else {
            const falhas = (ap.falhas || 0) + 1;
            if (falhas >= MAX_FALHAS) {
              await supabase.from("push_inscricoes").delete().eq("id", ap.id);
              stats.inscricoes_removidas++;
            } else {
              await supabase.from("push_inscricoes").update({ falhas }).eq("id", ap.id);
            }
            stats.erros.push(`${ap.endpoint.slice(0, 40)}…: ${status || (e as Error).message}`);
          }
        }
      }

      await supabase.from("notificacoes")
        .update({ push_enviado_em: new Date().toISOString() })
        .eq("id", aviso.id);
    }

    return new Response(JSON.stringify({ ok: true, ...stats }), {
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, erro: (e as Error).message, ...stats }),
      { status: 500, headers: { ...cors, "Content-Type": "application/json" } },
    );
  }
});
