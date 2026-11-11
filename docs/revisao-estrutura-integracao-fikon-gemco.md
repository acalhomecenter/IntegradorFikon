# Revisão de estrutura: integração Fikon ↔ Gemco

Revisão feita em 04/11/2026, só com leitura. Foram analisados o **IntegradorFikon** (Windows Service) e a **ApiAcal** (webhooks da Fikon e telas de pedido). As procedures foram lidas no dev (`DB-TREINO`). As linhas citadas referem-se ao código dessa data, já com as correções de faturamento e cancelamento feitas no mesmo dia.

> **Correção sobre o achado A1:** o relatório sugere trocar `sqlEx.Message.Contains("50001")` por `sqlEx.Number`. Não funciona assim: o `CATCH` da `SP_FIKON_CANCELAR_NOTA` relança qualquer erro com `THROW 50000`, então `Number` é sempre 50000 e o código original só aparece no texto. A forma robusta é a procedure relançar com números próprios (por exemplo, 50001 para "não encontrada ou já cancelada") ou devolver um código de retorno.

---

## 1. Diagnóstico da estrutura atual

- **Dois processos escrevem nas mesmas tabelas** (`MOV_SAIDA`, `MOV_ITSAIDA`, estoque e `FIKON_INTEGRACAO_PEDIDO`) **sem coordenação entre si.** Um é o IntegradorFikon (.NET 4.5), que faz polling na Fikon e envia cadastros. O outro é a ApiAcal (Web API 2, .NET 4.6.1), que recebe webhooks e ações de usuário.
- **Os "repositórios" fazem tudo.** `FikonRepositorio` (~1.230 linhas) e `PedidoFikonRepositprio` (~1.420 linhas) juntam numa só classe cliente HTTP, parse de JSON, regra de negócio, SQL e log. Tudo é criado com `new`, em campos `static readonly`, e não há injeção de dependência.
- **A máquina de estados do pedido tem quatro escritores.** O status (`FALTA PASSAR NO CXA → LIBERADO CXA → FATURADO PARCIAL/FATURADO → LIBERADO CXA`) é gravado pelo integrador, pela ApiAcal, pela `SP_FIKON_CANCELAR_NOTA` e pela `SP_FIKON_INTEGRA_MOV_ITSAIDA`. Os status são texto livre.
- **Ninguém garante idempotência.** O C# confere antes e só depois executa (check-then-act), e as procedures inserem sem conferir nada.
- **Há código duplicado entre os dois projetos.** Estão repetidos `executaQuery`, `RegistrarErroConsultaStatus`, a regra de nota ativa (duas versões), a regra de série (duas versões, com comportamento diferente), as classes de conexão e o nome `FaturamentoIntegracaoPedido`, usado para duas classes diferentes.

## 2. Achados priorizados

### Crítico
| # | Achado | Onde | Impacto | Correção |
|---|---|---|---|---|
| C1 | Credenciais no código e no git: usuário `sa`, usuário `app` e chaves Bearer. O ambiente é escolhido comentando linhas; na ApiAcal, a chave de produção é sobrescrita pela de dev | `Conexao\*.cs` dos dois projetos; `FikonRepositorio.cs:22` | Quem tem acesso ao repositório tem acesso `sa` ao ERP; um deploy errado envia dados para o ambiente errado | Rotacionar senhas e chaves; login SQL dedicado com permissões mínimas; configuração criptografada por ambiente; limpar o histórico |
| C2 | SQL concatenado com o JSON (`"'" + jcontent + "'"`), executado como `sa` | `FikonRepositorio.cs:123, 242, 368, 430, 491`; `PedidoFikonRepositprio.cs:123` | Um apóstrofo comum quebra o INSERT e o erro é engolido; um texto malicioso executa SQL | Um único log parametrizado; eliminar `executaQuery` |
| C3 | Timers de 1 e 5 min sem `await`, sem proteção contra reentrância e com `Thread.Sleep(5000)` por item | `IntegradorService.cs`; `FikonRepositorio.cs:277, 339, 401, 462` | Teto de ~12 itens/min; execuções sobrepostas reenviam os mesmos itens; threads presas; exceções somem; os timers podem ser coletados pelo GC | Um laço `while + Task.Delay` por fluxo, sem `Sleep`; `OnStop` cancela e espera o trabalho em andamento |
| C4 | `HttpClient`, `response` e `jcontent` guardados em campos de instância compartilhada na ApiAcal | `PedidoFikonRepositprio.cs:24-26`; `PedidosRepositorio.cs:51-56` | Duas integrações simultâneas podem trocar respostas; um pedido pode receber a chave Fikon de outro | Usar só variáveis locais; repositórios sem estado |
| C5 | Idempotência não garantida no banco (faturamento, cupom, devolução) | `ConsultarNotaNoGemco` seguido de `ExecutarIntegracaoMovSaida`, em conexões separadas; `IntegrarCupomMovSaida` não confere nada | Duas instâncias ou um webhook repetido gravam em duplicidade, ou o evento entra em loop de erro e reenvio | Tabela de controle com chave única, gravada na mesma transação (seção 3) |

