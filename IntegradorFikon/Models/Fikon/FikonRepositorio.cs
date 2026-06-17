using IntegradorFikon.Conexao;
using IntegradorFikon.Models.Produtos;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fikon
{
    class FikonRepositorio : IFikonRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;
        private static string urlBase = new ApiFikon().UrlBase;
        private static string chaveApi = new ApiFikon().ChaveApi;
        private HttpClient client;
        string jcontent = "";


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
                System.Threading.Thread.Sleep(1000);

                jcontent = JsonConvert.SerializeObject(produtos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Post, url);
                HttpResponseMessage response = await client.PostAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() WHERE status='P' and codprod=" + produtos[i].codprod, ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and codprod=" + produtos[i].codprod, ConnectionString);

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
                System.Threading.Thread.Sleep(1000);

                jcontent = JsonConvert.SerializeObject(produtos[i]);

                HttpRequestMessage request = new HttpRequestMessage(HttpMethod.Put, url);
                HttpResponseMessage response = await client.PutAsync(url, new StringContent(jcontent, Encoding.UTF8, "application/json")).ConfigureAwait(false);

                if (response.StatusCode.ToString() == "OK")
                {

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='R', DTINTEGRACAO=getdate() WHERE status='P' and codprod=" + produtos[i].codprod, ConnectionString);


                }
                else
                {

                    string res = await response.Content.ReadAsStringAsync();
                    JObject json = JObject.Parse(res);

                    executaQuery("UPDATE FIKON_CAD_PROD WITH (READCOMMITTED) SET STATUS='E', DTINTEGRACAO=getdate() WHERE status='P' and codprod=" + produtos[i].codprod, ConnectionString);

                    executaQuery("INSERT INTO FIKON_LOG_INTEGRADOR(ERRO,MODULO,CODPROD,DTERRO,BODY) VALUES(" +
                                               "'" + json.GetValue("message").ToString().Replace("'", "") + "'," +
                                               "'PRODUTO UPDATE' ," +
                                               produtos[i].codprod + "," +
                                               "getdate() ," +
                                               "'" + jcontent.ToString() + "'" +
                                               ")", ConnectionString);
                }




            }
        }

    }
}
