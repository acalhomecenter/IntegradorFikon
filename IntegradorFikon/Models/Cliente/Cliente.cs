using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Models.Cliente
{

    public class Cliente
    {
        public string cpfcnpj { get; set; }
        public string classe { get; set; }
        public string nome { get; set; }
        public string razaoSocial { get; set; }
        public string codigo { get; set; }
        public string email { get; set; }
        public string fone { get; set; }
        public string celular { get; set; }
        public string rg { get; set; }
        public string nascimento { get; set; }
        public string sexo { get; set; }
        public string estadoCivil { get; set; }
        public string profissao { get; set; }
        public string compFiscal { get; set; }
        public string inscEstadual { get; set; }
        public string inscMunicipal { get; set; }
        public string obsGerais { get; set; }
        public Enderecoprincipal enderecoPrincipal { get; set; }
        public List<Enderecosadicionais> enderecosAdicionais { get; set; }
    }

    public class Enderecoprincipal
    {
        public string cep { get; set; }
        public string tipoLogradouro { get; set; }
        public string logradouro { get; set; }
        public string numero { get; set; }
        public string complemento { get; set; }
        public string bairro { get; set; }
        public string cidade { get; set; }
        public string uf { get; set; }
    }

    public class Enderecosadicionais
    {
        public string cep { get; set; }
        public string tipoLogradouro { get; set; }
        public string logradouro { get; set; }
        public string numero { get; set; }
        public string complemento { get; set; }
        public string bairro { get; set; }
        public string cidade { get; set; }
        public string uf { get; set; }
        public bool entrega { get; set; }
        public bool cobranca { get; set; }
    }

}
