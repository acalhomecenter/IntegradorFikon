using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Preco
{
    interface IPrecoRepositorio
    {
        IEnumerable<Preco> GetPrecosUpdate();
    }
}