### Alto
- **A1 – Um evento com erro rejeita o lote inteiro** (`FikonController.cs`). A Fikon reenvia o lote, e o evento com problema bloqueia todos os seguintes. O processamento é síncrono: se demorar mais que o timeout do webhook, o mesmo evento passa a rodar duas vezes em paralelo.
- **A2 – Lost update entre integrador e cancelamento.** O integrador grava `FATURADO` por cima do `LIBERADO CXA` que o cancelamento acabou de gravar, e a nota nova nunca é integrada. Correção: `UPDATE ... WHERE id=@id AND STATUS=@lido`, conferindo o rowcount.
- **A3 – `HttpClient`.**
  - Um `new HttpClient()` por chamada, sem timeout e sem retry.
  - Qualquer resposta diferente de 200 marca o item com erro definitivo ('E'), mesmo um 503 ou 429 transitório.
  - `StatusCode.ToString()=="OK"` trata 201 como erro.
  - Correção: um cliente único, com retry e backoff para 429/5xx/timeout.
- **A4 – Baixa do outbox de cadastros pela chave natural** (`WHERE status='P' and codprod=...`). Marca como enviada uma linha nova que nunca foi enviada. Correção: dar baixa pelo `id` da linha.
- **A5 – Polling sem limite e sem estado final.** Pedido nunca pago ou parcial fica na fila para sempre; o caso "cancelada no Gemco" grava log a cada 30 s (~2.880 linhas/dia por pedido). As consultas não têm `TOP` nem paginação, e o filtro com `UPPER(LTRIM(RTRIM(...)))` impede o uso de índice.
- **A6 – Filial 502 fixa** em `ExecutarAtualizacaoStatusPedidoGemco` (`FikonRepositorio.cs:640`), embora a restrição a 502 tenha sido comentada na ApiAcal.
- **A7 – Tipos numéricos.**
  - Dinheiro em `float` (`FaturamentoIntegracaoPedido.cs`): perde centavos em valores altos.
  - Quantidade em `int`: quantidade fracionada (metro, kg) quebra o webhook.
  - `pNumNota.Scale = 2` no lugar de `pQuantidade.Scale` (`PedidoFikonRepositprio.cs:1346`).
- **A8 – Erros devolvidos como string ou `null`, e catch vazio.** Uma falha do banco vira "nada pendente". `devolverNotaGemco` devolve `""` quando a devolução falha.

### Médio
- **M1 – Cupom.**
  - Grava o `totalNegociado` e todo o financeiro da venda numa única nota, mesmo que ela tenha só parte dos itens.
  - `Convert.ToDateTime(horaEmissao)` recebe só a hora, então a data vira a do processamento.
  - Formas de pagamento ainda com valores "AJUSTAR".
- **M2 – Devolução.** A chave de saída vem só do primeiro produto; `tipoTransacao.Equals` dá erro quando o campo vem nulo; NFC-e não é tratada.
- **M3 – ADO.NET.** `AddWithValue`, readers não descartados, sem `CommandTimeout`, N+1 na carga de produtos, SP e status em conexões separadas, `NOLOCK` na fila de controle.
- **M4 – Integração de pedido.**
  - Um duplo clique cria dois pedidos na Fikon.
  - Se o controle falhar depois do POST, o pedido fica órfão na Fikon.
  - O cancelamento apaga a linha de controle e o histórico se perde.
- **M5 – Flags de execução dos timers** são `bool` comuns, sujeitas a condição de corrida.
- **M6 – Observabilidade.** O EventLog recebe "Monitorando" a cada minuto; não há correlation id nem métricas de fila.

