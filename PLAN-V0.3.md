# PLAN v0.3 — concorrência, resíduos e divergências

Plano de execução para o **squirrel-mode**, escrito para ser orquestrado por uma sessão de IA
(Cursor, Claude Code ou Codex) atuando como **tech lead**, delegando toda implementação a subagentes.

Este documento é **autossuficiente**: não depende de nenhuma conversa anterior. Quem orquestra precisa
apenas dele, do repositório, e das restrições da seção 9.

---

## 1. Estado hoje — ponto de partida

| | |
|---|---|
| Repositório | `thgMatajs/squirrel-mode`, público |
| `HEAD` | `65ea96f` na `main`, árvore limpa |
| Última release | **v0.2.0**, tag e Release marcados como Latest |
| Suíte | `sh tests/run.sh` → **1591 assertions, 10 arquivos, exit 0** |
| Qualidade | `shellcheck --shell=sh -x` limpo · zero drift · `claude plugin validate .` passa |
| Aceite | **7 `met` · 4 `observed` · 8 `manual`** de 19 critérios |

Alvo deste plano: **v0.3.0**.

Leitura obrigatória antes de começar: `PLAN.md` (o plano original, seções 3 e 5), `CONTEXT.md`,
`docs/ACCEPTANCE.md`, `docs/adr/*.md`, e `rules/base-rules.md` (as 16 regras, fonte única de verdade).

---

## 2. A correção que vem antes do plano

O objetivo declarado é "zerar divergências, resíduos e defeitos". Duas partes disso são impossíveis
como enunciadas, e o plano diz isso em vez de fingir que entrega:

**Critérios `manual` não podem ser zerados por este plano.** `manual` significa "exige uma sessão
interativa real que nenhuma automação alcança". Três deles dependem literalmente do Thiago: o critério
10 precisa de uma tool de Jira conectada e autorizada, o 13 precisa de instalar e desinstalar na
máquina dele, o 7 precisa do perfil escrito dele. O que este plano **pode** fazer é converter os que
são probeáveis para `observed` via cadeias de probe mais longas — e `observed` é deliberadamente mais
fraco que `met`: uma observação de um sistema não-determinístico. **Nenhum step deste plano tem
permissão de marcar um critério como `met` com base em probe.**

**Alguns "resíduos" são decisões, não dívidas.** Vários limites declarados no código foram escolhidos
de propósito, com o raciocínio escrito ao lado. Zerá-los às cegas contradiz a regra que este projeto
aprendeu do jeito difícil: *um guard que barra trabalho correto é pior que guard nenhum.* O step P4
trata cada um com um veredito explícito — **fechar** ou **reafirmar** — nunca "sumir com a linha".

---

## 3. A descoberta que reduz o escopo pela metade

O medo original era "2 sessões de Claude Code + 1 de Cursor" como um cenário de caos compartilhado.
Ele não é. Verificado lendo os artefatos gerados:

| Estado | Claude Code | Codex | Cursor |
|---|---|---|---|
| `~/.squirrel/profile.md` | lê no `SessionStart` | lê (`targets/codex/AGENTS.md:6`) | lê (`.mdc`) |
| Checkpoints | **sim**, escreve | não existe | não existe |
| Flag de `off` | **sim**, via hook | não existe | não existe |

`targets/codex/AGENTS.md:108` e `targets/cursor/squirrel-mode.mdc:113` afirmam explicitamente que
nenhuma regra assume a existência de checkpoint em nenhum target.

**Consequência:** o único estado compartilhado entre ferramentas é o **perfil**, e ele é
predominantemente leitura. Concorrência de checkpoint e de flag `off` é um problema **interno ao
Claude Code**, entre sessões dele. Isso é bem menor do que parecia — e o plano deve ser dimensionado
para o problema real, não para o susto.

---

## 4. O princípio de desenho

Escrito aqui porque toda decisão técnica dos steps P1 e P2 deriva dele:

> **Scripts fazem o trabalho sensível a concorrência — eles podem travar com `mkdir` e renomear
> atomicamente. O modelo só escreve em arquivo que ele possui em exclusividade.**

O modelo escreve via as tools `Write`/`Edit`, em duas chamadas separadas (lê, depois escreve). Não há
como travar isso. Então a correção **não** é adicionar lock a estado compartilhado: é **eliminar o
estado compartilhado** para que não haja corrida.

