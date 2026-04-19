# 🏥 Nutricionais Visitas

**Sistema mobile-first de gestão de visitas comerciais de nutricionistas**

Aplicação web que permite às nutricionistas da equipe comercial registrar visitas a hospitais com check-in GPS, objetivos e relatórios, enquanto administradores revisam divergências e acompanham indicadores.

🔗 **App em produção:** [nutricionais.github.io/nutricionais-visitas](https://nutricionais.github.io/nutricionais-visitas/)

---

## 📱 Funcionalidades

### Para nutricionistas (mobile-first)

- ✅ **Login com CPF + senha** (hash SHA-256 via Web Crypto API)
- ✅ **Cadastro com aprovação pendente** (admin revisa antes de liberar)
- ✅ **Recuperação de senha** via código OTP
- ✅ **Dashboard personalizado** — saudação dinâmica, KPIs, últimas visitas
- ✅ **Check-in GPS** — lista de hospitais ordenada por proximidade (Haversine)
- ✅ **Raio geográfico de 500m** — tolerância configurável, flag de GPS divergente
- ✅ **Check-in manual** — fallback quando GPS não está disponível
- ✅ **Timer em tempo real** — contagem da duração da visita
- ✅ **Check-out com GPS** — registra localização de saída
- 🔄 **Relatório de visita** — stepper de 7 etapas com salvamento incremental *(Sprint 2.3)*

### Para administradores

- 🔄 **Dashboard admin** — KPIs globais, gráficos e ações pendentes *(Sprint 3)*
- 🔄 **Fila de revisão** — visitas com flags de divergência *(Sprint 3)*
- 🔄 **CRUD de instituições** — hospitais, clínicas e suas coordenadas *(Sprint 3)*
- 🔄 **CRUD de profissionais** — nutricionistas, médicos, enfermeiros *(Sprint 3)*
- 🔄 **Agenda** — planejamento de visitas futuras *(Sprint 3)*
- 🔄 **Faturamento** — import Excel, curva ABC *(Sprint 4)*

---

## 🛠️ Stack técnica

| Camada | Tecnologia |
|---|---|
| **Frontend** | HTML single-file + JavaScript vanilla (sem build) |
| **Banco de dados** | Supabase (PostgreSQL) |
| **Autenticação** | Custom (tabela `usuarios` + hash SHA-256) |
| **Hospedagem** | GitHub Pages |
| **Ícones** | Material Symbols Rounded |
| **Tipografia** | Poppins (display), Inter (body), JetBrains Mono (dados) |
| **Paleta** | Navy `#0A1F5C` + Lime `#8BC63F` |

### Por que single-file?

O arquivo `index.html` contém **todo o CSS, JavaScript e HTML** em um único arquivo. Essa escolha foi consciente:

- **Zero build** — editar → salvar → recarregar
- **Deploy trivial** — drag-and-drop no GitHub Pages
- **Portabilidade** — abre até mesmo com duplo clique local
- **Debug facilitado** — um único arquivo pra inspecionar

---

## 📊 Banco de dados

Schema em PostgreSQL com 11 tabelas:

- `usuarios` — autenticação e perfis (admin / nutricionista)
- `instituicoes` — hospitais com coordenadas GPS
- `profissionais` — contatos por instituição
- `visitas` — registro principal com check-in/checkout
- `visitas_agendadas` — agenda futura
- `objetivos_visita` — catálogo (contagem, padronização, etc.)
- `configuracoes_sistema` — parâmetros globais (raio GPS, margens)
- `faturamento` — dados comerciais por instituição
- `historico_visitas` — auditoria
- `visitas_objetivos` — N:N entre visitas e objetivos
- `visitas_profissionais` — N:N entre visitas e profissionais

Flags automáticas em cada visita: `sem_checkin`, `sem_checkout`, `gps_divergente` (>500m), `horario_fora_margem` (±1h30), `checkin_manual`.

---

## 🗺️ Status do roadmap

- ✅ **Sprint 1** — Fundação (infra, splash, diagnóstico)
- ✅ **Sprint 2.1** — Autenticação (login, cadastro, recuperar senha)
- ✅ **Sprint 2.2** — Core operacional (dashboard, check-in GPS, timer)
- 🔄 **Sprint 2.3** — Relatório de visita (stepper 7 etapas)
- ⏳ **Sprint 3** — Admin (dashboard, fila de revisão, CRUD)
- ⏳ **Sprint 4** — Faturamento + PWA offline

---

## 🚀 Rodar localmente

```bash
# Clone o repositório
git clone https://github.com/nutricionais/nutricionais-visitas.git

# Navegue até a pasta
cd nutricionais-visitas

# Abra o index.html no navegador
# (duplo clique ou Ctrl+O no Chrome/Edge/Firefox)
```

Não requer instalação de dependências. As chaves do Supabase já estão embutidas (chave `anon`, segura para uso público).

---

## 🔐 Segurança

- Senhas armazenadas como hash SHA-256 (Web Crypto API nativa)
- RLS (Row Level Security) planejado para Fase 2 pós-MVP
- Chave `anon` do Supabase é pública por design — restrições aplicadas via RLS
- Nenhum dado sensível no repositório

---

## 👥 Créditos

Desenvolvido para **Nutricionais** (nutricionais.com.br) com foco em equipes comerciais de nutrição enteral e parenteral hospitalar.
