using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace IntegradorFikon.Conexao
{
    class ApiFikon
    {
        public string UrlBase { get; set; }
        public string ChaveApi { get; set; }

        public ApiFikon()
        {
            //UrlBase = "https://dacal.fikon.com.br";
            UrlBase = "http://127.0.0.1";
            ChaveApi = "Bearer 01AuLxiyljeDSHj1R2SswP4ysnVb8hS4oD0r81ruLt0SkMhsgfuX6PUJ_w7crAKfkx";
        }
    }
}
