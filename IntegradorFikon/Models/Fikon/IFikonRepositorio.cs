using IntegradorFikon.Models.Produtos;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fikon
{
    interface IFikonRepositorio
    {
        void insereProdutoFikon(IEnumerable<Produto> prods);
        void atualizaProdutoFikon(IEnumerable<Produto> prods);
        void insereFornecedorFikon(IEnumerable<IntegradorFikon.Models.Fornecedor.Fornecedor> forne);
        void inserePrecoFikon(IEnumerable<IntegradorFikon.Models.Preco.Preco> preco);
    }
}
