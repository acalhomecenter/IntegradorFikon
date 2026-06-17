using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Conexao
{
    class ConDbHub
    {
        public ConDbHub()
        {
            ConString = "Data Source=sqlcs;User Id=app;Password=sqlbolim;Initial Catalog=dbHub";

            //ConString = "Data Source=10.1.0.76;User Id=app;Password=sqlbolim;Initial Catalog=dbHub";
        }

        public string ConString { get; set; }
    }
}