### Baixo
- `async void` em `insereProdutoFikonTodos`/`insereClientesFikonTodos`.
- Objetos criados e nunca usados.
- `debug="true"` no `Web.config`.
- Projetos sem uso na solução.
- Nomes com erro de digitação (`Repositprio`).

### Avaliação da correção de faturamento de 04/11
A direção está certa: filtrar a nota ativa, pular a que já foi gravada, não mudar o status quando há erro e devolver o PARCIAL para a fila. Os pontos fracos estruturais:

- a deduplicação é feita na aplicação e não é atômica (C5);
- o lost update com o cancelamento continua (A2);
- PARCIAL e "cancelada no Gemco" não têm estado final (A5);
- `NotaEstaAtiva` considera a nota ativa quando o status não vem no payload. Quando a Fikon garantir o envio de `statusNotaCodigo`, inverter: logar e pular.

## 3. Estrutura-alvo (.NET Framework, sem reescrever tudo)
1. **Biblioteca compartilhada `Acal.Fikon.Core` (net48)**, com:
   - `FikonApiClient` (um `HttpClient` estático, timeout, Polly);
   - DTOs com `decimal`;
   - regras de nota e série num lugar só;
   - acesso a dados parametrizado;
   - log de integração.

   Subir o integrador para .NET 4.8.
2. **Configuração externa e criptografada** por ambiente, com login SQL dedicado.
3. **Fila de controle com claim por registro**, para permitir várias instâncias. A instância "pega" itens com `UPDATE TOP (@lote) ... WITH (UPDLOCK, READPAST, ROWLOCK) OUTPUT ...`. Junto vêm tentativas com backoff, estados terminais, dead-letter com alerta e um índice em `(STATUS, PROXIMA_TENTATIVA)`.
4. **Inbox de webhooks.** Tabela com chave de idempotência única. O controller só grava o evento (duplicado conta como sucesso) e responde 200; um worker processa. Um evento com problema deixa de bloquear os demais.
5. **Idempotência no banco.** Uma procedure wrapper com `XACT_ABORT` grava `FIKON_NOTA_INTEGRADA` (com chave única) na mesma transação da gravação. Atenção ao `@@TRANCOUNT`, porque as procedures internas já abrem transação.
6. **Outbox de cadastros com claim e baixa por `id`.** Retry classificado por tipo de erro, sem `Sleep`.
7. **Logging estruturado** (NLog ou Serilog) com correlation id.
8. **Injeção de dependência simples e testes unitários** das regras, usando JSON real da Fikon como fixture.

**Primeiro passo:** rotacionar os segredos e encontrar a segunda instância do integrador. Enquanto a fila não existir, usar `sp_getapplock` por fluxo no início de cada ciclo, para que só uma instância rode.

## 4. Roteiro
| Etapa | Conteúdo | Esforço |
|---|---|---|
| 0 – Contenção | Rotacionar `sa` e chaves; login dedicado; configuração externa; localizar a segunda instância; `sp_getapplock` por fluxo | 1–2 dias |
| 1 – Quick wins | Log parametrizado; fim do catch vazio; `HttpClient` único com timeout e retry; laço sem sobreposição e sem `Sleep`; fim do estado compartilhado na ApiAcal; `decimal`; bug do `Scale`; filial 502; UPDATE de status com concorrência otimista; retornos de erro reais; baixa por `id` | 4–6 dias |
| 2 – Confiabilidade | Inbox de webhooks; wrapper idempotente (faturamento, cupom, devolução); backoff e estados terminais; claim com `READPAST`; fim do `NOLOCK` na fila | 1,5–2 semanas |
| 3 – Estrutura | `Acal.Fikon.Core`; .NET 4.8 + Polly; injeção de dependência; testes; logging e painel; um dono só para a máquina de estados | 2–4 semanas |
| 4 – Escala | Paralelismo controlado (`SemaphoreSlim`); endpoints em lote; eventos da Fikon no lugar do polling | contínuo |

**A confirmar:**
- comportamento das procedures em produção (só o dev foi lido);
- se as procedures de leitura de cadastro devolvem `id`;
- efeito da filial 502 em `SP_FIKON_ATUALIZA_STATUS_PEDIDO`;
- política de reenvio e timeout dos webhooks da Fikon;
- se a Fikon trata `idDocumento` como chave de idempotência.
