﻿﻿﻿﻿using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.Linq;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using IntegradorFikon.Models.Produtos;
using IntegradorFikon.Models.Fikon;
using IntegradorFikon.Models.Fornecedor;
using IntegradorFikon.Models.Preco;
using IntegradorFikon.Models.Cliente;

namespace IntegradorFikon
{
    public partial class IntegradorService : ServiceBase
    {
       //private EventLog eventLog1;
        private int eventId = 1;
        private System.Timers.Timer timerStatusPedidos;
        private System.Timers.Timer timerFaturamentoPedidos;
        private bool executandoConsultaStatusPedidos = false;
        private bool executandoConsultaFaturamentoPedidos = false;
        static readonly IProdutoRepositorio repositorio = new ProdutoRepositorio();
        static readonly IClienteRepositorio repositorioCliente = new ClienteRepositorio();
        static readonly IFornecedorRepositorio repositorioFornecedor = new FornecedorRepositorio();
        static readonly IPrecoRepositorio repositorioPreco = new PrecoRepositorio();
        static readonly IFikonRepositorio repositorioFikon = new FikonRepositorio();



        public enum ServiceState
        {
            SERVICE_STOPPED = 0x00000001,
            SERVICE_START_PENDING = 0x00000002,
            SERVICE_STOP_PENDING = 0x00000003,
            SERVICE_RUNNING = 0x00000004,
            SERVICE_CONTINUE_PENDING = 0x00000005,
            SERVICE_PAUSE_PENDING = 0x00000006,
            SERVICE_PAUSED = 0x00000007,
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct ServiceStatus
        {
            public int dwServiceType;
            public ServiceState dwCurrentState;
            public int dwControlsAccepted;
            public int dwWin32ExitCode;
            public int dwServiceSpecificExitCode;
            public int dwCheckPoint;
            public int dwWaitHint;
        };

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool SetServiceStatus(System.IntPtr handle, ref ServiceStatus serviceStatus);

        public IntegradorService()
        {
            InitializeComponent();

            eventLog1 = new System.Diagnostics.EventLog();
            if (!EventLog.SourceExists("IFikonSource"))
            {
                System.Diagnostics.EventLog.CreateEventSource(
                    "IFikonSource", "IFikonLog");
            }
            eventLog1.Source = "IFikonSource";
            eventLog1.Log = "IFikonLog";

        }

        protected override void OnStart(string[] args)
        {
            eventLog1.WriteEntry("Serviço Iniciando");

            // Set up a timer that triggers every minute.
            System.Timers.Timer timer = new System.Timers.Timer();
            timer.Interval = 60000; // 1 minutos
            //timer.Interval = 120000; // 2 minutos
            //timer.Interval = 300000; // 5 minutos
            timer.Elapsed += new System.Timers.ElapsedEventHandler(this.OnTimer);
            timer.Start();

            System.Timers.Timer timerPreco = new System.Timers.Timer(300000); // 5 minutos em milissegundos
            timerPreco.Elapsed += OnTimerPreco;
            timerPreco.Start();

            timerStatusPedidos = new System.Timers.Timer(30000);
            timerStatusPedidos.Elapsed += OnTimerStatusPedidos;
            timerStatusPedidos.Start();

            timerFaturamentoPedidos = new System.Timers.Timer(30000);
            timerFaturamentoPedidos.Elapsed += OnTimerFaturamentoPedidos;
            timerFaturamentoPedidos.Start();

            // Update the service state to Start Pending.
            ServiceStatus serviceStatus = new ServiceStatus();
            serviceStatus.dwCurrentState = ServiceState.SERVICE_START_PENDING;
            serviceStatus.dwWaitHint = 100000;
            SetServiceStatus(this.ServiceHandle, ref serviceStatus);

            // Update the service state to Running.
            serviceStatus.dwCurrentState = ServiceState.SERVICE_RUNNING;
            SetServiceStatus(this.ServiceHandle, ref serviceStatus);

            eventLog1.WriteEntry("Serviço Iniciado");


            //repositorioFikon.insereClientesFikonTodos(repositorioCliente.GetClientes());

            //repositorioFikon.insereProdutoFikonTodos(repositorio.GetItensTodos());


        }

