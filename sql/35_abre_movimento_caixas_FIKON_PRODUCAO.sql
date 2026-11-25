/* =====================================================================================================
   Script 35 (24/11/2026) - Job "Rotinas - 17_INSERE_CXA_MOVIMENTO" passa a abrir também o movimento
   dos caixas da FIKON (dbgemco.dbo.FIKON_CAD_CAIXA)

   Antes o cursor só pegava os caixas CXA_CAIXAS com DESCXA LIKE '%cartoes%' (operador CODOPERTOTEM).
   Agora pega também os caixa/operador da FIKON_CAD_CAIXA (ex.: filial 15 caixa 4 / operador 24 PDVFIKON).
   A regra continua a mesma: só abre o movimento do dia se o caixa/operador tiver lançamento no dia na
   CXA_LANCTO e ainda não tiver movimento no dia.

   Duas formas de aplicar (use UMA):
     A) colar o texto do passo (bloco entre as linhas ===== abaixo) no passo 1 ("Insert") do job pelo SSMS;
     B) rodar o sp_update_jobstep do final deste arquivo.
   ===================================================================================================== */

/* ===================== TEXTO DO PASSO 1 DO JOB (database dbgemco) =====================
declare @codfil int
declare @numcxa int
declare @codoper int
declare @data date = cast(getdate() as date)

DECLARE CR_CAIXAS CURSOR FOR
        select codfil,numcxa,CODOPERTOTEM from dbgemco..CXA_CAIXAS where  DESCXA like '%cartoes%'
        union
        -- script 35: caixas/operadores dos lançamentos integrados da FIKON
        select CODFIL,CAIXA,CODOPER from dbgemco..FIKON_CAD_CAIXA where CAIXA is not null and CODOPER is not null
    OPEN CR_CAIXAS
        FETCH NEXT FROM CR_CAIXAS INTO @codfil,@numcxa,@codoper
            WHILE @@FETCH_STATUS = 0
                BEGIN


				if(select count(*) from cxa_lancto where codfil=@codfil and numcxa = @numcxa and CODOPER =@codoper and cast(DATENT as date) = @data) > 0

				   begin

					 if(select count(*) from cxa_movimento where codfil=@codfil and numcxa = @numcxa and CODOPER =@codoper and cast(dataini as date) = @data) = 0
					   begin

					   insert into dbgemco..cxa_movimento values (@codfil,@numcxa,1,@codoper,@data,'I',null,null,null,null,0,0,null,null,null,0,null,null,null,null,null,null,null,'N',null)

					   end


				   end




	        FETCH NEXT FROM CR_CAIXAS INTO
                                @codfil,@numcxa,@codoper

                END
    CLOSE CR_CAIXAS
    DEALLOCATE CR_CAIXAS
   ======================================================================================= */


/* ---------------------------------------------------------------------------------------------
   B) Atualiza o passo 1 do job pelo script (mesmo texto acima)
   --------------------------------------------------------------------------------------------- */
USE [msdb]
GO

EXEC msdb.dbo.sp_update_jobstep
     @job_name = N'Rotinas - 17_INSERE_CXA_MOVIMENTO',
     @step_id = 1,
     @command = N'declare @codfil int
declare @numcxa int
declare @codoper int
declare @data date = cast(getdate() as date)

DECLARE CR_CAIXAS CURSOR FOR
        select codfil,numcxa,CODOPERTOTEM from dbgemco..CXA_CAIXAS where  DESCXA like ''%cartoes%''
        union
        -- script 35: caixas/operadores dos lançamentos integrados da FIKON
        select CODFIL,CAIXA,CODOPER from dbgemco..FIKON_CAD_CAIXA where CAIXA is not null and CODOPER is not null
    OPEN CR_CAIXAS
        FETCH NEXT FROM CR_CAIXAS INTO @codfil,@numcxa,@codoper
            WHILE @@FETCH_STATUS = 0
                BEGIN


				if(select count(*) from cxa_lancto where codfil=@codfil and numcxa = @numcxa and CODOPER =@codoper and cast(DATENT as date) = @data) > 0

				   begin

					 if(select count(*) from cxa_movimento where codfil=@codfil and numcxa = @numcxa and CODOPER =@codoper and cast(dataini as date) = @data) = 0
					   begin

					   insert into dbgemco..cxa_movimento values (@codfil,@numcxa,1,@codoper,@data,''I'',null,null,null,null,0,0,null,null,null,0,null,null,null,null,null,null,null,''N'',null)

					   end


				   end




	        FETCH NEXT FROM CR_CAIXAS INTO
                                @codfil,@numcxa,@codoper

                END
    CLOSE CR_CAIXAS
    DEALLOCATE CR_CAIXAS';
GO

-- confere o texto gravado no passo
SELECT j.name, s.step_id, s.database_name, s.command
  FROM msdb.dbo.sysjobs j JOIN msdb.dbo.sysjobsteps s ON s.job_id = j.job_id
 WHERE j.name = N'Rotinas - 17_INSERE_CXA_MOVIMENTO';
GO
