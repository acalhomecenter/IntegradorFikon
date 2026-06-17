using System;
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

namespace IntegradorFikon
{
    public partial class IntegradorService : ServiceBase
    {
       //private EventLog eventLog1;
        private int eventId = 1;
        static readonly IProdutoRepositorio repositorio = new ProdutoRepositorio();
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

            // Update the service state to Start Pending.
            ServiceStatus serviceStatus = new ServiceStatus();
            serviceStatus.dwCurrentState = ServiceState.SERVICE_START_PENDING;
            serviceStatus.dwWaitHint = 100000;
            SetServiceStatus(this.ServiceHandle, ref serviceStatus);

            // Update the service state to Running.
            serviceStatus.dwCurrentState = ServiceState.SERVICE_RUNNING;
            SetServiceStatus(this.ServiceHandle, ref serviceStatus);

            eventLog1.WriteEntry("Serviço Iniciado");

            
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



           repositorioFikon.insereProdutoFikon(repositorio.GetItens());


        
            repositorioFikon.atualizaProdutoFikon(repositorio.GetItensUpdate());


        }

        private void eventLog1_EntryWritten(object sender, EntryWrittenEventArgs e)
        {

        }


      
    }
}
