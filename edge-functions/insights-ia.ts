// =============================================================================
// Edge Function: insights-ia   |   Sprint 9.32.382
// =============================================================================
// Gera a "leitura do analista" da aba Insights do Faturamento usando IA.
//
// PRINCÍPIO CENTRAL — o modelo NÃO CALCULA NADA.
//   Todos os números chegam prontos, já calculados pelo app (que é determinístico
//   e auditável). A IA só interpreta, prioriza e escreve. Se ela fizer conta, ela
//   inventa — e um dashboard que mente é pior que um dashboard sem graça.
//
// CUSTO / CACHE:
//   A análise custa tokens. Os dados só mudam quando roda o `atualizar_dashboard.bat`,
//   que grava um novo `meta.gerado_em` no JSON. Usamos esse carimbo como `data_hash`:
//     - Se já existe análise pra esse hash  -> devolve do cache (custo ZERO).
//     - Se não existe                        -> chama a IA 1x, salva e devolve.
//   Resultado: no máximo uma chamada paga por sincronização de dados.
//
// A CHAVE DA API FICA AQUI, NO SERVIDOR — nunca no index.html, que é público no
// GitHub Pages (qualquer um lê o código-fonte e roubaria a chave).
//
// Secrets esperados (Edge Functions -> Manage secrets):
//   ANTHROPIC_API_KEY=sk-ant-...
//   ANTHROPIC_MODEL=claude-sonnet-4-6        (opcional; troque por um modelo
//                                             mais barato pra reduzir custo)
//   SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já vêm prontos do ambiente.
//
// Pré-requisito: rodar `supabase/insights_ia.sql` (cria a tabela de cache).
// =============================================================================

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const MODELO_PADRAO = "claude-sonnet-4-6";

const SYSTEM_PROMPT = `Você é o analista comercial da B&N Logística, distribuidora de nutrição hospitalar.

Você recebe um bloco de números JÁ CALCULADOS e CORRETOS sobre o faturamento.

REGRAS ABSOLUTAS:
1. NUNCA calcule, recalcule, some, divida ou estime qualquer número. Use SOMENTE os valores que recebeu, exatamente como vieram.
2. NUNCA invente nomes de clientes, marcas, canais ou valores que não estejam nos dados.
3. Se um dado não estiver presente, não fale sobre ele. Não preencha lacuna com suposição.
4. O mês em curso é PARCIAL (só parte dos dias foi apurada). Jamais trate a queda aparente do mês em curso como queda real, e jamais o compare com meses fechados.

COMO ESCREVER:
- Português do Brasil, tom de quem gerencia a operação: direto, concreto, sem jargão de consultoria.
- Fale como quem vai agir amanhã de manhã, não como quem faz relatório.
- Priorize: o que muda a receita primeiro vem primeiro.
- Cada prioridade precisa de uma ação específica e executável — "ligar para o cliente X" e não "melhorar o relacionamento".
- Nada de elogio vazio nem de alarmismo. Se está indo bem, diga que está indo bem.

Responda SOMENTE com um JSON válido, sem markdown, sem cercas de código, neste formato exato:
{
  "resumo": "2 a 3 frases sobre o momento do negócio, citando os números que importam",
  "prioridades": [
    { "titulo": "curto e direto", "porque": "1 frase com o número que sustenta", "acao": "a ação concreta a tomar" }
  ],
  "risco": "o maior risco no horizonte, com o número que o sustenta",
  "oportunidade": "a maior receita na mesa, com o número que a sustenta"
}
São no máximo 3 prioridades.`;

Deno.serve(async (req) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });

  try {
    const { data_hash, resumo, forcar } = await req.json();

    if (!data_hash) return json({ ok: false, error: "data_hash é obrigatório" }, 400);
    if (!resumo) return json({ ok: false, error: "resumo é obrigatório" }, 400);

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const API_KEY = Deno.env.get("ANTHROPIC_API_KEY");
    const MODELO = Deno.env.get("ANTHROPIC_MODEL") || MODELO_PADRAO;

    if (!API_KEY) {
      return json({ ok: false, error: "ANTHROPIC_API_KEY não configurada nos secrets" }, 500);
    }

    const restHeaders = {
      apikey: SERVICE_KEY,
      Authorization: `Bearer ${SERVICE_KEY}`,
      "Content-Type": "application/json",
    };

    // ---- 1. Cache: já analisamos essa versão dos dados? ----------------------
    if (!forcar) {
      const cacheResp = await fetch(
        `${SUPABASE_URL}/rest/v1/insights_ia?data_hash=eq.${encodeURIComponent(data_hash)}&select=analise,modelo,gerado_em&limit=1`,
        { headers: restHeaders },
      );
      const cacheRows = await cacheResp.json().catch(() => []);
      if (Array.isArray(cacheRows) && cacheRows.length > 0) {
        return json({
          ok: true,
          cached: true,
          analise: JSON.parse(cacheRows[0].analise),
          modelo: cacheRows[0].modelo,
          gerado_em: cacheRows[0].gerado_em,
        });
      }
    }

    // ---- 2. Sem cache: chama a IA uma única vez ------------------------------
    const iaResp = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODELO,
        max_tokens: 1500,
        system: SYSTEM_PROMPT,
        messages: [{
          role: "user",
          content: "Números do faturamento (já calculados, use exatamente como estão):\n\n" +
            JSON.stringify(resumo, null, 2),
        }],
      }),
    });

    if (!iaResp.ok) {
      const erro = await iaResp.text().catch(() => "");
      return json({ ok: false, error: `IA retornou HTTP ${iaResp.status}: ${erro.slice(0, 300)}` }, 502);
    }

    const iaJson = await iaResp.json();
    let texto = (iaJson?.content?.[0]?.text || "").trim();

    // Defesa: se vier embrulhado em cerca de código, desembrulha.
    texto = texto.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();

    let analise;
    try {
      analise = JSON.parse(texto);
    } catch {
      return json({ ok: false, error: "A IA não devolveu JSON válido.", bruto: texto.slice(0, 400) }, 502);
    }

    const tokensIn = iaJson?.usage?.input_tokens ?? null;
    const tokensOut = iaJson?.usage?.output_tokens ?? null;

    // ---- 3. Salva no cache (upsert pelo data_hash) ---------------------------
    await fetch(`${SUPABASE_URL}/rest/v1/insights_ia?on_conflict=data_hash`, {
      method: "POST",
      headers: { ...restHeaders, Prefer: "resolution=merge-duplicates" },
      body: JSON.stringify({
        data_hash,
        analise: JSON.stringify(analise),
        modelo: MODELO,
        tokens_entrada: tokensIn,
        tokens_saida: tokensOut,
        periodo_fim: resumo?.periodo_fim ?? null,
      }),
    }).catch(() => { /* se o cache falhar, a análise ainda volta pro usuário */ });

    return json({
      ok: true,
      cached: false,
      analise,
      modelo: MODELO,
      gerado_em: new Date().toISOString(),
      tokens: { entrada: tokensIn, saida: tokensOut },
    });
  } catch (e) {
    return json({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});