Precedente já no repositório: `targets/codex/install.sh` usa lock por `mkdir` (atômico em POSIX) e
escrita por temp-file + rename. Reutilize o idioma; não invente outro.

---

## 5. Como orquestrar

### 5.1 O ciclo

```
implementa → AUDITORIA de escopo → review → corrige → review → corrige
                                   └────────── 2 ciclos ──────────┘
```

Um step é aceito quando um review volta sem BLOCKER/MAJOR, **ou** os 2 ciclos acabaram e o
orquestrador aceita o resíduo **explicitamente e por escrito** no arquivo de checkpoint.

### 5.2 Os quatro papéis — subagentes diferentes, contexto fresco cada um

**IMPLEMENTADOR.** Escreve o código e os testes. Recebe contrato, guardrails e checklist. Deve
argumentar contra qualquer instrução que considere errada em vez de obedecer — várias correções deste
projeto vieram de um subagente discordando de uma decisão do tech lead que estava errada.
*Limites:* não commita, não faz push, não muda escopo, não toca arquivo fora do contrato.

**AUDITOR DE ESCOPO.** Roda **antes** do review de defeitos e responde uma pergunta só: *foi entregue
exatamente o que foi pedido — nem menos, nem mais?* Compara o diff item por item contra o contrato.
Reporta três listas: **faltou**, **sobrou** (escopo não pedido, refactor oportunista, arquivo extra),
e **divergiu** (feito de forma diferente da contratada). É read-only.
*Limites:* não julga qualidade nem procura bug — isso é do reviewer. Não edita nada.

**REVIEWER.** Read-only e adversarial. Procura o que está errado, **constrói a condição de falha e
reproduz**. Não confia no relatório de ninguém. Classifica BLOCKER / MAJOR / MINOR, cada achado com
reprodução exata e o que uma correção precisaria fazer.
*Limites:* não edita, não cria, não apaga, não commita. Se acha que o contrato em si está errado,
argumenta — não implementa.

**FIXER.** Corrige os achados listados, e só eles.
*Limites:* não refatora, não adiciona check não pedido, não muda escopo. Se um achado for impossível
ou piorar o resultado, argumenta com reprodução em vez de implementar algo que considera pior.

### 5.3 O orquestrador

Nunca implementa. Delega, audita e libera. Além disso:

- **Verifica por conta própria antes de aceitar.** Roda a suíte, reproduz o ataque principal, confere
  o artefato. Relatório de subagente **não é evidência**.
- Um fix que adiciona um guard é **superfície nova** — revise-o como código novo, não só contra o
  achado original. Num step deste projeto, os três MAJOR do segundo review tinham sido *introduzidos
  pelo fix do primeiro*.
- 1 commit por step aceito, depois push. Atualiza o arquivo de checkpoint com o que foi feito, os
  achados e os resíduos.
- Mantém um arquivo de checkpoint de orquestração (sugestão: `.build-checkpoint-v03.md`, gitignored)
  para não perder estado entre sessões.

### 5.4 A armadilha que pegou este build dez vezes

**"Guard que não pode falhar para o próprio alvo."** Dez vezes um teste pareceu cobrir algo e cobria
nada. Toda asserção nova precisa ser **mutation-provada contra o texto atual** — aplique a mutação,
veja a asserção ficar vermelha nomeando o alvo, cole a saída. Uma asserção que passa porque o padrão
casou zero linhas é pior que asserção nenhuma.

A forma mais sutil: quando duas funções compartilham uma correção, verifique que **cada uma** tem
cobertura própria. Num caso aqui, reverter os âncoras de uma delas deixou a suíte inteira verde,
porque toda prova existente exercitava apenas a outra.

---

## 6. Cronograma — sequência, dependências e o que roda em paralelo

```
P0  reproduzir  ████  ← TRAVA TUDO. Nada começa antes de fechar.
                 │
     ┌───────────┴───────────┬─────────────┐
     ▼                       ▼             ▼
P1  checkpoint  ██████   P2  off  ███   P4  resíduos  ████
     (o maior)            (independente)  (independente de P1/P2)
     │                       │             │
     └───────────┬───────────┘             │
                 ▼                         │
P3  perfil  ███  (independente, mas        │
                  encoste em P1/P2 para    │
                  não competir por hook)   │
                 │                         │
                 └───────────┬─────────────┘
                             ▼
                 P5  aceite  ████   ← precisa de P1, P2, P3 fechados
                             │
                             ▼
                 P6  ADR + release  ██
```

