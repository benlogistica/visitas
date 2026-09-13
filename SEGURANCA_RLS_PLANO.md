# Segurança do banco — diagnóstico e plano

**Data:** 12/09/2026 · **Projeto Supabase:** `nutricionais-crm` (`qrlnbtxscjrmnpfjbtvv`)
**Origem:** alertas semanais do Supabase Advisor recebidos por e-mail

---

## 1. Resumo em um parágrafo

A chave de acesso ao banco está publicada dentro do `index.html`, que é servido
abertamente em `benlogistica.com.br`. Isso por si só não seria um problema — em apps
que rodam no navegador essa chave é **feita para ser pública**. O que a torna perigosa
aqui é que o banco está sem RLS e o papel anônimo recebeu permissão total. Resultado:
qualquer pessoa que abra o código-fonte da página consegue ler, alterar e apagar
todo o banco, sem passar pela tela de login.

**Não há indício de que isso tenha acontecido.** Mas a porta está destrancada.

---

## 2. O que foi verificado (e como)

| Verificação | Resultado |
|---|---|
| RLS nas tabelas do app | **Desligada em 16 tabelas** |
| Permissões do papel `anon` | `SELECT, INSERT, UPDATE, DELETE, TRUNCATE` em todas |
| Chave no arquivo público | Confirmada em `index.html`, linha ~8270 |
| Login | Compara o hash via filtro no banco (não vaza por si só) |

As três primeiras linhas, juntas, são o que caracteriza a exposição. Nenhuma delas
isolada seria grave.

## 3. O que está exposto hoje

| Tabela | Linhas | Dado sensível |
|---|---:|---|
| `notificacoes` | 3.183 | conteúdo das mensagens internas |
| `visitas` | 1.004 | coordenadas de GPS de check-in/checkout |
| `profissionais` | 512 | e-mail, telefone |
| `instituicoes` | 344 | CNPJ, coordenadas, contatos do supervisor |
| `usuarios` | 15 | **CPF, e-mail, telefone, hash de senha** |
| `funil_indicacoes` | 4 | **CPF de cliente final** |

### Dois pontos que merecem atenção específica

**O hash das senhas é SHA-256 sem sal.** Isso significa que senhas comuns ou curtas
podem ser descobertas por comparação com tabelas prontas, que circulam livremente.
Um hash exposto não é o mesmo que uma senha exposta — mas está mais perto do que
parece.

**Há CPF de terceiros.** Os CPFs de clientes no funil e os dos profissionais não são
dados da empresa: são de outras pessoas. É isso que traz a LGPD para a conversa.
*(Não sou advogado e isto não é orientação jurídica — vale consultar quem cuida
disso aí, porque a obrigação de notificar em caso de incidente depende do caso.)*

---

## 4. Um engano comum: trocar a chave não resolve

O reflexo natural é "então vamos gerar outra chave". Não adianta: a nova chave
teria que ir para o `index.html` do mesmo jeito, e ficaria igualmente visível.
A chave anônima é pública por design. **Quem deveria proteger os dados é a RLS
e as permissões — e é aí que está o buraco.**

---

## 5. Por que não foi feito assim desde o começo

Não foi descuido: foi uma escolha registrada no HANDOFF. O login é próprio
(CPF + senha), não usa o Supabase Auth. Sem ele, o banco não sabe quem é o usuário
— `auth.uid()` é sempre nulo — e uma política de RLS não teria como decidir quem
pode ver o quê. A decisão fazia sentido. O que mudou é que o sistema saiu do
piloto e hoje carrega dado real de 344 instituições e 512 profissionais.

---

## 6. As opções

### Opção A — Ganhos rápidos
**Esforço:** algumas horas · **Risco de quebrar o app:** baixo · **Proteção:** parcial

Quatro medidas independentes, cada uma com valor próprio:

1. ~~**Apagar as 12 tabelas `_bkp_reset20260504_*`**~~ — **RETIRADO DO PLANO.**
   Ao conferir, essas tabelas guardam 90 visitas, 15 instituições, 15 profissionais
   e 7 usuários que **não existem em nenhuma outra tabela**. Não são cópias: são o
   único exemplar de dados apagados no reset de 04/05/2026. Tudo indica ser massa
   de teste pré-lançamento (há visitas datadas de outubro/2026, ou seja, no futuro),
   mas isso precisa ser confirmado por você, não presumido por mim.
   E, principalmente: **essas 12 tabelas já são as únicas protegidas** — têm RLS
   ligada e nenhuma política, o que significa que ninguém consegue lê-las.
   Apagá-las não melhora a segurança em nada; só limparia a lista de alertas.
2. **Revogar `TRUNCATE` do papel anônimo** — o app nunca trunca tabela. É tirar do
   atacante o botão de "apagar tudo de uma vez" sem afetar nada em produção.
3. **Mover o login para uma função no banco** (`SECURITY DEFINER`), que devolve o
   usuário sem o campo de senha.
4. **Revogar a leitura da coluna `senha_hash`** — só possível depois do item 3.

Depois disso, o banco ainda está legível por qualquer um. Mas os hashes saem de
circulação e o estrago possível diminui bastante.

### Opção B — Token próprio + RLS  ← **recomendada**
**Esforço:** 1 a 2 semanas · **Risco:** médio · **Proteção:** alta

Mantém o login por CPF e senha como está hoje. A diferença: ao entrar, uma Edge
Function assina um token dizendo quem é a pessoa e qual o perfil dela. O app passa
a mandar esse token em cada requisição, e as políticas de RLS finalmente têm em
quem se basear — "visitador só enxerga as visitas dele", "só admin altera
instituição", e assim por diante.

Resolve o problema de verdade sem jogar fora o sistema de login que já funciona e
que a equipe já conhece. É o melhor equilíbrio entre esforço e resultado.

### Opção C — Migrar para o Supabase Auth
**Esforço:** várias semanas · **Risco:** alto · **Proteção:** alta

O caminho canônico. Em troca, exige migrar os 15 usuários, refazer as telas de
login e de senha, e revisar cada consulta do app. Faz sentido como destino de
longo prazo — não como resposta a este alerta.

---

## 7. Recomendação

**Fazer a Opção A agora** e **planejar a Opção B** para as próximas semanas.

O raciocínio: a Opção A é barata, reversível e não depende de decisão maior. Ela
não fecha a porta, mas tira da mesa o que é mais sensível — os hashes de senha e
a possibilidade de apagar tudo de uma vez. Serve de ponte enquanto a Opção B, que
é a correção real, é feita com calma e testada direito.

O que **não** recomendo é ligar RLS nas tabelas sem antes ter o token da Opção B.
Isso derrubaria o app inteiro na hora, porque nenhuma consulta passaria. É um erro
fácil de cometer clicando em "Resolver problema" no e-mail do Supabase.

---

## 8. Sobre os outros alertas do e-mail

| Alerta | Gravidade real |
|---|---|
| `rls_enabled_no_policy` (12 tabelas `_bkp_*`) | **Nenhuma** — essas são as únicas tabelas *fechadas* do banco. O alerta é informativo. Ver ressalva no item 6-A antes de apagá-las. |
| `function_search_path_mutable` (26 funções) | Baixa — boa prática, sem exposição direta aqui. |
| `extension_in_public` (`pg_net`) | Baixa. |
| Funções `SECURITY DEFINER` executáveis (2) | Média — `auto_cancelar_agendamentos_72h` e `executar_auto_checkout` podem ser disparadas por qualquer um. Vale revogar; é rápido. |

---

## 9. Nota sobre os e-mails

Os alertas do Supabase são legítimos e chegam toda semana. Ainda assim, o próprio
rodapé sugere não clicar nos links e entrar direto pelo painel — em Advisors, na
barra lateral. É um bom hábito: aviso de segurança é justamente o formato que
golpistas mais copiam.
