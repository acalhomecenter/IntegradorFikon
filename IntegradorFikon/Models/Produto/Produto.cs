using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Produtos
{

    public class Produto
    {
        public string codigo { get; set; }
        public string nome { get; set; }
        public string classe { get; set; }
        public string unidmedida { get; set; }
        public string clfiscal { get; set; }
        public string procedenci { get; set; }
        public string marca { get; set; }
        public string cor { get; set; }
        public string tamanho { get; set; }
        public string modelo { get; set; }
        public string fabricante { get; set; }
        public string referenciaPrincipal { get; set; }
        public string referenciaFabrica { get; set; }
        public string codprod { get; set; }
        public string descricaogenerica { get; set; }
        public List<Codigo> codigos { get; set; }
        public List<Fornecedor> fornecedores { get; set; }
    }

    public class Codigo
    {
        public string tipo { get; set; }
        public object codigo { get; set; }
    }

    public class Fornecedor
    {
        public string fornecedor { get; set; }
        public string principal { get; set; }
        public string entrega { get; set; }
        public string logistica { get; set; }
        public string mincompra { get; set; }
        public string economico { get; set; }
        public string qtdevolcompra { get; set; }
        public string comprador { get; set; }

    }

}
