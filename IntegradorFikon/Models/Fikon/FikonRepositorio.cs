﻿﻿﻿using IntegradorFikon.Conexao;
using IntegradorFikon.Models.Produtos;
using IntegradorFikon.Models.Fornecedor;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Data;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Data.SqlClient;

namespace IntegradorFikon.Models.Fikon
{
    class FikonRepositorio : IFikonRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;
        private string ConnectionStringAplicativos = "Data Source=sqlcs;User Id=app;Password=sqlbolim;Initial Catalog=dbAplicativos";
        private static string urlBase = new ApiFikon().UrlBase;
        private static string chaveApi = new ApiFikon().ChaveApi;
        private HttpClient client;
        string jcontent = "";
        string jcontentAtualiza = "";
        string jcontentPreco = "";
        string jcontentForne = "";



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
            client = new HttpClient();

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
            client = new HttpClient();

            string url = urlBase + "/api-acal/api/v1/cliente";

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

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'CLIENTE_TODOS' ," +
                                               clientes[i].codigo + "," +
                                               "getdate() ," +
                                               "'" + jcontent.ToString() + "'" +
                                               ")", ConnectionString);
                }




            }
        }




        public async void insereProdutoFikon(IEnumerable<Produto> prods)
        {
            client = new HttpClient();

            string url = urlBase + "/api-acal/api/v1/recurso/cadastrar";

            var produtos = prods.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < produtos.Count(); i++)
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




                }
        }


        public async void atualizaProdutoFikon(IEnumerable<Produto> prods)
        {
            client = new HttpClient();

            string url = urlBase + "/api-acal/api/v1/recurso/editar";

            var produtos = prods.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < produtos.Count(); i++)
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




            }
        }


        public async void insereFornecedorFikon(IEnumerable<IntegradorFikon.Models.Fornecedor.Fornecedor> forne)
        {
            client = new HttpClient();

            string url = urlBase + "/api-acal/api/v1/fornecedor";

            var fornecedores = forne.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < fornecedores.Count(); i++)
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




            }
        }

        public async void inserePrecoFikon(IEnumerable<IntegradorFikon.Models.Preco.Preco> preco)
        {
            client = new HttpClient();

            string url = urlBase + "/api-acal/api/v1/preco/cadastrar";

            var precos = preco.ToArray();

            if (!client.DefaultRequestHeaders.Contains("Authorization"))
            {
                client.DefaultRequestHeaders.Add("Authorization", chaveApi);
            }

            for (int i = 0; i < precos.Count(); i++)
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

        private async Task ProcessarConsultaStatusPedidoAsync(HttpClient statusClient, PedidoIntegradoMonitoramento pedido)
        {
            string url = urlBase + "/api-acal/api/v1/pedidos/pesquisarVenda?idPedido=" + Uri.EscapeDataString(pedido.PedidoFikon);
            HttpResponseMessage response = await statusClient.GetAsync(url).ConfigureAwait(false);
            string body = await response.Content.ReadAsStringAsync().ConfigureAwait(false);

            if (!response.IsSuccessStatusCode)
            {
                RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Consulta do pedido FIKON retornou status " + (int)response.StatusCode + ". Body: " + body);
                return;
            }

            JObject json = JObject.Parse(body);
            string statusComercial = (json.SelectToken("dadosVenda.linhaDoTempo.statusComercial") ?? json.SelectToken("linhaDoTempo.statusComercial")) == null
                ? string.Empty
                : (json.SelectToken("dadosVenda.linhaDoTempo.statusComercial") ?? json.SelectToken("linhaDoTempo.statusComercial")).ToString();

            if (!string.Equals(statusComercial, "Passado no Caixa / Aprovado", StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            JArray financeiros = json.SelectToken("dadosVenda.financeiro") as JArray;
            JToken financeiroSelecionado = SelecionarFinanceiroParaAtualizacao(financeiros);

            if (financeiroSelecionado == null)
            {
                RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Pedido FIKON " + pedido.PedidoFikon + " aprovado no caixa, mas sem financeiro retornado.");
                return;
            }

            string documento = ObterDocumentoFinanceiro(financeiroSelecionado);
            string bandeira = ObterBandeiraFinanceiro(financeiroSelecionado);

            if (string.IsNullOrWhiteSpace(bandeira))
            {
                RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Pedido FIKON " + pedido.PedidoFikon + " aprovado no caixa, mas sem bandeira no retorno da FIKON.");
                return;
            }

            ConveniadaCash conveniada = ConsultarConveniadaPorBandeira(bandeira);

            if (conveniada == null)
            {
                RegistrarErroConsultaStatus("STATUS_PEDIDO_FIKON", pedido.PedidoGemco, "Bandeira '" + bandeira + "' não encontrada em CASH_CONVENIADAS para o pedido FIKON " + pedido.PedidoFikon + ".");
                return;
            }

            ExecutarAtualizacaoStatusPedidoGemco(pedido.PedidoGemco, 502, documento, conveniada.Codcon, conveniada.Tipo);
            AtualizarStatusPedidoIntegrado(pedido.Id, "LIBERADO CXA");
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
                         WHERE ISNULL([STATUS], '') not in ('LIBERADO CXA','FATURADO','FATURADO PARCIAL')
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

                }
            }

            return pedidos;
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
                        SELECT TOP 1 [CODCON], [TIPO]
                          FROM [dbAplicativos].[dbo].[CASH_CONVENIADAS] WITH (NOLOCK)
                         WHERE UPPER(LTRIM(RTRIM(ISNULL([BANDEIRA], '')))) = UPPER(LTRIM(RTRIM(@BANDEIRA)))";
                    command.Parameters.AddWithValue("@BANDEIRA", bandeira ?? string.Empty);

                    SqlDataReader reader = command.ExecuteReader();

                    if (reader.Read())
                    {
                        return new ConveniadaCash()
                        {
                            Codcon = reader["CODCON"] == DBNull.Value ? 0 : Convert.ToInt32(reader["CODCON"]),
                            Tipo = reader["TIPO"] == DBNull.Value ? string.Empty : reader["TIPO"].ToString()
                        };
                    }
                }
            }

            return null;
        }

        private void ExecutarAtualizacaoStatusPedidoGemco(long numpedven, int codfil, string documento, int bandeira, string tipo)
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
                    command.Parameters.AddWithValue("@bandeira", bandeira);
                    command.Parameters.AddWithValue("@tipo", string.IsNullOrWhiteSpace(tipo) ? string.Empty : tipo.Trim());
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
                    && financeiro["formaPagamento"]["nome"] != null
                    && financeiro["formaPagamento"]["nome"].ToString().IndexOf("Cart", StringComparison.OrdinalIgnoreCase) >= 0));

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
                if (TemValorFinanceiro(financeiroSelecionado["bandeira"]["nome"]))
                {
                    return financeiroSelecionado["bandeira"]["nome"].ToString().Trim();
                }

                if (TemValorFinanceiro(financeiroSelecionado["bandeira"]["descricao"]))
                {
                    return financeiroSelecionado["bandeira"]["descricao"].ToString().Trim();
                }
            }

            return string.Empty;
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
    }
}
