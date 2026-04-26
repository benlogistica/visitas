# Changelog — Nutricionais Visitas

Histórico de mudanças relevantes do sistema.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/) e o projeto adota versionamento semântico informal (`1.0.0-alpha.<tag>`).

---

## [1.0.0-alpha.sprint4] — 2026-04-20

Sprint focado em gestão de equipe (autocadastro com aprovação administrativa), drilldown analítico do dashboard e relatório exportável em PDF.

### ✨ Adicionado

#### Mini 1 — Profissional edita sua instituição pendente
- Badge **"Pendente — editar"** (âmbar, clicável) aparece na listagem de check-in quando a instituição foi cadastrada pelo próprio usuário e ainda está `pendente_aprovacao = true`.
- Reuso do modal `showModalInstituicaoNova` com novo parâmetro `modo: 'edicao'` e `instExistente`.
- Handler `window.editarMinhaInstituicaoPendente(id)` com checagem dupla de autorização (usuário logado é o cadastrante + instituição ainda está pendente) antes de abrir o modal e no momento do update.
- Badge simples "Pendente" (sem edição) continua aparecendo para instituições pendentes de outros profissionais.

#### Mini 2 — Equipe e Categorias (autocadastro com aprovação)
- **Autocadastro público** na rota `#/cadastro`:
  - Campo novo de **categoria profissional** (obrigatório), carregado dinamicamente da tabela `categorias_profissionais`.
  - Validação bloqueia submit sem categoria selecionada.
  - Nova conta salva com `status = 'pendente'` e `categoria_id` preenchido.
  - Função reutilizável `listarCategoriasAtivas()` para outros dropdowns do sistema.
- **Tela `#/admin/equipe`** (antes era placeholder) com 4 abas e contadores dinâmicos:
  - **Pendentes** — profissionais aguardando aprovação. Ações: Aprovar / Rejeitar.
  - **Ativos** — profissionais liberados. Ações: Editar categoria / Desativar. Mostra último login.
  - **Desativados** — inativos e bloqueados juntos. Ações: Reativar / Excluir definitivamente (com **dupla confirmação** e fallback orientando desativar caso haja FK de visitas).
  - **Categorias** — CRUD completo (criar, renomear, desativar, reativar, excluir). Cards mostram contagem de profissionais vinculados. Excluir só permitido para categorias vazias; desativadas não aparecem no dropdown de cadastro mas mantêm vínculos existentes.
- **Cards de profissional** padronizados: avatar com iniciais (navy), status badge colorido, CPF/e-mail/telefone, data de cadastro. Grid responsivo de 2 colunas para botões de ação.
- **Modal reutilizável `showModalInputTexto`** para prompts de texto simples (criar/renomear).
- **Dashboard admin ganhou banner adicional** (azul) exibindo cadastros de profissionais pendentes, separado do banner (âmbar) de instituições/objetivos pendentes. Cada banner leva para a tela apropriada.
- Item **"Equipe"** adicionado ao drawer lateral do admin (antes marcado como "Em breve").

#### Mini 3 — Drilldown no dashboard
- Nova rota **`#/admin/visitas`** — lista global de todas as visitas, com filtros combináveis:
  - **Período** (pills: 7d / 30d / Mês / Trimestre / Tudo)
  - **Status** (Todos / Completa / Aprovada pós-revisão / Devolvida p/ revisão / Rascunho / Realizadas / Canceladas)
  - **Profissional** (dropdown de ativos)
  - **Instituição** (dropdown de ativas)
- Filtros aplicam em tempo real (sem botão "aplicar"). Botão "Limpar filtros" reseta pro default (30d + todos).
- Aceita parâmetros de URL para deeplink: `?periodo=7&status=realizada&profissional_id=XX`.
- Contagem total no topo da lista ("X visitas encontradas").
- Cards reutilizam o visual `.review-card` com flags visíveis; clique abre o detalhe em `#/admin/revisao/detalhe?id=X`.
- **KPI "Total de visitas" do dashboard virou clicável** — navega para `#/admin/visitas?periodo=XX` preservando o período atualmente selecionado no dashboard.
- Estado `window._dashPeriodoAtual` guarda o período do dashboard globalmente para o drilldown.

#### Mini 4 — Relatório exportável em PDF
- Nova rota **`#/admin/dashboard/relatorio`** — página dedicada, formatada como documento A4.
- **Conteúdo do relatório**:
  - Cabeçalho oficial com logo navy, título, período, data+hora de geração e nome do gerador.
  - **Resumo executivo em prosa** — gerado dinamicamente, com adjetivação adaptativa para qualidade GPS (≥80% = "boa", ≥60% = "aceitável", <60% = "merece atenção"). Menciona pendências se houver.
  - **4 KPIs** em grid horizontal com hints.
  - **Gráfico de linha SVG** — visitas no tempo (reusa a função do dashboard).
  - **Rankings** (Top 8 profissionais e Top 8 instituições) em tabelas com barra de progresso verde.
  - **Distribuições** — pizzas de Status e Tipo de check-in (lado a lado) + barras horizontais de Top objetivos.
  - **Lista completa de visitas** em tabela densa com quebra de página antes (`.page-break-before`). Colunas: data/hora, profissional, instituição, status, resultado (realizada/cancelada/—), GPS (✓ / ⚠ / 🅼).
  - Footer com aviso de documento gerado automaticamente.
