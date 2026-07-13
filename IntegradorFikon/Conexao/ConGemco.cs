using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Conexao
{
    class ConGemco
    {
        public ConGemco()
        {
            //ConString = "Data Source =sqlcs; User Id = sa; Password = sqlrollback; Initial Catalog = dbGemco";
            ConString = "Data Source =10.1.5.226; User Id = sa; Password = Underline5; Initial Catalog = dbGemco";
        }

        public string ConString { get; set; }
    }
}
