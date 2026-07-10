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
            //UrlBase = "https://acal.fikon.com.br";

            UrlBase = "http://127.0.0.1";
            //Produçao
            //ChaveApi = "Bearer 01nwXhX8CgJwGhwHTNb7dlX8Jzs54pwD60FZqRGBWm5rSAEzGvoumP4vcc*k2v*NHu";

            //Desenvolvimento
            ChaveApi = "Bearer 01AuLxiyljeDSHj1R2SswP4ysnVb8hS4oD0r81ruLt0SkMhsgfuX6PUJ_w7crAKfkx";
        }
    }
}
