// =============================================================================
// Edge Function: verificar-visitas-abertas   |   versão 9.32.260
// =============================================================================
// Roda a cada 15 minutos via pg_cron (configurado em supabase/visitas_auto_checkout.sql).
// Pra cada visita com checkin SEM checkout, decide qual ação tomar:
//
//   >= 2h  e sem aviso_2h_em → INSERT notificacoes "esqueceu checkout 2h"
//   >= 4h  e sem aviso_4h_em → INSERT notificacoes "esqueceu checkout 4h"
//   >= 6h  e sem aviso_6h_em → INSERT notificacoes "último alerta antes do auto-fechamento"
//   >= 6h30                  → AUTO-CHECKOUT: status='rascunho', checkout_automatico=true
//                              + notificações pro nutri E pra cada admin
//
// IMPORTANTE: NÃO toca em nada do sistema de GPS / check-in / timer atual.
// Só lê/escreve em colunas próprias da feature (aviso_*, checkout_automatico).
//
// SETUP NO SUPABASE:
//   1. SQL Editor → rodar supabase/visitas_auto_checkout.sql (cria colunas + cron)
//   2. Edge Functions → New function "verificar-visitas-abertas"
//   3. Cola este código
//   4. Deploy
//   5. Marcar "Verify JWT" = OFF (cron usa service_role, não JWT de usuário)
//
// SECRETS NECESSÁRIOS (já existem no projeto):
//   SUPABASE_URL              — URL do projeto
//   SUPABASE_SERVICE_ROLE_KEY — service role (bypass RLS)
// =============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Constantes de tempo (em minutos) — fácil de ajustar se quiser mudar a janela
const MIN_AVISO_2H = 120;   // 2 horas
const MIN_AVISO_4H = 240;   // 4 horas
const MIN_AVISO_6H = 360;   // 6 horas
const MIN_AUTO_FECHAR = 390; // 6h30 — janela de 30min após o último aviso pra agir
// Sprint 9.32.269: extensão do nutri (+2h) — quando concedida, o threshold de auto-fechar pula pra 8h30
const MIN_AUTO_FECHAR_COM_EXTENSAO = 510; // 8h30

const SITE_URL = "https://www.benlogistica.com.br";