**Dependências reais, e só elas:**

| Step | Depende de | Por quê |
|---|---|---|
| P0 | — | Trava tudo: P1 não pode ser desenhado antes de saber se o `SessionStart` traz `session_id` |
| P1 | P0 (itens 1 e 3) | O desenho do caminho depende do payload do hook |
| P2 | P0 (item 2) | Só do probe de reprodução |
| P3 | — | Mas toca o `UserPromptSubmit`, igual P2. **Não rode P2 e P3 em paralelo** se forem editar o mesmo script |
| P4 | — | Totalmente independente. Bom candidato para rodar em paralelo com P1 |
| P5 | P1, P2, P3 | Os probes deles são a evidência `observed` |
| P6 | P5 | Um release não sai com o documento de aceite desatualizado |

**Sugestão de sequenciamento com dois trilhos:**

| Fase | Trilho A | Trilho B |
|---|---|---|
| 1 | **P0** — sozinho, trava tudo | — |
| 2 | **P1** (o maior: caminho, pickup, matriz de ataque, regra 14, migração) | **P4** (resíduos, veredito um por um) |
| 3 | **P2** (binding por token) | — |
| 4 | **P3** (perfil) | — |
| 5 | **P5** (aceite) | — |
| 6 | **P6** (ADR + release) | — |

**Tamanho relativo**, para dimensionar expectativa — não são horas, é peso: P1 é de longe o maior
(cinco entregas, incluindo mudança de regra que regenera artefatos). P0 e P4 são médios. P2, P3, P5 e
P6 são pequenos. Cada step carrega o seu ciclo completo de auditoria + 2× review/fix, e nos steps
grandes é o ciclo que domina o tempo, não a implementação.

**Regra de parada:** se P0 não conseguir reproduzir o lost update, **pare e reporte** antes de
implementar P1. Corrigir um defeito que não se consegue reproduzir é como este projeto ganharia um
guard que não pode falhar — só que na arquitetura, não no teste.

---

## 7. Os steps

### P0 — Reproduzir antes de corrigir. **Trava todo o resto.**

A história deste projeto diz que raciocínio estático sobre hooks e permissões está errado até ser
probado ao vivo. Os dois defeitos mais caros do build (o diretório protegido, e o Release apontando
para a versão quebrada) eram invisíveis para uma suíte de 1500 asserções.

**Contrato:**

1. **Reproduza o lost update.** Duas sessões `claude -p --session-id <uuid>` paralelas no **mesmo**
   cwd de scratch, cada uma completando uma unidade de trabalho. Observável: uma entrada do Done log
   desaparece, ou o `## Doing` de uma sobrescreve o da outra.
2. **Reproduza o `off` ligando na sessão errada.** Duas sessões no mesmo cwd; `/squirrel:off` em uma;
   a outra manda prompt primeiro. Observável: a sessão errada perde as regras.
3. **Verifique se o payload do `SessionStart` carrega `session_id`.** *Todo o desenho de checkpoint
   por sessão depende disso e ninguém confirmou.* Instrumente o hook para gravar o JSON de stdin
   cru num arquivo de scratch e leia. **Se não carregar**, o fallback nomeado é o hook
   `UserPromptSubmit`, que comprovadamente carrega (ver o header de `scripts/check-off-flag.sh`) — e
   o desenho de P1 muda para materializar o caminho no primeiro prompt, não no início da sessão.
4. **Meça se dez turnos encadeados são práticos.** S9 e S10 só chegaram a três turnos via
   `--session-id`/`--resume`. Os critérios 3 e 9 pedem dez. Estabeleça se dá, e quanto custa.

**Definition of done:** os três primeiros reproduzidos com log colado, ou declarado não-reproduzível
com a evidência de por quê. O item 3 respondido com o JSON cru. Os probes 1 e 2 viram **os gates de
aceite** de P1 e P2 — o mesmo probe tem que passar depois.

**Guardrails:** `env HOME=<scratch>` como primeiro token, sempre. Nunca toque o `~/.squirrel` real —
existe um checkpoint e um perfil de verdade lá.

---

### P1 — Concorrência de checkpoint

**Desenho contratado:** um arquivo por sessão, propriedade exclusiva.

```
~/.squirrel/checkpoints/<slug>/<session-id>.md
```

