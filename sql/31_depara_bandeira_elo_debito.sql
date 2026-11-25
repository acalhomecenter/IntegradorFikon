/*
  31 - De-para de bandeiras FIKON: nomes com "Débito"/"Crédito" (ex.: "Elo Débito")  -  23/11/2026
  Rodar nas DUAS bases: DEV (DB-TREINO 10.1.5.226) e PRODUÇÃO (SQLPROD / sqlcs.acal.local), banco dbgemco.

  Erro (VENDA 32):
    "Bandeira FIKON "Elo Débito" (debito) sem de-para em dbgemco.dbo.FIKON_DEPARA_BANDEIRA."
    A SP_FIKON_NOTA_GRAVAR_FINANCEIRO procura a bandeira pelo nome inteiro (ignorando acento e maiúscula).
    A carga do script 08 tem 'ELO' (débito -> convênio 29), mas não 'ELO DEBITO'. Para Mastercard já existia
    'MASTERCARD DEBITO'; as demais variações com o tipo no nome não existiam.

  O que o script faz: inclui as variações abaixo, com os MESMOS convênios da carga inicial (script 08),
  só se ainda não existirem e só se o convênio existir no CXA_CADCON. Nada é alterado nem apagado.
      ELO DEBITO          D  29  (= ELO débito)
      ELO CREDITO         C  30  (= ELO crédito)
      VISA DEBITO         D  11  (= VISA débito)
      VISA CREDITO        C   2  (= VISA crédito)
      MASTERCARD CREDITO  C   1  (= MASTERCARD crédito)
      MASTER DEBITO       D  10  (= MASTERCARD débito)
      MASTER CREDITO      C   1  (= MASTERCARD crédito)
  Antes de incluir, o script confere se a linha base da carga inicial (ex.: 'ELO' débito) ainda aponta para o
  mesmo convênio; se alguém mudou, usa o convênio que está hoje na linha base.

  Como rodar: no SSMS, conectado no banco dbgemco, executar o script INTEIRO (F5). Repetir na outra base.
  Depois: reenviar da FIKON a VENDA 32.
*/
SET NOCOUNT ON;

DECLARE @novas TABLE (BANDEIRA_FIKON varchar(40), TIPO char(1), BASE varchar(40), CODCON_PADRAO int, OBS varchar(100));
INSERT INTO @novas VALUES
    ('ELO DEBITO',         'D', 'ELO',        29, 'Elo debito (nome com o tipo)'),
    ('ELO CREDITO',        'C', 'ELO',        30, 'Elo credito (nome com o tipo)'),
    ('VISA DEBITO',        'D', 'VISA',       11, 'Visa debito (nome com o tipo)'),
    ('VISA CREDITO',       'C', 'VISA',        2, 'Visa credito (nome com o tipo)'),
    ('MASTERCARD CREDITO', 'C', 'MASTERCARD',  1, 'Mastercard credito (nome com o tipo)'),
    ('MASTER DEBITO',      'D', 'MASTERCARD', 10, 'Mastercard debito (nome com o tipo)'),
    ('MASTER CREDITO',     'C', 'MASTERCARD',  1, 'Mastercard credito (nome com o tipo)');

-- convênio = o da linha base (ex.: 'ELO' débito) se existir; senão o padrão do script 08
DECLARE @plano TABLE (BANDEIRA_FIKON varchar(40), TIPO char(1), CODCON int, OBS varchar(100), SITUACAO varchar(60));
INSERT INTO @plano
SELECT n.BANDEIRA_FIKON, n.TIPO,
       ISNULL(b.CODCON, n.CODCON_PADRAO),
       n.OBS,
       CASE WHEN EXISTS (SELECT 1 FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA x
                          WHERE x.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI = n.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI
                            AND x.TIPO = n.TIPO)
                 THEN 'ja existe (nao muda)'
            WHEN NOT EXISTS (SELECT 1 FROM dbgemco..CXA_CADCON c WHERE c.CODCON = ISNULL(b.CODCON, n.CODCON_PADRAO))
                 THEN 'convenio nao existe no CXA_CADCON (nao incluida)'
            ELSE 'incluir' END
  FROM @novas n
  OUTER APPLY (SELECT TOP (1) x.CODCON FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA x
                WHERE x.BANDEIRA_FIKON COLLATE Latin1_General_CI_AI = n.BASE COLLATE Latin1_General_CI_AI
                  AND x.TIPO = n.TIPO AND x.ATIVO = 1
                ORDER BY x.ID) b;

SELECT 'PLANO' AS momento, BANDEIRA_FIKON, TIPO, CODCON, SITUACAO FROM @plano ORDER BY BANDEIRA_FIKON, TIPO;

INSERT INTO dbgemco.dbo.FIKON_DEPARA_BANDEIRA (BANDEIRA_FIKON, TIPO, CODCON, OBS)
SELECT BANDEIRA_FIKON, TIPO, CODCON, OBS FROM @plano WHERE SITUACAO = 'incluir';

PRINT CONCAT(@@ROWCOUNT, ' variacao(oes) incluida(s) no de-para de bandeiras.');

SELECT 'DEPOIS' AS momento, ID, BANDEIRA_FIKON, TIPO, CODCON, ATIVO, OBS
  FROM dbgemco.dbo.FIKON_DEPARA_BANDEIRA
 ORDER BY BANDEIRA_FIKON, TIPO;
