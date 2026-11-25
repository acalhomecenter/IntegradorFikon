﻿﻿﻿﻿using IntegradorFikon.Conexao;
using IntegradorFikon.Models.Produtos;
using IntegradorFikon.Models.Fornecedor;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Data;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Data.SqlClient;
using System.Data.SqlClient;

namespace IntegradorFikon.Models.Fikon
{
    class FikonRepositorio : IFikonRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;
        private string ConnectionStringAplicativos = "Data Source=sqlcs;User Id=app;Password=sqlbolim;Initial Catalog=dbAplicativos";
        private static string urlBase = new ApiFikon().UrlBase;
        private static string chaveApi = new ApiFikon().ChaveApi;
        string jcontent = "";
        string jcontentAtualiza = "";
        string jcontentPreco = "";
        string jcontentForne = "";

        // Status da fila (FIKON_INTEGRACAO_PEDIDO) para pedido que não precisa mais ser consultado na FIKON:
        // já faturado ou cancelado direto no Gemco.
        private const string STATUS_FATURADO_NO_GEMCO = "FATURADO NO GEMCO";
        private const string STATUS_CANCELADO_NO_GEMCO = "CANCELADO NO GEMCO";

        // Avisos que se repetiriam a cada ciclo (ex.: nota sem chave): registrados uma vez por execução do serviço.
        private static readonly HashSet<string> avisosRegistrados = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        private static readonly object avisosLock = new object();