O hook injeta o caminho completo; o modelo nunca calcula slug nem descobre session id sozinho
(decisão já registrada: o modelo não pode computar o algoritmo do slug). `/squirrel:pickup` lê o
**diretório** e dobra os arquivos por mtime. O `SessionStart` poda arquivos por idade.

**Explicitamente fora de escopo nesta versão:** consolidar os arquivos num histórico canônico dentro
do hook. Seria um modo de falha novo dentro de um hook cujo contrato é "nunca sair com status
não-zero" — o mesmo absoluto que P4 vai auditar. Só entra se os probes mostrarem que a dobra em
tempo de leitura ficou ruidosa.

**Contrato:**

1. Caminho por sessão implementado no `scripts/load-profile.sh`, com o resultado de P0 item 3 como
   base. Sanitize o session id como `scripts/check-off-flag.sh` já faz com o dele.
2. `/squirrel:pickup` dobra o diretório. Ordem de saída inalterada: Recent wins → You were doing →
   Next action → Open decisions, e para.
3. **Re-prove a fronteira do `PreToolUse` para o formato aninhado** `checkpoints/<slug>/<session>.md`.
   A matriz de ataque de `scripts/allow-checkpoint.sh` foi construída para o layout plano. Rode-a
   inteira de novo: legítimo → `allow`; traversal, prefix-escape, decoy aninhado, spoof de
   `file_path` no topo, `Bash`, e o caminho antigo → `defer`. **Não assuma que continua valendo.**
4. **Regra 14 muda de texto.** O "Done log das últimas 10 entradas" precisa ser redefinido (por
   arquivo? dobrado na leitura?). Mudança de regra regenera artefatos via `sh scripts/build.sh` e bate
   nos checks de paridade cross-target e de drift. Orce isso como trabalho, não como detalhe.
5. **Migração dos arquivos planos `<slug>.md` já existentes.** Duas opções, escolha uma e registre:
   (a) detectar-e-avisar, precedente do v0.2.0; (b) dobrar na primeira leitura, defensável porque
   estes são arquivos **do próprio plugin**, não do usuário. Recomendação: (b), com aviso.

**DoD:** o probe 1 de P0 re-rodado **passa** — duas sessões paralelas, nenhuma entrada perdida.
Matriz de ataque verde no layout novo. Suíte verde, shellcheck limpo, zero drift, validate passa.

---

### P2 — Binding do `off` por sessão

**Problema confirmado:** o sentinela do ADR-0005 grava só o **cwd**, e `claim_pending()`
(`scripts/check-off-flag.sh:216`) entrega o sentinela para a primeira sessão cujo hook disparar com
cwd batendo. Duas sessões no mesmo diretório → `/squirrel:off` pode silenciar a errada. Os comentários
do código tratam a corrida do `mv` como benigna; ela é benigna só quando os cwd diferem, que é o caso
que ninguém testou.

**Desenho contratado:** o `SessionStart` injeta um **token opaco de sessão** no contexto. O
`/squirrel:off` grava `PENDING.<token>`. O `UserPromptSubmit` mapeia token → `session_id` e só reclama
o sentinela cujo token é o dele. A premissa do ADR-0005 continua válida e está verificada no header do
próprio arquivo: a skill não descobre o session id, o hook descobre.

**Contrato:** token validado e sanitizado espelhando `sanitize_session_id`. Decisão registrada sobre
compatibilidade com sentinelas **sem token**, de sessões antigas — reclamar por cwd como hoje, ou
descartar. Vale para `PENDING` e `CLEAR`. ADR-0005 recebe uma seção de Amendment; **preserve o
histórico, não reescreva a decisão original.**

**DoD:** o probe 2 de P0 re-rodado **passa** — `/squirrel:off` numa sessão não afeta a outra, mesmo
cwd. Mais o caso oposto: em cwd diferentes, o comportamento de hoje não regride.

---

### P3 — Perfil: escrita atômica e propagação

Único estado compartilhado entre ferramentas, então este step é o que toca o cenário cross-tool.

**Contrato — este step é uma decisão, não só implementação:** `/squirrel:tune` é uma **skill**. O
modelo escreve com a tool `Write` e **não consegue** renomear atomicamente. Então:

1. **Janela de leitura torta.** Escolha e registre: rotear a escrita por um script (que faz temp +
   rename como os installers já fazem), **ou** aceitar a janela como resíduo documentado.
   Recomendação: **aceitar** — janela minúscula, severidade baixa, e rotear a escrita por script
   significa dar ao modelo mais superfície auto-aprovada, que é exatamente onde este projeto já se
   machucou duas vezes.
