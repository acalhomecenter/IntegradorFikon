﻿﻿using IntegradorFikon.Models.Produtos;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fikon
{
    interface IFikonRepositorio
    {
        void insereProdutoFikonTodos(IEnumerable<Produto> prods);
        Task insereProdutoFikon(IEnumerable<Produto> prods);
        Task atualizaProdutoFikon(IEnumerable<Produto> prods);
        Task insereFornecedorFikon(IEnumerable<IntegradorFikon.Models.Fornecedor.Fornecedor> forne);
        Task inserePrecoFikon(IEnumerable<IntegradorFikon.Models.Preco.Preco> preco);
        void insereClientesFikonTodos(List<Models.Cliente.Cliente> cliente);
        Task insereClientesFikon(List<Models.Cliente.Cliente> cliente);
        Task consultarStatusPedidosFikon();
        Task consultarFaturamentoPedidosFikon();
    }
}
