using IntegradorFikon.Conexao;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Produtos
{
    class ProdutoRepositorio : IProdutoRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;


        public IEnumerable<Produto> GetItens()
        {

            List<Produto> ListProdutos = new List<Produto>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_INSERT_PRODUTOS] ";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {
                    
                            Produto produto = new Produto()
                            {
                                codigo = reader["Codigo"] == DBNull.Value ? string.Empty : reader["Codigo"].ToString(),
                                nome = reader["Nome"] == DBNull.Value ? string.Empty : reader["Nome"].ToString(),
                                classe = reader["Classe"] == DBNull.Value ? string.Empty : reader["Classe"].ToString(),
                                clfiscal = reader["ClFiscal"] == DBNull.Value ? string.Empty : reader["ClFiscal"].ToString(),
                                unidmedida = reader["UnidMedida"] == DBNull.Value ? string.Empty : reader["UnidMedida"].ToString(),
                                procedenci = reader["Procedencia"] == DBNull.Value ? string.Empty : reader["Procedencia"].ToString(),
                                fabricante = reader["Fabricante"] == DBNull.Value ? string.Empty : reader["Fabricante"].ToString(),
                                referenciaFabrica = reader["RefFabrica"] == DBNull.Value ? string.Empty : reader["RefFabrica"].ToString(),
                                marca = reader["Marca"] == DBNull.Value ? string.Empty : reader["Marca"].ToString(),
                                modelo = reader["Modelo"] == DBNull.Value ? string.Empty : reader["Modelo"].ToString(),
                                cor = reader["Cor"] == DBNull.Value ? string.Empty : reader["Cor"].ToString(),
                                tamanho = reader["Tamanho"] == DBNull.Value ? string.Empty : reader["Tamanho"].ToString(),
                                //qdeporvol = reader["QdePorvol"] == DBNull.Value ? string.Empty : reader["QdePorvol"].ToString(),
                                //qdeporvolcompra = reader["QdePorvolCompra"] == DBNull.Value ? string.Empty : reader["QdePorvolCompra"].ToString(),
                                //foradeLinha = reader["ForaDeLinha"] == DBNull.Value ? string.Empty : reader["ForaDeLinha"].ToString(),
                                //foradelinhainfo = reader["ForaDeLinha"] == DBNull.Value ? string.Empty : reader["ForaDeLinha"].ToString(),
                                //inativo = reader["Inativo"] == DBNull.Value ? string.Empty : reader["Inativo"].ToString(),
                                //inativador = reader["Inativador"] == DBNull.Value ? string.Empty : reader["Inativador"].ToString(),
                                //material = reader["Material"] == DBNull.Value ? string.Empty : reader["Material"].ToString(),
                                referenciaPrincipal = reader["RefPrincipal"] == DBNull.Value ? string.Empty : reader["RefPrincipal"].ToString(),
                                codprod = reader["codprod"] == DBNull.Value ? string.Empty : reader["codprod"].ToString(),
                                descricaogenerica = reader["DescricaoGenerica"] == DBNull.Value ? string.Empty : reader["DescricaoGenerica"].ToString(),
                                //Cest = reader["Cest"] == DBNull.Value ? string.Empty : reader["Cest"].ToString(),

                            };

                            produto.codigos = GetCodigos(produto.codigo);
                            produto.fornecedores = GetFornecedores(produto.codigo);

                            ListProdutos.Add(produto);
                        }


                    }


                    connection.Close();

                }


                return ListProdutos;
            }

            catch (Exception ex)

            {
                return null;
            }
        }


        public IEnumerable<Produto> GetItensUpdate()
        {

            List<Produto> ListProdutos = new List<Produto>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_ALTER_PRODUTOS] ";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Produto produto = new Produto()
                            {
                                codigo = reader["Codigo"] == DBNull.Value ? string.Empty : reader["Codigo"].ToString(),
                                nome = reader["Nome"] == DBNull.Value ? string.Empty : reader["Nome"].ToString(),
                                classe = reader["Classe"] == DBNull.Value ? string.Empty : reader["Classe"].ToString(),
                                clfiscal = reader["ClFiscal"] == DBNull.Value ? string.Empty : reader["ClFiscal"].ToString(),
                                unidmedida = reader["UnidMedida"] == DBNull.Value ? string.Empty : reader["UnidMedida"].ToString(),
                                procedenci = reader["Procedencia"] == DBNull.Value ? string.Empty : reader["Procedencia"].ToString(),
                                fabricante = reader["Fabricante"] == DBNull.Value ? string.Empty : reader["Fabricante"].ToString(),
                                referenciaFabrica = reader["RefFabrica"] == DBNull.Value ? string.Empty : reader["RefFabrica"].ToString(),
                                marca = reader["Marca"] == DBNull.Value ? string.Empty : reader["Marca"].ToString(),
                                modelo = reader["Modelo"] == DBNull.Value ? string.Empty : reader["Modelo"].ToString(),
                                cor = reader["Cor"] == DBNull.Value ? string.Empty : reader["Cor"].ToString(),
                                tamanho = reader["Tamanho"] == DBNull.Value ? string.Empty : reader["Tamanho"].ToString(),
                                //qdeporvol = reader["QdePorvol"] == DBNull.Value ? string.Empty : reader["QdePorvol"].ToString(),
                                //qdeporvolcompra = reader["QdePorvolCompra"] == DBNull.Value ? string.Empty : reader["QdePorvolCompra"].ToString(),
                                //foradeLinha = reader["ForaDeLinha"] == DBNull.Value ? string.Empty : reader["ForaDeLinha"].ToString(),
                                //foradelinhainfo = reader["ForaDeLinha"] == DBNull.Value ? string.Empty : reader["ForaDeLinha"].ToString(),
                                //inativo = reader["Inativo"] == DBNull.Value ? string.Empty : reader["Inativo"].ToString(),
                                //inativador = reader["Inativador"] == DBNull.Value ? string.Empty : reader["Inativador"].ToString(),
                                //material = reader["Material"] == DBNull.Value ? string.Empty : reader["Material"].ToString(),
                                referenciaPrincipal = reader["RefPrincipal"] == DBNull.Value ? string.Empty : reader["RefPrincipal"].ToString(),
                                codprod = reader["codprod"] == DBNull.Value ? string.Empty : reader["codprod"].ToString(),
                                descricaogenerica = reader["DescricaoGenerica"] == DBNull.Value ? string.Empty : reader["DescricaoGenerica"].ToString(),
                                //Cest = reader["Cest"] == DBNull.Value ? string.Empty : reader["Cest"].ToString(),

                            };

                            produto.codigos = GetCodigos(produto.codigo);
                            produto.fornecedores = GetFornecedores(produto.codigo);

                            ListProdutos.Add(produto);
                        }


                    }


                    connection.Close();

                }


                return ListProdutos;
            }

            catch (Exception ex)

            {
                return null;
            }
        }



        public List<Codigo> GetCodigos(string recurso)
        {

            List<Codigo> ListCodigo = new List<Codigo>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_CONSULTA_CODIGOS] "+recurso ;

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Codigo codigo = new Codigo()
                            {
                                codigo = reader["codigo"] == DBNull.Value ? string.Empty : reader["codigo"].ToString(),
                                tipo = reader["Classificacao"] == DBNull.Value ? string.Empty : reader["Classificacao"].ToString(),
                                

                            };

                            ListCodigo.Add(codigo);
                        }


                    }


                    connection.Close();

                }


                return ListCodigo;
            }

            catch (Exception ex)

            {
                return null;
            }
        }



        public List<Fornecedor> GetFornecedores(string recurso)
        {

            List<Fornecedor> ListFornecedores = new List<Fornecedor>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_CONSULTA_FORNECEDORES]  "+ recurso;

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Fornecedor fornecedor = new Fornecedor()
                            {
                                fornecedor = reader["fornecedor"] == DBNull.Value ? string.Empty : reader["fornecedor"].ToString(),
                                principal = reader["principal"] == DBNull.Value ? string.Empty : reader["principal"].ToString(),
                                entrega = reader["entrega"] == DBNull.Value ? string.Empty : reader["entrega"].ToString(),
                                logistica = reader["logistica"] == DBNull.Value ? string.Empty : reader["logistica"].ToString(),
                                mincompra = reader["mincompra"] == DBNull.Value ? string.Empty : reader["mincompra"].ToString(),
                                economico = reader["economico"] == DBNull.Value ? string.Empty : reader["economico"].ToString(),
                                qtdevolcompra = reader["qtdevolcompra"] == DBNull.Value ? string.Empty : reader["qtdevolcompra"].ToString(),
                                
                     

                            };

                            ListFornecedores.Add(fornecedor);
                        }


                    }


                    connection.Close();

                }


                return ListFornecedores;
            }

            catch (Exception ex)

            {
                return null;
            }
        }


    }
}
