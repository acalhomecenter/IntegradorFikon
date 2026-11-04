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
            //ConString = "Data Source=sqlcs;User Id=app;Password=sqlbolim;Initial Catalog=dbHub";

            ConString = "Data Source=10.1.5.226;User Id=sa;Password=Underline5;Initial Catalog=dbHub";
        }

        public string ConString { get; set; }
    }
}