2. **Propagação.** Hoje o perfil é injetado só no `SessionStart`, então um `tune` numa sessão não
   alcança outra até ela reiniciar. O `UserPromptSubmit` já roda a cada prompt: uma checagem de mtime
   + reinjeção é a correção barata. Implemente.
3. **Staleness cross-tool** (Cursor e Codex leem no cadence deles) é **documentada, não engenheirada**.
   Uma linha no `docs/OTHER-TOOLS.md`.

**DoD:** um `tune` numa sessão alcança outra sessão de Claude Code já aberta, provado ao vivo. A
decisão do item 1 escrita com o raciocínio.

---

### P4 — Resíduos, com veredito um por um

Cada item recebe **fechar** ou **reafirmar com assinatura**. Nada some sem veredito.

| # | Resíduo | Recomendação |
|---|---|---|
| 1 | `jq` presente mas **travado** pendura o hook. `timeout(1)` é GNU coreutils, ausente no macOS de fábrica | **Reafirmar.** Já foi provado não-portável; o header declara o limite honestamente e o timeout de hook do harness limita o dano. Tentar watchdog em background mexe no hook que "nunca falha" — mau negócio |
| 2 | `scripts/load-profile.sh:56` afirma *"must NEVER exit non-zero and must always print valid JSON"* — absoluto nunca auditado | **Fechar.** Este é o pass próprio que foi prometido e nunca aconteceu. Audite: construa a condição que quebra a afirmação, e então ou conserte, ou reescreva a afirmação para o que é verdade |
| 3 | Invariante 15 não cobre duplicata em `__Status:__` ou outras grafias de ênfase | **Reafirmar.** Decisão deliberada: o guard é para drift acidental, e drift acidental copia a forma das linhas vizinhas |
| 4 | Invariante 15 não cobre linha em formato de status **fora** das 19 seções | **Reafirmar**, limite já escrito |
| 5 | O containment da lista `manual` não pega **exclusão** de um número | **Reafirmar.** O status daquele critério segue preso por outros dois checks |
| 6 | `flatten_acceptance_section` pode dar falso positivo dentro de um parágrafo | **Fechar se barato, reafirmar se não.** Julgue pelo custo |

**Guardrail deste step:** se fechar um item exigir um guard que barre trabalho correto, **não feche** —
reafirme com o limite escrito. Este projeto já apagou dois guards exatamente por esse motivo.

---

### P5 — Critérios de aceite novos e conversão do que é probeável

**Contrato:**

1. **Critérios novos** para concorrência, escritos no formato de `docs/ACCEPTANCE.md`: duas sessões
   paralelas não perdem entrada de checkpoint; `off` liga na sessão certa; `tune` propaga. Os probes
   de P0 re-rodados verdes são a evidência `observed`.
2. **Tente converter os probeáveis.** Critérios 3 e 9 pedem dez turnos; use cadeias
   `--session-id`/`--resume` conforme o resultado de P0 item 4. Critério 6 (`/squirrel:init`) e 8
   (`/squirrel:tune`) podem ser alcançáveis headless. **Máximo permitido: `observed`.** Nunca `met`.
3. **Atualize os três lugares** onde um status vive: a linha `**Status:**` da seção, a linha da
   tabela-resumo, o parágrafo de contagem. O invariante 15 falha se você esquecer um — é para isso
   que ele existe.
4. Convenção em vigor, escrita na legenda do documento: **o status de um critério acompanha o ramo
   nomeado menos coberto.** Respeite-a.

**DoD:** contagem nova derivada do arquivo, independente do parser do próprio teste. Nenhum critério
marcado além do que a evidência sustenta.

---

### P6 — ADR e release v0.3.0

1. **ADR novo** para o modelo de concorrência. Passa nos três testes: difícil de reverter, surpreende
   sem contexto, resultado de trade-off real. Registre a alternativa rejeitada (lock em estado
   compartilhado) e por quê.
2. **Amendment no ADR-0005** para o binding por token. Histórico preservado.
3. **README** atualizado: a limitação de multi-sessão que o v0.2.0 documentou como conhecida sai, e a
   matriz de paridade reflete o que mudou.
