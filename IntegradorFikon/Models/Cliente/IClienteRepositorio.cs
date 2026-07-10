using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Cliente
{
    interface IClienteRepositorio
    {
        List<Cliente> GetClientes();
    }
}
