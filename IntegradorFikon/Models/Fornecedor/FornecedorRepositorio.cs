using IntegradorFikon.Conexao;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fornecedor
{
    class FornecedorRepositorio : IFornecedorRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;


        public IEnumerable<Fornecedor> GetFornecedores()
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

                        command.CommandText = "exec [SP_FIKON_INSERE_FORNECEDOR] ";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Fornecedor fornecedor = new Fornecedor()
                            {
                                codigo = reader["Codigo"] == DBNull.Value ? string.Empty : reader["Codigo"].ToString(),
                                nome= reader["Nome"] == DBNull.Value ? string.Empty : reader["Nome"].ToString(),
                                razaoSocial = reader["apelido"] == DBNull.Value ? string.Empty : reader["apelido"].ToString(),
                                classe = reader["Classe"] == DBNull.Value ? string.Empty : reader["Classe"].ToString(),
                                inscMunic = reader["inscmunic"] == DBNull.Value ? string.Empty : reader["inscmunic"].ToString(),
                                inscEstad = reader["inscestad"] == DBNull.Value ? string.Empty : reader["inscestad"].ToString(),
                                email = reader["e-mail"] == DBNull.Value ? string.Empty : reader["e-mail"].ToString(),
                                fone = reader["fone"] == DBNull.Value ? string.Empty : reader["fone"].ToString(),
                                compFiscal = reader["compfiscal"] == DBNull.Value ? string.Empty : reader["compfiscal"].ToString(),
                                cpfcnpj = reader["cgccpf"] == DBNull.Value ? string.Empty : reader["cgccpf"].ToString(),
                                
                              

                            };

                            Enderecoprincipal endereco = new Enderecoprincipal()
                            {
                                
                                numero = reader["numero"] == DBNull.Value ? string.Empty : reader["numero"].ToString(),
                                bairro = reader["bairro"] == DBNull.Value ? string.Empty : reader["bairro"].ToString(),
                                uf = reader["uf"] == DBNull.Value ? string.Empty : reader["uf"].ToString(),
                                logradouro = reader["logradouro"] == DBNull.Value ? string.Empty : reader["logradouro"].ToString(),
                                complemento = reader["complemento"] == DBNull.Value ? string.Empty : reader["complemento"].ToString(),
                                cidade = reader["cidade"] == DBNull.Value ? string.Empty : reader["cidade"].ToString(),
                                tipoLogradouro = reader["tipologradouro"] == DBNull.Value ? string.Empty : reader["tipologradouro"].ToString(),
                                cep = reader["cep"] == DBNull.Value ? string.Empty : reader["cep"].ToString(),

                            };

                            fornecedor.enderecoPrincipal = endereco;
                           
                           

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
