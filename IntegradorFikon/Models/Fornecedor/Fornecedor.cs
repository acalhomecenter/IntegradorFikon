using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Fornecedor
{
    

        public class Fornecedor
        {
            public string codigo { get; set; }
            public string classe { get; set; }
            public string inscEstad { get; set; }
            public Enderecosadicionai[] enderecosAdicionais { get; set; }
            public string inscMunic { get; set; }
            public string email { get; set; }
            public string razaoSocial { get; set; }
            public string fone { get; set; }
            public string compFiscal { get; set; }
            public int chave { get; set; }
            public string nome { get; set; }
            public Enderecoprincipal enderecoPrincipal { get; set; }
            public string cpfcnpj { get; set; }
        }

        public class Enderecoprincipal
        {
            public string pontoRefer { get; set; }
            public string numero { get; set; }
            public string bairro { get; set; }
            public string uf { get; set; }
            public string logradouro { get; set; }
            public string complemento { get; set; }
            public string cidade { get; set; }
            public string zona { get; set; }
            public string tipoLogradouro { get; set; }
            public string cep { get; set; }

    }

        public class Enderecosadicionai
        {
            public bool entrega { get; set; }
            public string classe { get; set; }
            public string bairro { get; set; }
            public int chave { get; set; }
            public string numero { get; set; }
            public string uf { get; set; }
            public bool cobranca { get; set; }
            public string logradouro { get; set; }
            public string complemento { get; set; }
            public string cidade { get; set; }
            public string cep { get; set; }
        }




    
}
