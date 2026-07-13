﻿﻿﻿using IntegradorFikon.Models.Produtos;
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
        void insereProdutoFikon(IEnumerable<Produto> prods);
        void atualizaProdutoFikon(IEnumerable<Produto> prods);
        void insereFornecedorFikon(IEnumerable<IntegradorFikon.Models.Fornecedor.Fornecedor> forne);
        void inserePrecoFikon(IEnumerable<IntegradorFikon.Models.Preco.Preco> preco);
        void insereClientesFikonTodos(List<Models.Cliente.Cliente> cliente);
        Task consultarStatusPedidosFikon();
    }
}
