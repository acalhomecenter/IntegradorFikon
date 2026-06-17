using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Data.SqlClient;
using System.Drawing;
using System.Linq;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace IntegradorFikonForm
{
    public partial class Form1 : Form
    {
        //private string ConnectionString = "Data Source=sqlcs;User Id=app;Password=sqlbolim;Initial Catalog=dbAplicativos";
        private string ConnectionString;

        public Form1()
        {
            InitializeComponent();
            //Reiniciar("new IntegradorService()");
        }

        private void button1_Click(object sender, EventArgs e)
        {
             ConnectionString = "Data Source=" + rtServidor.Text.ToString() + ";User Id=" + rtUsuario.Text.ToString() + ";Password=" + txtsenha.Text.ToString() + ";Initial Catalog=" + rtCatalogo.Text.ToString() + "";
            try
            {
                using (SqlConnection connection = new SqlConnection(this.ConnectionString))
                {
                    connection.Open();

                    MessageBox.Show("Conexão feita", "Teste de conexão", MessageBoxButtons.OK,MessageBoxIcon.Information, MessageBoxDefaultButton.Button1);
                }

                 
            }
            catch (Exception ex)
            {
                MessageBox.Show(ex.Message, "Teste de conexão", MessageBoxButtons.OK, MessageBoxIcon.Error, MessageBoxDefaultButton.Button1);
                //throw ex;
            }


        }

        //public void Reiniciar(string nome)
        //{
        //    ServiceController serviço = new ServiceController();
        //    serviço.ServiceName = nome;

        //    if (serviço.Status == ServiceControllerStatus.Running)
        //    {
        //        serviço.Stop();
        //        serviço.WaitForStatus(ServiceControllerStatus.Stopped);
        //    }

        //    serviço.Start();

        //    serviço.Dispose();
        //}


    }
}