- **Botão "Exportar PDF"** no dashboard admin chama `window.location.hash = '#/admin/dashboard/relatorio?periodo=XX&auto=1'`. O parâmetro `auto=1` dispara `window.print()` automaticamente 800ms após carregar (tempo para ícones/fontes carregarem).
- **CSS `@media print`** cuidadosamente ajustado: remove `.no-print`, zera paddings, força `-webkit-print-color-adjust: exact`, `@page A4` com margens 16mm × 14mm, quebra de página controlada por `.avoid-break` e `.page-break-before`.
- **Card informativo de dica** (azul, classe `.no-print`) instrui o usuário a desmarcar "Cabeçalhos e rodapés" no diálogo de impressão para um PDF sem URL/data do browser.

### 🔧 Migrations (rodar no Supabase SQL Editor)

- **`migration_18_equipe.sql`** — **obrigatória** para o Sprint 4:
  - Cria tabela `categorias_profissionais (id uuid, nome text unique, ativo boolean, criado_em timestamptz)`.
  - Seed inicial: Nutricionista, Enfermeiro, Farmacêutico, Médico (só insere se tabela está vazia).
  - Adiciona `categoria_id uuid REFERENCES categorias_profissionais(id)` em `usuarios`.
  - Adiciona `email text` em `usuarios` (idempotente).
  - Cria índices `idx_usuarios_status` e `idx_usuarios_categoria`.
  - `NOTIFY pgrst, 'reload schema'` para PostgREST reconhecer as mudanças.

> ℹ️ **Sobre RLS:** ao rodar a migration, o Supabase exibe aviso de RLS em nova tabela. **Escolher "Run without RLS"** — mantém consistência com o restante do sistema, que opera sem RLS desde a `migration_14_rollback_rls.sql` (projeto usa login customizado em `usuarios`, não Supabase Auth, então `auth.uid()` retorna null e políticas RLS bloqueariam tudo).

### 🐛 Corrigido

- **Plural dinâmico em KPIs** — hints "X divergentes · Y manuais" e "X realizadas · Y canceladas" agora concordam em número quando o valor é 1 (evita "1 manuais" / "1 realizadas"). Vale para o dashboard e para o relatório PDF.
- **Frase de destaque do profissional** no resumo executivo do PDF — só aparece "com destaque para X" quando há 3+ profissionais ativos no período. Com 1 profissional usa "todas registradas por X"; com 2 omite a comparação para não soar crítica implícita.
- **Erro "column visitas.em_revisao does not exist"** na tela de Todas as visitas — coluna legado foi removida pela migration 15. Ajustado o SELECT. Filtro "Devolvida p/ revisão" agora usa a lógica atual (`status='rascunho' AND revisao_motivo IS NOT NULL`), e filtro "Rascunho" usa rascunho puro (`status='rascunho' AND revisao_motivo IS NULL`).

### 💔 Breaking changes

Nenhum. O sprint é aditivo — todas as mudanças são compatíveis com dados existentes.

### 📝 Notas de deploy

1. **Rodar `migration_18_equipe.sql`** no Supabase antes de publicar a nova versão do `index.html`. Sem isso, a tela de cadastro não carrega categorias e a tela de equipe falha com erro de coluna.
2. **Publicar `index.html`** no GitHub Pages. Não há outras dependências externas — continua single-file.
3. **Nenhuma mudança de credenciais/env necessária.** Supabase URL e chave pública seguem as mesmas.
4. **Hard reload** (Ctrl+Shift+R) recomendado para garantir que o browser não use CSS antigo em cache.
5. **Admin Master existente** (CPF `000.000.000-00`) continua funcionando normalmente. Profissionais criados antes da migration 18 ficam com `categoria_id = NULL` — usar a ação "Editar categoria" na aba Ativos para preencher.

### 📁 Arquivos adicionados em `/mnt/user-data/outputs/`

- `migration_18_equipe.sql`
- `index.html` (atualizado)

### 📊 Métricas informais do sprint

- Linhas de código adicionadas: ~1.400 (sobre ~11.000 existentes).
- Divs balanceados: 862/862 ✓
- Rotas novas: 2 (`#/admin/visitas`, `#/admin/dashboard/relatorio`).
- Tabelas novas no banco: 1 (`categorias_profissionais`).
- Colunas novas em tabelas existentes: 2 (`usuarios.categoria_id`, `usuarios.email` idempotente).
- Tempo total do sprint: 1 sessão de trabalho.

---

## [1.0.0-alpha.flags2] — Sprints anteriores

Sprints 1–3 documentados em conversas anteriores e resumidos na memória do projeto. Principais marcos:

- **Sprint 1–2** — Autenticação custom (CPF+senha), recuperação de senha via OTP/EmailJS, cadastros iniciais, check-in por GPS com raio configurável, relatório da visita, bottom nav.
- **Sprint 3 Mini 1** — Fila de revisão admin (filtros por flags).
- **Sprint 3 Mini 2** — Fluxo "devolver pra revisão": admin devolve com motivo, visita volta pra `status='rascunho' + revisao_motivo`, janela de 24h reabre.
- **Sprint 3 Mini 3** — Seed de visitas teste.
- **Sprint 3 Mini 4** — Dashboard admin com KPIs, gráfico de linha SVG, rankings, pizzas, drawer lateral. Cadastro de instituição em campo pelo profissional (usando GPS dele como coords iniciais). Geocoding via OpenStreetMap no admin. Correção do bug crítico `flag_gps_divergente NOT NULL` via `DROP NOT NULL` (migrations 15–17).

Para histórico detalhado desses sprints, consultar os anexos SQL (`migration_11` a `migration_17`) e resumos de conversa.