4. **Checklist de release — três artefatos, três checagens.** Esta é a lição de ontem, e ela custou
   uma tag reescrita:
   - `.claude-plugin/plugin.json` com `"version": "0.3.0"` **no mesmo commit**. O
     `claude plugin validate` **não** compara manifesto com tag — passou verde em dois releases
     anunciando versão errada.
   - tag `v0.3.0` anotada, apontando para esse commit.
   - **Release no GitHub, marcado `--latest`.** Tag empurrada **não é** Release: o v0.1.1 quebrado
     ficou marcado como Latest mesmo depois do conserto ter sido publicado.

---

## 8. Devolvido para o Thiago — o que nenhum agente resolve

| Critério | Por que precisa dele |
|---|---|
| 10 | Digerir um ticket de Jira com a tool **conectada e autorizada** |
| 13 | Instalar, desinstalar e reinstalar na máquina, conferindo que `~/.squirrel/` sobrevive |
| 7 | Respostas obedecendo o **perfil escrito dele**, injetado no `SessionStart` |

E a maior de todas, que não é um critério: **ninguém nunca usou este plugin de verdade.** Zero
usuários, zero sessão de trabalho real. Uma semana de uso vai gerar uma lista diferente desta, e
provavelmente mais curta e mais importante.

---

## 9. Restrições em vigor — todo prompt de subagente repete estas

**Git**
- Subagente **nunca** roda `git stash`, `git reset`, `git checkout --` nem `git clean`. Um stasheou a
  árvore inteira neste projeto. Só o orquestrador roda `git commit` e `git push`.
- Subagente **faz `git add`** do que tocar — os testes de invariante descobrem arquivos via
  `git ls-files`, então arquivo untracked passa invisível.
- Commit como `Thiago Matajs <35839277+thgMatajs@users.noreply.github.com>` (forma noreply, para não
  vazar e-mail corporativo em repo público).
- Auth por comando: `GH_TOKEN=$(gh auth token -u thgMatajs)`. A conta `gh` global é `thgPacheco`
  (corporativa) e **tem que continuar sendo** — não troque o login global.

**Segurança e sistema de arquivos**
- Testes usam `HOME` temporário. **Nunca** toque `~/.claude`, `~/.squirrel`, `~/.codex`, `~/.cursor`,
  `~/.agents` reais. Existem um checkpoint e um perfil de verdade em `~/.squirrel/` — mais crítico
  agora do que antes, não menos.
- Em runtime o plugin escreve só em `~/.squirrel/`.
- Sem chamada de rede e sem telemetria em nada distribuído.
- `.claude` é **diretório protegido** do Claude Code: a checagem de segurança roda antes das regras de
  permissão e nenhum hook a atravessa. Foi o que quebrou o v0.1.1. Não desenhe nada que escreva lá.

**Código**
- POSIX `sh` estrito: sem `[[ ]]`, sem arrays, sem `${var,,}`, sem `source`.
  `shellcheck --shell=sh -x` limpo.
- `trap EXIT` em POSIX sh **substitui**, não empilha.
- `awk -v` processa escapes de barra invertida — cuidado ao passar padrões.
- Toda mudança em `rules/base-rules.md` exige `sh scripts/build.sh` e commit dos artefatos gerados; o
  CI falha se derivarem.
- Se `grep`/`cat` do ambiente estiverem atrás de proxy, use `/usr/bin/grep` e `/usr/bin/sed` por
  caminho absoluto para qualquer checagem byte-exata.

---

## 10. Metodologia de probe ao vivo

Foi assim que os defeitos que importavam apareceram. A suíte estática passava por cima de todos.

- `claude -p --plugin-dir . "<prompt>" < /dev/null` — o `< /dev/null` é **obrigatório**: várias
  chamadas em sequência no mesmo script deixam as últimas com stdin consumido e uma volta **vazia**.
- Multi-turno: `--session-id <uuid>`, depois `--resume <uuid>`. **Nunca `--continue`** — ele retoma a
  conversa mais recente *do diretório*, que é a própria sessão do orquestrador, e pendura.
- `env HOME=<scratch>` sempre como **primeiro token**, antes de qualquer pipe.
- Retrato do `$HOME` antes e depois, e confira.
- Uma resposta headless vazia isolada **não é** defeito. Rode a matriz de controle antes de concluir
  qualquer coisa: prompt trivial com e sem plugin, e o mesmo prompt sem plugin.
- Um probe é **uma** observação de sistema não-determinístico. Evidência de que a regra dispara, não
  prova de que sempre dispara. É por isso que `observed` existe e é mais fraco que `met`.