        protected override void OnPause()
        {
            eventLog1.WriteEntry("Serviço Pausado");
        }

        protected override void OnContinue()
        {
            eventLog1.WriteEntry("Serviço Continuado");
        }

        protected override void OnStop()
        {
            // Update the service state to Running.
            ServiceStatus serviceStatus = new ServiceStatus();
            serviceStatus.dwCurrentState = ServiceState.SERVICE_STOPPED;
            serviceStatus.dwWaitHint = 100000;
            SetServiceStatus(this.ServiceHandle, ref serviceStatus);

            eventLog1.WriteEntry("Serviço Parado");
        }

        protected override void OnShutdown()
        {
            eventLog1.WriteEntry("Serviço Desligado");
        }

        public void OnTimer(object sender, System.Timers.ElapsedEventArgs args)
        {
            // TODO: Insert monitoring activities here.
            //eventLog1.WriteEntry("Monitorando Integrador Moskit", EventLogEntryType.Information, eventId++);
            eventLog1.WriteEntry("Monitorando Integrador Fikon", EventLogEntryType.Information);
            //eventLog1.WriteEntry("Controlando o event id: " + eventId.ToString(), EventLogEntryType.Information, eventId++);
            //eventLog1.WriteEntry("Orcamento: " +  repositorio.GetDadosOrcamento().ToString(), EventLogEntryType.Information, eventId++);



          


            //repositorioFikon.insereFornecedorFikon(repositorioFornecedor.GetFornecedores());



            //repositorioFikon.insereProdutoFikon(repositorio.GetItens());




        }


        public void OnTimerPreco(object sender, System.Timers.ElapsedEventArgs args)
        {
            // TODO: Insert monitoring activities here.
            //eventLog1.WriteEntry("Monitorando Integrador Moskit", EventLogEntryType.Information, eventId++);
            eventLog1.WriteEntry("Monitorando Integrador Fikon", EventLogEntryType.Information);
            //eventLog1.WriteEntry("Controlando o event id: " + eventId.ToString(), EventLogEntryType.Information, eventId++);
            //eventLog1.WriteEntry("Orcamento: " +  repositorio.GetDadosOrcamento().ToString(), EventLogEntryType.Information, eventId++);





            //repositorioFikon.inserePrecoFikon(repositorioPreco.GetPrecosUpdate());


            //repositorioFikon.atualizaProdutoFikon(repositorio.GetItensUpdate());



        }

        public void OnTimerStatusPedidos(object sender, System.Timers.ElapsedEventArgs args)
        {
            if (executandoConsultaStatusPedidos)
            {
                return;
            }
           
            try
            {
                executandoConsultaStatusPedidos = true;
                repositorioFikon.consultarStatusPedidosFikon().GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                eventLog1.WriteEntry("Erro ao consultar status de pedidos integrados na FIKON: " + ex.Message, EventLogEntryType.Error);
            }
            finally
            {
                executandoConsultaStatusPedidos = false;
            }
        }

        public void OnTimerFaturamentoPedidos(object sender, System.Timers.ElapsedEventArgs args)
        {
            if (executandoConsultaFaturamentoPedidos)
            {
                return;
            }

            try
            {
                executandoConsultaFaturamentoPedidos = true;
                repositorioFikon.consultarFaturamentoPedidosFikon().GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                eventLog1.WriteEntry("Erro ao consultar faturamento de pedidos integrados na FIKON: " + ex.Message, EventLogEntryType.Error);
            }
            finally
            {
                executandoConsultaFaturamentoPedidos = false;
            }
        }



        private void eventLog1_EntryWritten(object sender, EntryWrittenEventArgs e)
        {

        }


      
    }
}