        public List<List<String>> executaQuery(string query, string conexao)
        {
            try
            {
                using (SqlConnection connection = new SqlConnection(conexao))
                {
                    connection.Open();

                    SqlDataReader reader;

                    List<List<String>> dadosConsulta = new List<List<String>>();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = query;

                        reader = command.ExecuteReader();

                        while (reader.Read())
                        {
                            List<String> linha = new List<String>();

                            for (int i = 0; i < reader.FieldCount; i++)
                            {
                                linha.Add(reader[i] == DBNull.Value ? null : reader[i].ToString());
                            }

                            dadosConsulta.Add(linha);
                        }
                    }

                    connection.Close();

                    return dadosConsulta;
                }
            }
            catch (Exception ex)
            {
                return null;
            }
        }

        public async void insereProdutoFikonTodos(IEnumerable<Produto> prods)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/recurso/cadastrar";

            var produtos = prods.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < produtos.Count(); i++)
            {
                //System.Threading.Thread.Sleep(1000);

                jcontent = JsonConvert.SerializeObject(produtos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    //string res = await response.Content.ReadAsStringAsync();
                    //JObject json = JObject.Parse(res);

                    //executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);

                 
                }

            
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    //executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'PRODUTO_TODOS' ," +
                                               produtos[i].codprod + "," +
                                               "getdate() ," +
                                               "'" + jcontent.ToString() + "'" +
                                               ")", ConnectionString);
                }




            }
        }


        public async void insereClientesFikonTodos(List<Models.Cliente.Cliente> cliente)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/integracao-fikon/v1/cliente";

            var clientes = cliente.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < clientes.Count(); i++)
            {
                //System.Threading.Thread.Sleep(1000);

                jcontent = JsonConvert.SerializeObject(clientes[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    //string res = await response.Content.ReadAsStringAsync();
                    //JObject json = JObject.Parse(res);

                    //executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);


                }


                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    //executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);

                    //executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                    //                           "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                    //                           "'CLIENTE_TODOS' ," +
                    //                           clientes[i].codigo + "," +
                    //                           "getdate() ," +
                    //                           "'" + jcontent.ToString() + "'" +
                    //                           ")", ConnectionString);
                }




            }
        }


        public async Task insereClientesFikon(List<Models.Cliente.Cliente> cliente)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/cliente";

            var clientes = cliente.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < clientes.Count(); i++)
            {
                try
                {

                
                //System.Threading.Thread.Sleep(1000);

                jcontent = JsonConvert.SerializeObject(clientes[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_CLIENTE WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codcli=" + clientes[i].codigo.ToString().Replace("C", ""), ConnectionString);
                    executaQuery("UPDATE FIKON_CAD_END_CLIENTE WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codcli=" + clientes[i].codigo.ToString().Replace("C", ""), ConnectionString);

                }


                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_CLIENTE WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codcli=" + clientes[i].codigo.ToString().Replace("C", ""), ConnectionString);
                    executaQuery("UPDATE FIKON_CAD_END_CLIENTE WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codcli=" + clientes[i].codigo.ToString().Replace("C", ""), ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'CLIENTE' ," +
                                               "'" +clientes[i].codigo + "'," +
                                               "getdate() ," +
                                               "'" + jcontent.ToString() + "'" +
                                               ")", ConnectionString);
                }


                }catch(Exception ex)
                {
                    // Erro de rede, timeout ou resposta que não é JSON: o registro continua 'P' e volta no
                    // próximo ciclo. Antes o erro era engolido sem log.
                    RegistrarErroEnvio("CLIENTE", clientes[i].codigo, ex, jcontent);
                }

            }
        }




        public async Task insereProdutoFikon(IEnumerable<Produto> prods)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/recurso/cadastrar";

            var produtos = prods.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < produtos.Count(); i++)
            {
                try
                {

                
                System.Threading.Thread.Sleep(5000);

                jcontent = JsonConvert.SerializeObject(produtos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codprod=" + produtos[i].codprod, ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'PRODUTO' ," +
                                               produtos[i].codprod + "," +
                                               "getdate() ," +
                                               "'" + jcontent.ToString() +"'" +
                                               ")", ConnectionString);
                }



                }catch(Exception ex)
                {
                    RegistrarErroEnvio("PRODUTO", Convert.ToString(produtos[i].codprod), ex, jcontent);
                }
            }
        }


        public async Task atualizaProdutoFikon(IEnumerable<Produto> prods)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/recurso/editar";

            var produtos = prods.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < produtos.Count(); i++)
            {
                try
                {

                
                System.Threading.Thread.Sleep(5000);

                jcontentAtualiza = JsonConvert.SerializeObject(produtos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Put, url);
                HttpResponseMessage response = await client.PutAsync(url, new StringContent(jcontentAtualiza, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate(), retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + " WHERE status='P' and tipo='A' and codprod=" + produtos[i].codprod, ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='A' and codprod=" + produtos[i].codprod, ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'PRODUTO UPDATE' ," +
                                               produtos[i].codprod + "," +
                                               "getdate() ," +
                                               "'" + jcontentAtualiza.ToString() + "'" +
                                               ")", ConnectionString);
                }

                }catch(Exception ex)
                {
                    RegistrarErroEnvio("PRODUTO UPDATE", Convert.ToString(produtos[i].codprod), ex, jcontentAtualiza);
                }


            }
        }


        public async Task insereFornecedorFikon(IEnumerable<IntegradorFikon.Models.Fornecedor.Fornecedor> forne)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/fornecedor";

            var fornecedores = forne.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < fornecedores.Count(); i++)
            {
                try
                {

                
                System.Threading.Thread.Sleep(5000);

                jcontentForne = JsonConvert.SerializeObject(fornecedores[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontentForne, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_FORNECEDOR WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='I' and codforne=" + fornecedores[i].codigo, ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_FORNECEDOR WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='I' and codforne=" + fornecedores[i].codigo, ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'FORNECEDOR' ," +
                                               fornecedores[i].codigo + "," +
                                               "getdate() ," +
                                               "'" + jcontentForne.ToString() + "'" +
                                               ")", ConnectionString);
                }


                }catch(Exception ex)
                {
                    RegistrarErroEnvio("FORNECEDOR", fornecedores[i].codigo, ex, jcontentForne);
                }

            }
        }

        public async Task inserePrecoFikon(IEnumerable<IntegradorFikon.Models.Preco.Preco> preco)
        {
            HttpClient client = new HttpClient(); // local: os timers de cadastro e de preço rodam em paralelo

            string url = urlBase + "/api-acal/api/v1/preco/cadastrar";

            var precos = preco.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < precos.Count(); i++)
            {
                try
                {

                
                System.Threading.Thread.Sleep(5000);

                jcontentPreco = JsonConvert.SerializeObject(precos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontentPreco, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {
                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PRECO WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() , retorno = " + "'" + json.GetValue("dados").ToString().Replace("'", "") + "'" + "WHERE status='P' and tipo='A' and coditprod=" + precos[i].recursoChave.Substring(0, precos[i].recursoChave.Length - 1), ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PRECO WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and tipo='A' and coditprod=" + precos[i].recursoChave.Substring(0, precos[i].recursoChave.Length - 1), ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'PRECO' ," +
                                               precos[i].recursoChave.Substring(0, precos[i].recursoChave.Length - 1) + "," +
                                               "getdate() ," +
                                               "'" + jcontentPreco.ToString() + "'" +
                                               ")", ConnectionString);
                }


                }catch(Exception ex)
                {
                    RegistrarErroEnvio("PRECO", precos[i].recursoChave, ex, jcontentPreco);
                }


            }
        }

        public async Task consultarStatusPedidosFikon()
        {
            List<PedidoIntegradoMonitoramento> pedidosPendentes = ConsultarPedidosPendentesLiberacaoCaixa();

            if (pedidosPendentes == null || pedidosPendentes.Count == 0)
            {
                return;
            }

            using (HttpClient statusClient = new HttpClient())
            {
                if (!statusClient.DefaultRequestHeaders.Contains("Authorization"))
                {
                    statusClient.DefaultRequestHeaders.Add("Authorization", chaveApi);
                }

                foreach (PedidoIntegradoMonitoramento pedido in pedidosPendentes)
                {
                    try
                    {
                        await ProcessarConsultaStatusPedidoAsync(statusClient, pedido).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Erro ao consultar pedido FIKON " + pedido.PedidoFikon + ": " + ex.Message);
                    }
                }
            }
        }

        public async Task consultarFaturamentoPedidosFikon()
        {
            List<PedidoIntegradoMonitoramento> pedidosLiberados = ConsultarPedidosLiberadosCaixaParaFaturamento();

            if (pedidosLiberados == null || pedidosLiberados.Count == 0)
            {
                return;
            }

            using (HttpClient faturamentoClient = new HttpClient())
            {
                if (!faturamentoClient.DefaultRequestHeaders.Contains("Authorization"))
                {
                    faturamentoClient.DefaultRequestHeaders.Add("Authorization", chaveApi);
                }

                foreach (PedidoIntegradoMonitoramento pedido in pedidosLiberados)
                {
                    try
                    {
                        await ProcessarConsultaFaturamentoPedidoAsync(faturamentoClient, pedido).ConfigureAwait(false);
                    }
                    catch (Exception ex)
                    {
                        RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, "Erro ao consultar faturamento do pedido FIKON " + pedido.PedidoFikon + ": " + ex.Message);
                    }
                }
            }
        }

        private async Task ProcessarConsultaStatusPedidoAsync(HttpClient statusClient, PedidoIntegradoMonitoramento pedido)
        {
            // Pedido cancelado, ou já faturado direto no Gemco, não passa mais no caixa da FIKON:
            // sai da fila sem consultar a FIKON (antes ficava sendo consultado a cada ciclo).
            SituacaoPedidoGemco pedidoGemco = ConsultarPedidoGemco(pedido.PedidoGemco);

            if (!pedidoGemco.Existe)
            {
                AvisarUmaVez("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Pedido Gemco " + pedido.PedidoGemco + " (FIKON " + pedido.PedidoFikon + ") não encontrado na MOV_PEDIDO.");
                return;
            }

            string statusResolvido = StatusResolvidoNoGemco(pedidoGemco);

            if (statusResolvido != null)
            {
                AtualizarStatusPedidoIntegrado(pedido.Id, statusResolvido);
                return;
            }

            string url = $"{urlBase}/api-acal/api/v1/pedidos/pesquisarVenda?idPedido={Uri.EscapeDataString(pedido.PedidoFikon)}";

            HttpResponseMessage response = await statusClient.GetAsync(url).ConfigureAwait(false);
            string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                RegistrarErroConsultaStatus(
                    "STATUS_PEDIDO_FIKON",
                    pedido.PedidoGemco,
                    $"Consulta do pedido FIKON retornou status {(int)response.StatusCode}. Body: {body}");

                return;
            }

            JObject json = JObject.Parse(body);

            string statusComercial =
                json.SelectToken("dadosVenda.linhaDoTempo.statusComercial")?.ToString()
                ?? json.SelectToken("linhaDoTempo.statusComercial")?.ToString()
                ?? string.Empty;

            if (!statusComercial.Equals("Passado no Caixa / Aprovado", StringComparison.OrdinalIgnoreCase))
                return;

            JToken financeiro = SelecionarFinanceiroParaAtualizacao(
                json.SelectToken("dadosVenda.financeiro") as JArray);

            if (financeiro == null)
            {
                RegistrarErroConsultaStatus(
                    "STATUS_PEDIDO_FIKON",
                    pedido.PedidoGemco,
                    $"Pedido FIKON {pedido.PedidoFikon} aprovado no caixa, mas sem financeiro retornado.");

                return;
            }

            string documento = ObterDocumentoFinanceiro(financeiro);
            string bandeira = ObterBandeiraFinanceiro(financeiro);
            string forma = ObterFormaFinanceiro(json.SelectToken("dadosVenda.financeiro") as JArray);

            bool ehCartaoCredito = forma.Equals("Cartão de Crédito", StringComparison.OrdinalIgnoreCase);

            ConveniadaCash conveniada = null;

            if (ehCartaoCredito)
            {
                if (string.IsNullOrWhiteSpace(bandeira))
                {
                    RegistrarErroConsultaStatus(
                        "STATUS_PEDIDO_FIKON",
                        pedido.PedidoGemco,
                        $"Pedido FIKON {pedido.PedidoFikon} aprovado no caixa, mas sem bandeira no retorno da FIKON.");

                    return;
                }

                conveniada = ConsultarConveniadaPorBandeira(bandeira);

                if (conveniada == null)
                {
                    RegistrarErroConsultaStatus(
                        "STATUS_PEDIDO_FIKON",
                        pedido.PedidoGemco,
                        $"Bandeira '{bandeira}' não encontrada em CASH_CONVENIADAS para o pedido FIKON {pedido.PedidoFikon}.");

                    return;
                }
            }

            // Série da nota no Gemco (ex.: U05), se a FIKON já emitiu a nota: a proc escolhe o caixa/operador da
            // FIKON_CAD_CAIXA por filial + série (script 33). Sem nota ainda, vai sem série (primeira linha da filial).
            string serieNota = null;
            JArray produtosStatus = json.SelectToken("dadosVenda.produtos") as JArray;
            if (produtosStatus != null)
            {
                List<string> documentosSemChaveStatus;
                serieNota = ExtrairFaturamentosIntegracao(produtosStatus, out documentosSemChaveStatus)
                    .FirstOrDefault(f => TemChaveAcessoValida(f.ChaveAcesso))?.Serie;
            }

            // Filial do próprio pedido (antes era 502 fixo). Caixa/operador: FIKON_CAD_CAIXA da filial;
            // o caixa "CARTOES" só quando a filial não está na FIKON_CAD_CAIXA.
            // @bandeira da proc é o NOME da bandeira na CASH_CONVENIADAS (a proc busca CODCON e taxa por ele).
            // Antes ia o CODCON (número), que nunca batia: todo cartão ficava com CODCON 1 e taxa 2,3.
            ExecutarAtualizacaoStatusPedidoGemco(
                pedido.PedidoGemco,
                pedidoGemco.Codfil,
                documento ?? string.Empty,
                conveniada?.Bandeira ?? string.Empty,
                conveniada?.Tipo ?? "DH",
                serieNota);

            AtualizarStatusPedidoIntegrado(pedido.Id, "LIBERADO CXA");
        }

        private async Task ProcessarConsultaFaturamentoPedidoAsync(HttpClient faturamentoClient, PedidoIntegradoMonitoramento pedido)
        {
            string url = urlBase + "/api-acal/api/v1/pedidos/pesquisarVenda?idPedido=" + Uri.EscapeDataString(pedido.PedidoFikon);
            HttpResponseMessage response = await faturamentoClient.GetAsync(url).ConfigureAwait(false);
            string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                // Pedido que a FIKON não devolve mais (ex.: 404 "não encontrado na base de dados") mas já foi
                // cancelado ou faturado direto no Gemco: sai da fila em vez de gravar o mesmo erro a cada ciclo.
                string statusResolvidoErro = StatusResolvidoNoGemco(ConsultarPedidoGemco(pedido.PedidoGemco));

                if (statusResolvidoErro != null)
                {
                    AtualizarStatusPedidoIntegrado(pedido.Id, statusResolvidoErro);
                    return;
                }

                RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, "Consulta do pedido FIKON retornou status " + (int)response.StatusCode + ". Body: " + body);
                return;
            }

            JObject json = JObject.Parse(body);
            JArray produtos = json.SelectToken("dadosVenda.produtos") as JArray;

            if (produtos == null || produtos.Count == 0)
            {
                return;
            }

            List<string> documentosSemChave;
            List<FaturamentoIntegracaoPedido> faturamentos = ExtrairFaturamentosIntegracao(produtos, out documentosSemChave);

            // Documento ativo sem chave de acesso (não é NF-e/NFC-e): nunca vira nota no Gemco.
            foreach (string documento in documentosSemChave)
            {
                AvisarUmaVez("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco,
                    "Documento " + documento + " do pedido FIKON " + pedido.PedidoFikon + " ignorado: está ativo, mas sem chave de acesso (não é NF-e/NFC-e).");
            }

            SituacaoPedidoGemco pedidoGemco = ConsultarPedidoGemco(pedido.PedidoGemco);

            if (faturamentos.Count == 0)
            {
                // Sem nota fiscal ativa na FIKON: se o pedido já foi faturado ou cancelado direto no Gemco,
                // sai da fila (antes ficava sendo consultado na FIKON a cada ciclo, sem fim).
                string statusSemNota = StatusResolvidoNoGemco(pedidoGemco);

                if (statusSemNota != null)
                {
                    AtualizarStatusPedidoIntegrado(pedido.Id, statusSemNota);
                }

                return;
            }

            // Só conta como faturado o item que tem ao menos uma nota fiscal ativa (cancelada ou sem chave não vale).
            bool todosItensFaturados = produtos.All(produto =>
            {
                JArray fat = produto["faturamentos"] as JArray;
                return fat != null && fat.Any(f => NotaEstaAtiva(f) && TemChaveAcessoValida(f["chaveAcesso"]?.ToString()));
            });

            string statusAtualizado = todosItensFaturados ? "FATURADO" : "FATURADO PARCIAL";

            HashSet<string> chavesProcessadas = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            bool houveErro = false;

            foreach (FaturamentoIntegracaoPedido faturamento in faturamentos)
            {
                if (!chavesProcessadas.Add(faturamento.ChaveAcesso))
                {
                    continue;
                }

                string descricaoNota = "Nota " + faturamento.NumeroNota + " série " + faturamento.Serie + " (chave " + faturamento.ChaveAcesso + ") do pedido FIKON " + pedido.PedidoFikon;

                try
                {
                    // O pedido volta para a fila após cancelamento ou faturamento parcial:
                    // nota que já está no Gemco não é inserida de novo.
                    SituacaoNotaGemco situacao = ConsultarNotaNoGemco(pedido.PedidoGemco, faturamento.NumeroNota, faturamento.Serie, faturamento.ChaveAcesso);

                    if (situacao == SituacaoNotaGemco.Ativa)
                    {
                        continue;
                    }

                    if (situacao == SituacaoNotaGemco.Cancelada)
                    {
                        houveErro = true;
                        // Registra em toda tentativa: o pedido fica na fila e é tentado de novo a cada ciclo.
                        RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, descricaoNota + " está ativa na FIKON mas cancelada no Gemco. Verificar manualmente.");
                        continue;
                    }

                    // Só grava a nota se o pedido tiver itens liberados para faturar (mesmo filtro da
                    // SP_FIKON_INTEGRA_MOV_ITSAIDA). Sem isso a SP_FIKON_INTEGRA_MOV_SAIDA grava o cabeçalho
                    // sem itens e com a data de hoje (ex.: notas 6 e 1567300 da filial 502 em 16/11/2026).
                    SituacaoPedidoGemco antesDeGravar = ConsultarPedidoGemco(pedido.PedidoGemco);

                    if (antesDeGravar.ItensFaturaveis == 0)
                    {
                        string mensagemSemItens = descricaoNota + " não foi gravada: o pedido Gemco " + pedido.PedidoGemco + " (status " + antesDeGravar.Status
                            + ") não tem itens liberados para faturar nesta filial (STATUS 5, FLLIBFAT S, TPPED R/P, FILORIG = filial).";

                        // Pedido ainda aberto sem item faturável: fica na fila, é tentado de novo a cada ciclo e o
                        // erro é registrado em toda tentativa, até ser corrigido.
                        // Pedido já faturado/cancelado no Gemco: a nota da FIKON sobrou e não há o que gravar
                        // (aviso registrado uma vez só).
                        if (StatusResolvidoNoGemco(antesDeGravar) == null)
                        {
                            houveErro = true;
                            RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, mensagemSemItens);
                        }
                        else
                        {
                            AvisarUmaVez("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, mensagemSemItens);
                        }

                        continue;
                    }

                    ExecutarIntegracaoMovSaida(pedido.PedidoGemco, faturamento.NumeroNota, faturamento.Serie, faturamento.ChaveAcesso, faturamento.DataHoraEmissao);
                }
                catch (Exception ex)
                {
                    houveErro = true;
                    RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", pedido.PedidoGemco, "Erro ao executar SP_FIKON_INTEGRA_MOV_SAIDA para a " + descricaoNota + ": " + ex.Message);
                }
            }

            // Com erro, o status não muda: o pedido continua na fila e as notas que faltam
            // são tentadas de novo no próximo ciclo (as já gravadas são puladas).
            if (!houveErro)
            {
                // Faturado em parte na FIKON, mas já resolvido no Gemco (faturado/cancelado sem item pendente):
                // sai da fila em vez de ficar como FATURADO PARCIAL consultado para sempre.
                if (statusAtualizado == "FATURADO PARCIAL")
                {
                    statusAtualizado = StatusResolvidoNoGemco(ConsultarPedidoGemco(pedido.PedidoGemco)) ?? statusAtualizado;
                }

                AtualizarStatusPedidoIntegrado(pedido.Id, statusAtualizado);
            }
        }

        // Pedido que não precisa mais de nada da FIKON: cancelado no Gemco, ou faturado (STATUS 6) sem item
        // pendente para faturar. Retorna o status da fila; null se o pedido ainda está em aberto.
        private static string StatusResolvidoNoGemco(SituacaoPedidoGemco pedidoGemco)
        {
            if (pedidoGemco == null || !pedidoGemco.Existe)
            {
                return null;
            }

            if (pedidoGemco.Status == 9)
            {
                return STATUS_CANCELADO_NO_GEMCO;
            }

            if (pedidoGemco.Status == 6 && pedidoGemco.ItensFaturaveis == 0)
            {
                return STATUS_FATURADO_NO_GEMCO;
            }

            return null;
        }

        private static bool TemChaveAcessoValida(string chaveAcesso)
        {
            string chave = (chaveAcesso ?? string.Empty).Trim();
            return chave.Length == 44 && chave.All(char.IsDigit);
        }

        // Situação do pedido no Gemco: filial, status e itens liberados para faturar com o mesmo filtro do
        // cursor da SP_FIKON_INTEGRA_MOV_ITSAIDA (STATUS 5, FLLIBFAT 'S', TPPED 'R' ou 'P', FILORIG = filial).
        // TPPED 'P' = pedido normal da loja, faturado em NF-e (ex.: DM, filial 15); exige o script 32 na base.
        private SituacaoPedidoGemco ConsultarPedidoGemco(long numpedven)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand())
                {
                    command.Connection = connection;
                    command.CommandText = @"
                        SELECT TOP 1 p.[CODFIL], p.[STATUS],
                               (SELECT COUNT(*)
                                  FROM [MOV_ITPED] i WITH (NOLOCK)
                                 WHERE i.[CODFIL] = p.[CODFIL]
                                   AND i.[TIPOPED] = 0
                                   AND i.[NUMPEDVEN] = p.[NUMPEDVEN]
                                   AND i.[STATUS] = 5
                                   AND i.[FLLIBFAT] = 'S'
                                   AND i.[TPPED] IN ('R', 'P')
                                   AND i.[FILORIG] = p.[CODFIL]) AS [ITENS_FATURAVEIS]
                          FROM [MOV_PEDIDO] p WITH (NOLOCK)
                         WHERE p.[TIPOPED] = 0
                           AND p.[NUMPEDVEN] = @NUMPEDVEN
                         ORDER BY p.[DTPEDIDO] DESC";
                    command.Parameters.Add("@NUMPEDVEN", SqlDbType.Decimal).Value = numpedven;

                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        if (!reader.Read())
                        {
                            return new SituacaoPedidoGemco();
                        }

                        return new SituacaoPedidoGemco()
                        {
                            Existe = true,
                            Codfil = Convert.ToInt32(reader["CODFIL"]),
                            Status = reader["STATUS"] == DBNull.Value ? -1 : Convert.ToInt32(reader["STATUS"]),
                            ItensFaturaveis = Convert.ToInt32(reader["ITENS_FATURAVEIS"])
                        };
                    }
                }
            }
        }

        // Registra o aviso no log só na primeira vez em que ele acontece nesta execução do serviço.
        private void AvisarUmaVez(string modulo, long pedidoGemco, string mensagem)
        {
            string chave = modulo + "|" + pedidoGemco.ToString(CultureInfo.InvariantCulture) + "|" + mensagem;

            lock (avisosLock)
            {
                if (!avisosRegistrados.Add(chave))
                {
                    return;
                }
            }

            RegistrarErroConsultaStatus(modulo, pedidoGemco, mensagem);
        }

        private List<PedidoIntegradoMonitoramento> ConsultarPedidosPendentesLiberacaoCaixa()
        {
            List<PedidoIntegradoMonitoramento> pedidos = new List<PedidoIntegradoMonitoramento>();

            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                try
                {

               
                connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;
                        command.CommandText = @"
                        SELECT [id], [pedido_gemco], [pedido_fikon], [STATUS]
                         FROM [dbgemco].[dbo].[FIKON_INTEGRACAO_PEDIDO] WITH (NOLOCK)
                         WHERE ISNULL([STATUS], '') not in ('LIBERADO CXA','FATURADO','FATURADO PARCIAL','FATURADO NO GEMCO','CANCELADO NO GEMCO')
                         AND ISNULL([pedido_fikon], '') <> ''";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {
                            PedidoIntegradoMonitoramento pedido = new PedidoIntegradoMonitoramento()
                            {
                                Id = reader["id"] == DBNull.Value ? 0 : Convert.ToInt32(reader["id"]),
                                PedidoGemco = reader["pedido_gemco"] == DBNull.Value ? 0 : Convert.ToInt64(reader["pedido_gemco"]),
                                PedidoFikon = reader["pedido_fikon"] == DBNull.Value ? string.Empty : reader["pedido_fikon"].ToString(),
                                Status = reader["STATUS"] == DBNull.Value ? string.Empty : reader["STATUS"].ToString()
                            };

                            pedidos.Add(pedido);
                        }

                    }
                }
                catch (Exception ex)
                {
                    // Antes o erro era engolido e a liberação de caixa parava sem aviso.
                    RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", 0, "Erro ao consultar a fila de pedidos para liberação de caixa: " + ex.Message);
                }
            }

            return pedidos;
        }

        private List<PedidoIntegradoMonitoramento> ConsultarPedidosLiberadosCaixaParaFaturamento()
        {
            List<PedidoIntegradoMonitoramento> pedidos = new List<PedidoIntegradoMonitoramento>();

            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                try
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;
                        command.CommandText = @"
                        SELECT [id], [pedido_gemco], [pedido_fikon], [STATUS]
                         FROM [dbgemco].[dbo].[FIKON_INTEGRACAO_PEDIDO] WITH (NOLOCK)
                        WHERE UPPER(LTRIM(RTRIM(ISNULL([STATUS], '')))) IN ('LIBERADO CXA', 'FATURADO PARCIAL')
                          AND ISNULL([pedido_fikon], '') <> ''
                        ORDER BY [pedido_gemco] DESC";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {
                            PedidoIntegradoMonitoramento pedido = new PedidoIntegradoMonitoramento()
                            {
                                Id = reader["id"] == DBNull.Value ? 0 : Convert.ToInt32(reader["id"]),
                                PedidoGemco = reader["pedido_gemco"] == DBNull.Value ? 0 : Convert.ToInt64(reader["pedido_gemco"]),
                                PedidoFikon = reader["pedido_fikon"] == DBNull.Value ? string.Empty : reader["pedido_fikon"].ToString(),
                                Status = reader["STATUS"] == DBNull.Value ? string.Empty : reader["STATUS"].ToString()
                            };

                            pedidos.Add(pedido);
                        }
                    }
                }
                catch (Exception ex)
                {
                    // Antes o erro era engolido e o faturamento parava sem aviso.
                    RegistrarErroConsultaStatus("FATURAMENTO_PEDIDO_FIKON", 0, "Erro ao consultar a fila de pedidos para faturamento: " + ex.Message);
                }
            }

            return pedidos;
        }

        // Notas fiscais ativas da venda na FIKON. Documento ativo sem chave de acesso de 44 dígitos não é
        // NF-e/NFC-e (ex.: o "1567300" de 16/11/2026): fica fora e volta em documentosSemChave para o log.
        private static List<FaturamentoIntegracaoPedido> ExtrairFaturamentosIntegracao(JArray produtos, out List<string> documentosSemChave)
        {
            List<FaturamentoIntegracaoPedido> faturamentos = new List<FaturamentoIntegracaoPedido>();
            documentosSemChave = new List<string>();

            foreach (JToken produto in produtos)
            {
                JArray fats = produto["faturamentos"] as JArray;
                if (fats == null || fats.Count == 0)
                {
                    continue;
                }

                foreach (JToken fat in fats)
                {
                    // Nota cancelada na FIKON nunca vira faturamento no Gemco.
                    if (!NotaEstaAtiva(fat))
                    {
                        continue;
                    }

                    string numero = fat["numero"] == null ? string.Empty : fat["numero"].ToString();
                    string chaveAcesso = fat["chaveAcesso"] == null ? string.Empty : fat["chaveAcesso"].ToString();
                    string dataEmissao = fat["dataEmissao"] == null ? string.Empty : fat["dataEmissao"].ToString();
                    string horaEmissao = fat["horaEmissao"] == null ? string.Empty : fat["horaEmissao"].ToString();
                    string TipoDocumento = fat["tipoDocumento"]?.ToString() ?? string.Empty;

                    long numeroNota;
                    if (!long.TryParse((numero ?? string.Empty).Trim().TrimStart('0'), out numeroNota))
                    {
                        long.TryParse((numero ?? string.Empty).Trim(), out numeroNota);
                    }

                    if (numeroNota <= 0)
                    {
                        continue;
                    }

                    if (!TemChaveAcessoValida(chaveAcesso))
                    {
                        string documento = (numero ?? string.Empty).Trim() + (TipoDocumento.Length > 0 ? " (" + TipoDocumento + ")" : string.Empty);
                        if (!documentosSemChave.Contains(documento))
                        {
                            documentosSemChave.Add(documento);
                        }

                        continue;
                    }

                    DateTime dataHora;
                    if (!DateTime.TryParseExact(
                        (dataEmissao ?? string.Empty).Trim() + " " + (horaEmissao ?? string.Empty).Trim(),
                        "yyyy-MM-dd HH:mm:ss",
                        CultureInfo.InvariantCulture,
                        DateTimeStyles.None,
                        out dataHora))
                    {
                        if (!DateTime.TryParse((dataEmissao ?? string.Empty).Trim(), CultureInfo.InvariantCulture, DateTimeStyles.None, out dataHora))
                        {
                            continue;
                        }
                    }

                    // Série da FIKON: NF-e como veio ("1"); NFC-e no padrão do Gemco ("1" -> "U01").
                    // Sem série no payload, deduz pela chave / tipo do documento.
                    string serie = ObterSerie(fat["serie"]?.ToString(), TipoDocumento, chaveAcesso);

                    faturamentos.Add(new FaturamentoIntegracaoPedido()
                    {
                        NumeroNota = numeroNota,
                        Serie = serie,
                        ChaveAcesso = (chaveAcesso ?? string.Empty).Trim(),
                        DataHoraEmissao = dataHora
                    });
                }
            }

            return faturamentos;
        }

        // Nota ativa = statusNotaCodigo 2 ("Autorizada/Ativa"). Se a FIKON não mandar o código,
        // cai para o nome do status; sem nenhum dos dois, considera ativa (payload antigo).
        private static bool NotaEstaAtiva(JToken fat)
        {
            if (fat == null)
            {
                return false;
            }

            JToken codigo = fat["statusNotaCodigo"];
            if (codigo != null && codigo.Type != JTokenType.Null)
            {
                int valor;
                if (int.TryParse(codigo.ToString(), out valor))
                {
                    return valor == 2;
                }
            }

            string nome = fat["statusNotaNome"]?.ToString() ?? string.Empty;
            if (nome.IndexOf("Cancel", StringComparison.OrdinalIgnoreCase) >= 0
                || nome.IndexOf("Inutiliz", StringComparison.OrdinalIgnoreCase) >= 0
                || nome.IndexOf("Deneg", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return false;
            }

            JToken dataCancelamento = fat["dataCancelamento"];
            return dataCancelamento == null
                || dataCancelamento.Type == JTokenType.Null
                || string.IsNullOrWhiteSpace(dataCancelamento.ToString());
        }

        // Série da nota: a que veio no payload da FIKON (campo "serie"). Sem ela, a série que está
        // na chave de acesso (posições 23-25). Série numérica vai sem zeros à esquerda ("001" -> "1").
        // NFC-e (cupom): grava no padrão do PDV do Gemco, "U" + série com 2 dígitos ("1" -> "U01").
        // As procs do Gemco tratam serie = '1' como NF-e (modelo 55); com "U01" a NFC-e fica modelo 65.
        private static string ObterSerie(string seriePayload, string tipoDocumento, string chaveAcesso)
        {
            string serie = (seriePayload ?? string.Empty).Trim();
            string chave = new string((chaveAcesso ?? string.Empty).Where(char.IsDigit).ToArray());

            if (serie.Length == 0 && chave.Length == 44)
            {
                serie = chave.Substring(22, 3);
            }

            if (serie.Length > 0 && serie.All(char.IsDigit))
            {
                serie = serie.TrimStart('0');
                if (serie.Length == 0)
                {
                    serie = "0";
                }

                return EhNotaConsumidor(tipoDocumento, chave) ? SerieCupomGemco(serie) : serie;
            }

            if (serie.Length > 0 && serie.Length <= 3)
            {
                return serie;
            }

            // Sem série no payload nem na chave: padrão antigo do Gemco.
            string tipo = (tipoDocumento ?? string.Empty).Trim();

            return tipo.IndexOf("Consumidor", StringComparison.OrdinalIgnoreCase) >= 0 ? "U01" : "1";
        }

        // NFC-e: tipo do documento "Nota Fiscal de Consumidor Eletrônica" ou modelo 65 na chave
        // de acesso (posições 21-22).
        private static bool EhNotaConsumidor(string tipoDocumento, string chaveSomenteDigitos)
        {
            if ((tipoDocumento ?? string.Empty).IndexOf("Consumidor", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                return true;
            }

            return chaveSomenteDigitos != null
                && chaveSomenteDigitos.Length == 44
                && chaveSomenteDigitos.Substring(20, 2) == "65";
        }

        // Série do cupom no padrão do Gemco: "U" + série numérica com 2 dígitos ("1" -> "U01",
        // "12" -> "U12"). O campo SERIE tem 3 caracteres: série com 3 dígitos (ex.: "444") não cabe
        // no padrão e é gravada como veio.
        private static string SerieCupomGemco(string serieNumerica)
        {
            return serieNumerica.Length <= 2 ? "U" + serieNumerica.PadLeft(2, '0') : serieNumerica;
        }

        private void ExecutarIntegracaoMovSaida(long numpedven, long numnota, string serie, string chave, DateTime hrhora)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand("[dbo].[SP_FIKON_INTEGRA_MOV_SAIDA]", connection))
                {
                    command.CommandType = CommandType.StoredProcedure;
                    command.Parameters.AddWithValue("@numpedven", numpedven);
                    command.Parameters.AddWithValue("@numnota", numnota);
                    command.Parameters.AddWithValue("@serie", string.IsNullOrWhiteSpace(serie) ? string.Empty : serie.Trim());
                    command.Parameters.AddWithValue("@chave", string.IsNullOrWhiteSpace(chave) ? string.Empty : chave.Trim());
                    command.Parameters.AddWithValue("@hrhora", hrhora);
                    command.ExecuteNonQuery();
                }
            }
        }

        private SituacaoNotaGemco ConsultarNotaNoGemco(long numpedven, long numnota, string serie, string chave)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand())
                {
                    command.Connection = connection;
                    command.CommandText = @"
                        SELECT SUM(CASE WHEN [STATUS] <> 9 THEN 1 ELSE 0 END) AS ATIVAS,
                               COUNT(*) AS TOTAL
                          FROM [MOV_SAIDA]
                         WHERE [NUMPEDVEN] = @NUMPEDVEN
                           AND (   ([NUMNOTA] = @NUMNOTA AND [SERIE] = @SERIE)
                                -- mesma nota gravada antes com outra série (ex.: U01 x 444): reconhece pela chave
                                OR (@CHAVE <> '' AND [CHAVENFE] = @CHAVE))";
                    command.Parameters.Add("@NUMPEDVEN", SqlDbType.Decimal).Value = numpedven;
                    command.Parameters.Add("@NUMNOTA", SqlDbType.Decimal).Value = numnota;
                    command.Parameters.Add("@SERIE", SqlDbType.VarChar, 3).Value = (serie ?? string.Empty).Trim();
                    command.Parameters.Add("@CHAVE", SqlDbType.VarChar, 44).Value = (chave ?? string.Empty).Trim();

                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        if (!reader.Read() || Convert.ToInt32(reader["TOTAL"]) == 0)
                        {
                            return SituacaoNotaGemco.NaoExiste;
                        }

                        return Convert.ToInt32(reader["ATIVAS"]) > 0 ? SituacaoNotaGemco.Ativa : SituacaoNotaGemco.Cancelada;
                    }
                }
            }
        }

        private ConveniadaCash ConsultarConveniadaPorBandeira(string bandeira)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionStringAplicativos))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand())
                {
                    command.Connection = connection;
                    command.CommandText = @"
                        SELECT TOP 1 [CODCON], [TIPO], [BANDEIRA]
                          FROM [dbAplicativos].[dbo].[CASH_CONVENIADAS] WITH (NOLOCK)
                         WHERE UPPER(LTRIM(RTRIM(ISNULL([BANDEIRA], '')))) = UPPER(LTRIM(RTRIM(@BANDEIRA)))
                         ORDER BY CASE WHEN [TIPO] = 'C' THEN 0 ELSE 1 END, [ID]";   // só é chamada para cartão de crédito (ELO/CABAL têm C e D)
                    command.Parameters.AddWithValue("@BANDEIRA", bandeira ?? string.Empty);

                    SqlDataReader reader = command.ExecuteReader();

                    if (reader.Read())
                    {
                        return new ConveniadaCash()
                        {
                            Codcon = reader["CODCON"] == DBNull.Value ? 0 : Convert.ToInt32(reader["CODCON"]),
                            Tipo = reader["TIPO"] == DBNull.Value ? string.Empty : reader["TIPO"].ToString(),
                            Bandeira = reader["BANDEIRA"] == DBNull.Value ? string.Empty : reader["BANDEIRA"].ToString().Trim()
                        };
                    }
                }
            }

            return null;
        }

        private void ExecutarAtualizacaoStatusPedidoGemco(long numpedven, int codfil, string documento, string bandeira, string tipo, string serie = null)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand("[dbo].[SP_FIKON_ATUALIZA_STATUS_PEDIDO]", connection))
                {
                    command.CommandType = CommandType.StoredProcedure;
                    command.Parameters.AddWithValue("@NUMPEDVEN", numpedven);
                    command.Parameters.AddWithValue("@CODFIL", codfil);
                    command.Parameters.AddWithValue("@documento", string.IsNullOrWhiteSpace(documento) ? string.Empty : documento.Trim());
                    command.Parameters.AddWithValue("@bandeira", bandeira ?? string.Empty);
                    command.Parameters.AddWithValue("@tipo", string.IsNullOrWhiteSpace(tipo) ? string.Empty : tipo.Trim());

                    // @serie existe só a partir do script 33; sem série o parâmetro nem é enviado (usa o padrão NULL).
                    if (!string.IsNullOrWhiteSpace(serie))
                    {
                        command.Parameters.AddWithValue("@serie", serie.Trim());
                    }

                    command.ExecuteNonQuery();
                }
            }
        }

        private void AtualizarStatusPedidoIntegrado(int id, string status)
        {
            using (SqlConnection connection = new SqlConnection(this.ConnectionString))
            {
                connection.Open();

                using (SqlCommand command = new SqlCommand())
                {
                    command.Connection = connection;
                    command.CommandText = @"
                        UPDATE [FIKON_INTEGRACAO_PEDIDO]
                           SET [STATUS] = @STATUS
                         WHERE [id] = @ID";
                    command.Parameters.AddWithValue("@STATUS", status ?? string.Empty);
                    command.Parameters.AddWithValue("@ID", id);
                    command.ExecuteNonQuery();
                }
            }
        }

        private static JToken SelecionarFinanceiroParaAtualizacao(JArray financeiros)
        {
            if (financeiros == null || financeiros.Count == 0)
            {
                return null;
            }

            JToken financeiroCartao = financeiros.FirstOrDefault(financeiro =>
                TemValorFinanceiro(financeiro["documentoCartao"])
                || TemValorFinanceiro(financeiro["autorizacaoCartao"])
                || TemValorFinanceiro(financeiro["bandeira"])
                || (financeiro["formaPagamento"] != null
                    && financeiro["formaPagamento"] != null
                    && financeiro["formaPagamento"].ToString().IndexOf("Cart", StringComparison.OrdinalIgnoreCase) >= 0));

            return financeiroCartao ?? financeiros.First;
        }

        private static bool TemValorFinanceiro(JToken token)
        {
            return token != null && !string.IsNullOrWhiteSpace(token.ToString());
        }

        private static string ObterDocumentoFinanceiro(JToken financeiroSelecionado)
        {
            if (financeiroSelecionado == null || financeiroSelecionado["documentoCartao"] == null)
            {
                return string.Empty;
            }

            string documento = financeiroSelecionado["documentoCartao"].ToString();
            return string.IsNullOrWhiteSpace(documento) ? string.Empty : documento.Trim();
        }

        public static string ObterFormaFinanceiro(JArray financeiro)
        {
            if (financeiro == null || !financeiro.Any())
                return string.Empty;

            try
            {
                // Prioriza Cartão de Crédito
                var cartao = financeiro.FirstOrDefault(f =>
                    string.Equals(
                        f["formaPagamento"]?.ToString(),
                        "Cartão de Crédito",
                        StringComparison.OrdinalIgnoreCase));

                if (cartao != null)
                    return cartao["formaPagamento"]?.ToString();

                // Caso não exista cartão, retorna a primeira forma de pagamento
                return financeiro.First()?["formaPagamento"]?.ToString();
            }catch(Exception ex)
            {
                return "";
            }
        }

        private static string ObterBandeiraFinanceiro(JToken financeiroSelecionado)
        {
            if (financeiroSelecionado == null)
            {
                return string.Empty;
            }

            string[] propriedadesDiretas = { "bandeira", "nomeBandeira", "bandeiraCartao", "descricaoBandeira" };

            foreach (string propriedade in propriedadesDiretas)
            {
                if (TemValorFinanceiro(financeiroSelecionado[propriedade]))
                {
                    return financeiroSelecionado[propriedade].ToString().Trim();
                }
            }

            if (financeiroSelecionado["bandeira"] != null)
            {
                try
                {


                    var bandeira = financeiroSelecionado["bandeira"];

                    if (bandeira != null && bandeira.Type != JTokenType.Null)
                    {
                        if (TemValorFinanceiro(bandeira))
                            return bandeira.ToString().Trim();

                        if (TemValorFinanceiro(bandeira))
                            return bandeira["descricao"].ToString().Trim();
                    }

                } catch(Exception ex)
                {

                }
            }

            return string.Empty;
        }

        // Erro inesperado no envio de um cadastro (cliente, produto, fornecedor, preço): rede, timeout,
        // resposta que não é JSON etc. Grava em FIKON_LOG_INTEGRADOR e no log de eventos do Windows.
        // O registro da fila continua 'P' e é reenviado no próximo ciclo.
        private void RegistrarErroEnvio(string modulo, string codigo, Exception ex, string body)
        {
            string mensagem = ("Erro inesperado no envio: " + (ex == null ? string.Empty : ex.GetType().Name + ": " + ex.Message)).Replace("'", "");
            if (mensagem.Length > 4000)
                mensagem = mensagem.Substring(0, 4000);

            try
            {
                executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                     "'" + mensagem + "'," +
                                     "'" + (modulo ?? string.Empty).Replace("'", "") + "'," +
                                     "'" + (codigo ?? string.Empty).Replace("'", "") + "'," +
                                     "getdate()," +
                                     "'" + (body ?? string.Empty).Replace("'", "") + "'" +
                                     ")", ConnectionString);
            }
            catch
            {
            }

            try
            {
                System.Diagnostics.EventLog.WriteEntry("IFikonSource", modulo + " " + codigo + " - " + mensagem, System.Diagnostics.EventLogEntryType.Error);
            }
            catch
            {
            }
        }

        private void RegistrarErroConsultaStatus(string modulo, long pedidoGemco, string erro)
        {
            string mensagem = (erro ?? string.Empty).Replace("'", "");

            try
            {
                executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                     "'" + mensagem + "'," +
                                     "'" + (modulo ?? string.Empty).Replace("'", "") + "'," +
                                     pedidoGemco + "," +
                                     "getdate()," +
                                     "''" +
                                     ")", ConnectionString);
            }
            catch
            {
            }

            try
            {
                System.Diagnostics.EventLog.WriteEntry("IFikonSource", mensagem, System.Diagnostics.EventLogEntryType.Error);
            }
            catch
            {
            }
        }

    }

    class PedidoIntegradoMonitoramento
    {
        public int Id { get; set; }
        public long PedidoGemco { get; set; }
        public string PedidoFikon { get; set; }
        public string Status { get; set; }
    }

    class ConveniadaCash
    {
        public int Codcon { get; set; }
        public string Tipo { get; set; }
        public string Bandeira { get; set; }   // nome como está na CASH_CONVENIADAS (a proc procura por ele)
    }

    class SituacaoPedidoGemco
    {
        public bool Existe { get; set; }
        public int Codfil { get; set; }
        public int Status { get; set; } = -1;
        public int ItensFaturaveis { get; set; }
    }

    enum SituacaoNotaGemco
    {
        NaoExiste,
        Ativa,
        Cancelada
    }

    class FaturamentoIntegracaoPedido
    {
        public long NumeroNota { get; set; }
        public string Serie { get; set; }
        public string ChaveAcesso { get; set; }
        public DateTime DataHoraEmissao { get; set; }
    }
}
