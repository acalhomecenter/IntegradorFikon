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
            UrlBase = "https://dacal.fikon.com.br";
            //UrlBase = "https://hacal.fikon.com.br";
            //UrlBase = "https://acal.fikon.com.br";

            //UrlBase = "http://127.0.0.1:8065";
            //Produçao
            //ChaveApi = "Bearer 01nwXhX8CgJwGhwHTNb7dlX8Jzs54pwD60FZqRGBWm5rSAEzGvoumP4vcc*k2v*NHu";

           // Desenvolvimento
            ChaveApi = "Bearer 019i5zNyUUiR*BNbxwV_HhcSVrfOTZL0goKxlvNekeW3SP_XmoG*YuGV7XW21Evm3Y";

            ////Desenvolvimento2
            //ChaveApi = "Bearer 01G3nfdbOjWOLJrh1wzl5Z_R5ok7D9SQDEDn5dx7mfpdAUGvVpIfByqV1aRORtWcEG";


            //CHAVE_TEMPORARIA
            //ChaveApi = "Bearer 011DaxoVT* YKHSCI48UEebEtK5JFARrVQbc*HqXuRCwT3Vkglnb5iu1UmwiI6OOxcl";
        }
    }
}
