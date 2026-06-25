using IntegradorFikon.Conexao;
using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Preco
{
    class PrecoRepositorio: IPrecoRepositorio
    {
        private string ConnectionString = new ConGemco().ConString;

        public IEnumerable<Preco> GetPrecosUpdate()
        {

            List<Preco> ListPrecos = new List<Preco>();

            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    using (SqlCommand command = new SqlCommand())
                    {
                        command.Connection = connection;

                        command.CommandText = "exec [SP_FIKON_ATUALIZA_PRECO] ";

                        SqlDataReader reader = command.ExecuteReader();

                        while (reader.Read())
                        {

                            Preco preco = new Preco()
                            {
                                recursoChave = reader["recurso"] == DBNull.Value ? string.Empty : reader["recurso"].ToString(),
                                estabelecimento = "123",
                                novoPreco = reader["preco"] == DBNull.Value ? 0 : Convert.ToDouble(reader["preco"]),
                                

                            };



                            ListPrecos.Add(preco);
                        }


                    }


                    connection.Close();

                }


                return ListPrecos;
            }

            catch (Exception ex)

            {
                return null;
            }
        }

    }
}
