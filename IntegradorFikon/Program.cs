using System;
using System.Collections.Generic;
using System.Configuration.Install;
using System.Linq;
using System.Reflection;
using System.ServiceProcess;
using System.Text;
using System.Threading.Tasks;


namespace IntegradorFikon
{
    static class Program
    {
        /// <summary>
        /// Ponto de entrada principal para o aplicativo.
        /// </summary>
        static void Main()
        {
            ServiceBase[] ServicesToRun;
            ServicesToRun = new ServiceBase[]
            {
                new IntegradorService()
            };
            ServiceBase.Run(ServicesToRun);
        }


        //static void Main(string[] args)
        //{
        //    if (Environment.UserInteractive)
        //    {
        //        string parameter = string.Concat(args);
        //        switch (parameter)
        //        {
        //            case "--install":
        //                ManagedInstallerClass.InstallHelper(new[] { Assembly.GetExecutingAssembly().Location });
        //                break;
        //            case "--uninstall":
        //                ManagedInstallerClass.InstallHelper(new[] { "/u", Assembly.GetExecutingAssembly().Location });
        //                break;
        //        }
        //    }
        //    else
        //    {
        //        //aqui é seu codigo para rodar o serviço normalmente.
        //        ServiceBase[] servicesToRun = new ServiceBase[]
        //                          {
        //                                new IntegradorService()
        //                          };
        //        ServiceBase.Run(servicesToRun);
        //    }
        //}

        //static void Main(string[] args)
        //{
        //    if (args.Length == 0)
        //    {
        //        // Run your service normally.
        //        ServiceBase[] ServicesToRun = new ServiceBase[] { new IntegradorService() };
        //        ServiceBase.Run(ServicesToRun);
        //    }
        //    else if (args.Length == 1)
        //    {
        //        switch (args[0])
        //        {
        //            case "-install":
        //                InstallService();
        //                StartService();
        //                break;
        //            case "-uninstall":
        //                StopService();
        //                UninstallService();
        //                break;
        //            default:
        //                throw new NotImplementedException();
        //        }
        //    }
        //}

    }
}