Deno.serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  const stats = {
    avisos_2h: 0,
    avisos_4h: 0,
    avisos_6h: 0,
    auto_fechadas: 0,
    erros: [] as string[],
    visitas_processadas: 0,
  };

  try {
    // 1. Busca todas as visitas com check-in SEM check-out
    //    Já vem com nome do nutri e nome da instituição pra usar nas mensagens
    // Sprint 9.32.269: também traz extensao_concedida_em pra cálculo do threshold
    const { data: visitas, error: errSel } = await supabase
      .from("visitas")
      .select(`
        id, nutricionista_id, instituicao_id, checkin_timestamp,
        aviso_2h_em, aviso_4h_em, aviso_6h_em, extensao_concedida_em,
        usuarios:nutricionista_id(id, nome, email),
        instituicoes(id, nome, cidade)
      `)
      .not("checkin_timestamp", "is", null)
      .is("checkout_timestamp", null)
      .neq("status", "cancelada");

    if (errSel) throw new Error("Erro ao buscar visitas: " + errSel.message);

    stats.visitas_processadas = (visitas || []).length;

    // 2. Se houver auto-fechamento, vamos precisar avisar admins — busca lista 1x
    let admins: Array<{ id: string; nome: string; email: string | null }> = [];
    let adminsCarregados = false;
    const carregarAdmins = async () => {
      if (adminsCarregados) return admins;
      const { data } = await supabase
        .from("usuarios")
        .select("id, nome, email")
        .eq("perfil", "admin")
        .eq("status", "ativo");
      admins = data || [];
      adminsCarregados = true;
      return admins;
    };

    // 3. Pra cada visita aberta, decide o que fazer
    const agora = new Date();
    for (const v of visitas || []) {
      try {
        const checkinDt = new Date(v.checkin_timestamp);
        const minutosAberto = (agora.getTime() - checkinDt.getTime()) / 60000;
        const nutri = v.usuarios;
        const inst = v.instituicoes;
        const nutriNome = nutri?.nome || "Profissional";
        const instNome = inst?.nome || "instituição";
        const linkVisita = `/visitas/${v.id}`;

        // ===== AUTO-FECHAMENTO (>= 6h30, ou >= 8h30 se extensão foi concedida) =====
        const limiteAutoFechar = v.extensao_concedida_em ? MIN_AUTO_FECHAR_COM_EXTENSAO : MIN_AUTO_FECHAR;
        if (minutosAberto >= limiteAutoFechar) {
          // Marca a visita como auto-fechada
          const { error: errUpd } = await supabase
            .from("visitas")
            .update({
              checkout_timestamp: agora.toISOString(),
              checkout_automatico: true,
              auto_checkout_em: agora.toISOString(),
              status: "rascunho",
            })
            .eq("id", v.id);

          if (errUpd) {
            stats.erros.push(`auto_fechar visita ${v.id}: ${errUpd.message}`);
            continue;
          }
          stats.auto_fechadas++;

          // Notificação pro nutri (sininho + e-mail via TIPO_TEMPLATE)
          if (nutri?.id) {
            await supabase.from("notificacoes").insert({
              user_id: nutri.id,
              tipo: "visita_auto_fechada",
              titulo: "Visita encerrada automaticamente",
              mensagem: `Sua visita ao ${instNome} ficou aberta por mais de 6h30 e foi salva como rascunho. Você pode editar e revisar a qualquer momento.`,
              link: linkVisita,
              lida: false,
            });
          }

          // Notificação pra cada admin (sininho + e-mail)
          const adms = await carregarAdmins();
          if (adms.length > 0) {
            const linhasAdmin = adms.map(a => ({
              user_id: a.id,
              tipo: "admin_visita_auto_fechada",
              titulo: "Visita auto-fechada pelo sistema",
              mensagem: `Visita de ${nutriNome} (${instNome}) foi fechada automaticamente após 6h30 sem checkout. Pode indicar esquecimento ou problema técnico.`,
              link: `/admin/revisao/detalhe?id=${v.id}`,
              lida: false,
            }));
            await supabase.from("notificacoes").insert(linhasAdmin);
          }
          continue; // visita resolvida, próximo
        }

        // ===== AVISO 6h (último alerta antes do auto-fechamento) =====
        if (minutosAberto >= MIN_AVISO_6H && !v.aviso_6h_em) {
          if (nutri?.id) {
            await supabase.from("notificacoes").insert({
              user_id: nutri.id,
              tipo: "visita_aviso_6h_final",
              titulo: "Último aviso: visita será fechada em 30 minutos",
              mensagem: `Sua visita ao ${instNome} está aberta há 6 horas. Em 30 min o sistema vai encerrar automaticamente como rascunho. Encerre agora pra garantir os dados.`,
              link: linkVisita,
              lida: false,
            });
          }
          await supabase.from("visitas").update({ aviso_6h_em: agora.toISOString() }).eq("id", v.id);
          stats.avisos_6h++;
          continue;
        }

        // ===== AVISO 4h =====
        if (minutosAberto >= MIN_AVISO_4H && !v.aviso_4h_em) {
          if (nutri?.id) {
            await supabase.from("notificacoes").insert({
              user_id: nutri.id,
              tipo: "visita_aviso_4h",
              titulo: "Visita aberta há 4 horas",
              mensagem: `Sua visita ao ${instNome} continua sem encerramento. Encerre logo pra não perder os dados.`,
              link: linkVisita,
              lida: false,
            });
          }
          await supabase.from("visitas").update({ aviso_4h_em: agora.toISOString() }).eq("id", v.id);
          stats.avisos_4h++;
          continue;
        }

        // ===== AVISO 2h =====
        if (minutosAberto >= MIN_AVISO_2H && !v.aviso_2h_em) {
          if (nutri?.id) {
            await supabase.from("notificacoes").insert({
              user_id: nutri.id,
              tipo: "visita_aviso_2h",
              titulo: "Esqueceu o check-out?",
              mensagem: `Você fez check-in no ${instNome} há 2 horas e ainda não encerrou a visita.`,
              link: linkVisita,
              lida: false,
            });
          }
          await supabase.from("visitas").update({ aviso_2h_em: agora.toISOString() }).eq("id", v.id);
          stats.avisos_2h++;
          continue;
        }
      } catch (errVisita) {
        stats.erros.push(`visita ${v.id}: ${(errVisita as Error)?.message || errVisita}`);
      }
    }

    return new Response(JSON.stringify({ ok: true, stats }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("verificar-visitas-abertas error:", e);
    return new Response(JSON.stringify({
      ok: false,
      error: String((e as Error)?.message || e),
      stats,
    }), {
      status: 200, // 200 pra não bloquear retentativas do cron
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
