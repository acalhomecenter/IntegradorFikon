using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fornecedor
{
    interface IFornecedorRepositorio
    {
        IEnumerable<Fornecedor> GetFornecedores();
    }
}
