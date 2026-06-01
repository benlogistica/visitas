# 📦 HANDOFF — Nutricionais Visitas (BENLogistica)

> **Como usar este documento:** abra uma **sessão nova e leve** no Cowork, conecte a pasta
> `C:\Users\Edu\Documents\nutricionais-visitas` e cole/anexe este arquivo na primeira mensagem.
> Ele dá ao Claude todo o contexto do projeto sem precisar arrastar o histórico antigo (que é o
> que estava deixando a sessão BENLogistica travada).

**Gerado em:** 2026-06-01
**Versão atual do app:** `1.0.0-alpha.sprint9.32.373-filtros-prof-hospital-profissao`

---

## 1. O que é o projeto

Sistema **mobile-first** de gestão de visitas comerciais de nutricionistas a hospitais.
Nutricionistas registram visitas com check-in por GPS, objetivos e relatórios; administradores
revisam divergências e acompanham indicadores.

- **App em produção:** https://nutricionais.github.io/nutricionais-visitas/
- **Repositório:** GitHub Pages (deploy = publicar `index.html`)

### Perfis
- **Nutricionista (mobile):** login CPF+senha, dashboard, check-in/checkout GPS, relatório de visita (stepper 7 etapas), minhas visitas com calendário colapsável.
- **Admin (desktop):** dashboard com KPIs/gráficos, fila de revisão, CRUD instituições/profissionais/equipe, agenda, faturamento (import Excel + curva ABC), relatório PDF.

---

## 2. Stack técnica

| Camada | Tecnologia |
|---|---|
| Frontend | **HTML single-file** + JavaScript vanilla (sem build) |
| Banco | Supabase (PostgreSQL) — `SUPABASE_URL` no topo do `index.html` (~linha 8247) |
| Auth | Custom: tabela `usuarios` + hash SHA-256 (Web Crypto). **Sem Supabase Auth, sem RLS.** |
| Hospedagem | GitHub Pages |
| UI | Material Symbols Rounded · Poppins/Inter/JetBrains Mono · Navy `#0A1F5C` + Lime `#8BC63F` |

**Decisão consciente: tudo num único `index.html`** (CSS+JS+HTML). Zero build, deploy trivial.

---

## 3. Arquivos-chave

```
index.html                      ← O APP INTEIRO (~55.800 linhas). Editar aqui.
faturamento_data_inline.json    ← dados de faturamento (~17 MB, gerado por script)
manifest.json                   ← PWA
bckps/CHANGELOG.md              ← changelog (detalhado até sprint4; resto no git/sprints)
bckps/README.md                 ← visão geral do projeto
supabase/*.sql                  ← migrations e scripts de manutenção do banco
edge-functions/*.ts             ← e-mail e verificação de visitas abertas
scripts/validate-index.ps1      ← validador de sintaxe do index.html
DESIGN DO PROJETO/              ← protótipos por área (mobile, admin, auth, cadastros)
logs/                           ← snapshots diários do xlsx de faturamento
entrada/                        ← XLSX de faturamento para importar
```

**Backups estáveis do index:** `index.html.estavel.9.32.191`, `.194`, `.bak_338`, `.bak_338b`.

---

## 4. Banco de dados (11 tabelas principais)

`usuarios` · `instituicoes` · `profissionais` · `visitas` · `visitas_agendadas` ·
`objetivos_visita` · `configuracoes_sistema` · `faturamento` · `historico_visitas` ·
`visitas_objetivos` (N:N) · `visitas_profissionais` (N:N) · `categorias_profissionais`.

**Flags automáticas por visita:** `sem_checkin`, `sem_checkout`, `gps_divergente` (>500m),
`horario_fora_margem` (±1h30), `checkin_manual`.

⚠️ **RLS:** o projeto roda **sem RLS** (login é custom, `auth.uid()` é null). Ao criar tabela nova
no Supabase, escolher **"Run without RLS"**.

---

## 5. Sprints recentes (estado mais novo → mais antigo)

- **9.32.373** — `/admin/profissionais`: dois dropdowns novos (Hospital e Profissão) ao lado da busca; combinam em AND com o texto; populados dinâmicos da base; re-populam ao trocar aba Ativos/Desativados.
- **9.32.372** — Bug do "resumo com `</div><br>` aparecendo como texto" na fila de revisão e snippets de busca. Criado helper `_stripHtmlPreview()` (converte `<br>`/blocos em espaço, remove tags, normaliza). Aplicado em `renderReviewCard`, snippets admin desktop/mobile e filtro de busca por campo.
- **9.32.371** — Tela `/admin/revisao/detalhe`: botão Voltar saiu do topbar; agora banner branco "Modo revisão · auditando visita" (ícone `rule`) à esquerda + Voltar (pill outline navy) à direita, igual ao padrão do profissional.
- **9.32.370** — "Minhas visitas" (desktop): botão Ocultar/Mostrar calendário; grid alterna entre `30% 1fr` e `1fr` full-width; estado salvo em `localStorage.mvCalDesktopOculto`.

> Changelog formal em `bckps/CHANGELOG.md` está detalhado **até o sprint4**; do sprint5 em diante o
> histórico vive nos resumos de cada sprint (e no git para os `Sync faturamento`).

---

## 6. ⚠️ Pendências e pontos de atenção

1. **Há mudanças NÃO commitadas no git.** `git status` mostra `index.html` modificado (sprints 371–373)
   além de `manifest.json`, `gerar_faturamento_json.py`, `comparativo_mapas.html` e vários
   `proto_*.html` deletados. **Antes de continuar, decidir o que commitar.** O último commit é só
   um "Sync faturamento" de 2026-05-31 — ele NÃO inclui o código dos sprints recentes.

2. **🐞 Bug recorrente: o `Edit` trunca o `index.html`.** Por o arquivo ser muito grande (~55k linhas),
   a ferramenta Edit já cortou o final do arquivo várias vezes. **Workaround usado nos últimos sprints:
   fazer as alterações via script Python (substituição atômica) em vez de Edit**, e restaurar o tail
   do `git HEAD` quando truncar. Sempre validar depois.

3. **Validação obrigatória após editar o index:** checar sintaxe JS, presença de `</html>` no fim, e
   **balanceamento de `<div>`** (script `scripts/validate-index.ps1`). Os sprints registram esse passo.

---

## 7. Fluxo de trabalho recomendado para a sessão nova

1. Conectar a pasta `C:\Users\Edu\Documents\nutricionais-visitas`.
2. Confirmar a versão atual: `grep APP_VERSION index.html`.
3. Para qualquer edição no `index.html`: **usar Python/atômico, não o Edit**, e validar (sintaxe +
   `</html>` + divs balanceados) antes de fechar o sprint.
4. Subir a `APP_VERSION` a cada sprint (padrão `1.0.0-alpha.sprint9.32.<N>-<descricao-curta>`).
5. Commit + push para publicar no GitHub Pages. Hard reload (Ctrl+Shift+R) para furar cache.

---

## 8. Por que a sessão BENLogistica travava (e como evitar)

A sessão acumulou **muitos sprints de histórico** (texto + imagens + centenas de chamadas de
ferramenta). Quanto maior o histórico, mais pesada a interface do chat fica — daí o travamento.
**Solução:** começar sessões novas periodicamente usando este HANDOFF como ponto de partida, em vez
de continuar uma conversa infinita. O código e os arquivos ficam todos na pasta do projeto, então
nada se perde ao abrir uma sessão nova.
