using IntegradorFikon.Conexao;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Cliente
{
    class ClienteRepositorio:IClienteRepositorio
    {

        private string ConnectionString = new ConGemco().ConString;


        public List<Cliente> GetClientes()
        {

            List<Cliente> ListClientes = new List<Cliente>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_INSERT_CLIENTE] ";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Cliente cliente = new Cliente()
                            {
                                codigo = reader["Codigo"] == DBNull.Value ? string.Empty : reader["Codigo"].ToString(),
                                nome = reader["Nome"] == DBNull.Value ? string.Empty : reader["Nome"].ToString(),
                                razaoSocial = reader["apelido"] == DBNull.Value ? string.Empty : reader["apelido"].ToString(),
                                classe = reader["Classe"] == DBNull.Value ? string.Empty : reader["Classe"].ToString(),
                                inscEstadual = reader["InscEstad"] == DBNull.Value ? string.Empty : reader["InscEstad"].ToString(),
                                inscMunicipal = reader["InscMunic"] == DBNull.Value ? string.Empty : reader["InscMunic"].ToString(),
                                email = reader["email"] == DBNull.Value ? string.Empty : reader["email"].ToString(),
                                fone = reader["fone"] == DBNull.Value ? string.Empty : reader["fone"].ToString(),
                                celular = reader["celular"] == DBNull.Value ? string.Empty : reader["celular"].ToString(),
                                compFiscal = reader["compfiscal"] == DBNull.Value ? string.Empty : reader["compfiscal"].ToString(),
                                cpfcnpj = reader["cgccpf"] == DBNull.Value ? string.Empty : reader["cgccpf"].ToString(),
                                obsGerais = reader["obsgerais"] == DBNull.Value ? string.Empty : reader["obsgerais"].ToString(),



                            };

                            Enderecoprincipal endereco = new Enderecoprincipal()
                            {

                                numero = reader["numero"] == DBNull.Value ? string.Empty : reader["numero"].ToString(),
                                bairro = reader["bairro"] == DBNull.Value ? string.Empty : reader["bairro"].ToString(),
                                uf = reader["uf"] == DBNull.Value ? string.Empty : reader["uf"].ToString(),
                                logradouro = reader["logradouro"] == DBNull.Value ? string.Empty : reader["logradouro"].ToString(),
                                complemento = reader["complemento"] == DBNull.Value ? string.Empty : reader["complemento"].ToString(),
                                cidade = reader["cidade"] == DBNull.Value ? string.Empty : reader["cidade"].ToString(),
                                tipoLogradouro = reader["tplogradouro"] == DBNull.Value ? string.Empty : reader["tplogradouro"].ToString(),
                                cep = reader["cep"] == DBNull.Value ? string.Empty : reader["cep"].ToString(),

                            };

                            cliente.enderecoPrincipal = endereco;

                            cliente.enderecosAdicionais = GetEnderecos(cliente.codigo);



                            ListClientes.Add(cliente);
                        }


                    }


                    connection.Close();

                }


                return ListClientes;
            }

            catch (Exception ex)

            {
                return null;
            }
        }


        public List<Enderecosadicionais> GetEnderecos(string codigo)
        {

            List<Enderecosadicionais> ListEnderecos = new List<Enderecosadicionais>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_CONSULTA_ENDERECO] '" + codigo+"'" ;

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {


                            Enderecosadicionais endereco = new Enderecosadicionais()
                            {

                                numero = reader["numero"] == DBNull.Value ? string.Empty : reader["numero"].ToString(),
                                bairro = reader["bairro"] == DBNull.Value ? string.Empty : reader["bairro"].ToString(),
                                uf = reader["uf"] == DBNull.Value ? string.Empty : reader["uf"].ToString(),
                                logradouro = reader["logradouro"] == DBNull.Value ? string.Empty : reader["logradouro"].ToString(),
                                complemento = reader["complemento"] == DBNull.Value ? string.Empty : reader["complemento"].ToString(),
                                cidade = reader["cidade"] == DBNull.Value ? string.Empty : reader["cidade"].ToString(),
                                tipoLogradouro = reader["tplogradouro"] == DBNull.Value ? string.Empty : reader["tplogradouro"].ToString(),
                                cep = reader["cep"] == DBNull.Value ? string.Empty : reader["cep"].ToString(),
                                entrega = true,

                            };


                            ListEnderecos.Add(endereco);

                        }
                    }


                    connection.Close();

                }


                return ListEnderecos;
            }

            catch (Exception ex)

            {
                return null;
            }

        }

  
    }
}
