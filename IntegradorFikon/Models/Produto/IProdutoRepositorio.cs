using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Produtos
{
    interface IProdutoRepositorio
    {
        IEnumerable<Produto> GetItens();
        IEnumerable<Produto> GetItensUpdate();
        IEnumerable<Produto> GetItensTodos();
    }
}
