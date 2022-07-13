USE [GX_KB_VISION]
GO
/****** Object:  StoredProcedure [dbo].[SP_PlanAmortizacionGenerar]    Script Date: 29/03/2022 13:53:59 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_PlanAmortizacionGenerar]
(@P_NUMEROPROYECTO INT = NULL,
 @P_TIPOPLAN VARCHAR(10) = NULL,
 @P_PLANDEF VARCHAR(1) = NULL,
 @P_TRANSACCION VARCHAR(30) = NULL,
 @P_USUARIO VARCHAR(10) = NULL,
 @P_MSG VARCHAR(1000) OUTPUT)
AS
BEGIN
	BEGIN TRY
		SET LANGUAGE Spanish
		------------
		--Variables.
		------------
		DECLARE @V_ERRORMENSAJE VARCHAR(MAX) = ''
		DECLARE @V_VALORCREDITO INT = 0
		DECLARE @V_FECHAVENCIMIENTO DATE = NULL
		DECLARE @V_FECHANORMALIZACION DATE = NULL
		DECLARE @V_TASANMV DECIMAL(8,6) = 0
		DECLARE @V_VALORSEGURO MONEY = 0
		DECLARE @V_VALORCUOTAAPROBADA MONEY = 0
		DECLARE @V_ValorCuotaSeguro MONEY = 0
		DECLARE @V_NCUOTAMES INT = 1
		---------------------------------------------------
		--Variables para calcular plan aproximado con seguro.
		DECLARE @V_NCuotaMesAPR int = 1
		DECLARE @V_ValorCuotaSeguroAPR money = 0
		DECLARE @V_ValorCuotaCreditoAPR money = 0
		DECLARE @V_CreditoSaldoMesAPR int = 0
		DECLARE @V_CreditoCapitalMesAPR int = 0
		DECLARE @V_CreditoInteresMesAPR int = 0
		---------------------------------------------------
		--Variables para calcular normalizacion de pagos.
		DECLARE @V_FECHADESEMBOLSO_PRO DATE = NULL
		DECLARE @V_VALORDESEMBOLSO_PRO MONEY = 0
		DECLARE @V_DIASNORMALIZACION INT = 0
		DECLARE @V_VALORINTERESNORMALIZACION MONEY = 0
		DECLARE @V_TOTALINTERESNORMALIZACION MONEY = 0
		---------------------------------------------------
		--Variables para calcular plan definitivo con seguro.	
		DECLARE @V_VALORSALDOMES INT = 0
		DECLARE @V_VALORCAPITALMES INT = 0
		DECLARE @V_VALORINTERESMES INT = 0
		DECLARE @V_VALORSEGUROMES INT = 0
		----------------------------------------
		DECLARE @V_SeguroSaldoMes int = 0
		DECLARE @V_SeguroCapitalMes int = 0
		DECLARE @V_SeguroInteresMes int = 0
		---------------------------------------------------
		--Variables para regenerar plan de pagos por abono extra.
		DECLARE @V_VALORABONOSTOTAL MONEY = 0
		DECLARE @V_VALORSALDOTOTAL MONEY = 0
		DECLARE @V_VALORSALDONUEVO MONEY = 0
		DECLARE @V_ULTIMACUOTA INT = 0	
		------------------------------------------------
        --Validar el ingreso de parametros obligatorios.
        ------------------------------------------------
        IF @P_TIPOPLAN = 'APR'
        BEGIN
			IF Exists (SELECT * FROM [PlanAmortizacion] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO 
					   AND ([PlaAmoEstadoPlanAmortizacion] = 'DES' 
					   OR [PlaAmoEstadoPlanAmortizacion] = 'DEF'
					   OR [PlaAmoEstadoPlanAmortizacion] = 'REG'))
            BEGIN   
			    SET @V_ERRORMENSAJE = 'Ya existe un plan de amortización de desembolso, definitivo o regenerado.'
				GOTO R_PROCESAR_ERROR
			END	         
        END

-----------------------------
--PROCESAR PLAN AMORTIZACION.
-----------------------------
		--Se valida si el plan es Aprobación
		If @P_TIPOPLAN = 'APR'
		BEGIN
			--Se elimina el plan actual para el proyecto
			DELETE FROM [PlanAmortizacion] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO

			--Se busca el valor solicitud
			SET @V_VALORCREDITO = (SELECT TOP 1 [ProyectosValorAprobado] FROM [dbo].[Proyectos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
			
			--Se busca la fecha aprobacion para primer vencimiento
			SET @V_FECHAVENCIMIENTO = (SELECT TOP 1 [ProyectosFechaAproRec] FROM [dbo].[Proyectos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
		END

		--Se valida si el plan es Desembolso
		IF @P_TIPOPLAN = 'DES'
		BEGIN
			--Se elimina el plan actual para el proyecto
			DELETE FROM [PlanAmortizacion] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO

			--Se busca el valor del desembolso
			SET @V_VALORCREDITO = (SELECT TOP 1 SUM([DesembolsosValorDesembolso]) FROM [dbo].[Desembolsos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
			
			--Se busca la fecha desembolso
			SET @V_FECHAVENCIMIENTO = (SELECT TOP 1 MAX([DesembolsosFechaDesembolso]) FROM [dbo].[Desembolsos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)

			--Se busca la fecha normalizacion
			SET @V_FECHANORMALIZACION = (SELECT TOP 1 MAX([DesembolsosFechaNormalizacionP]) FROM [dbo].[Desembolsos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
		END

		--Se valida si el plan es Regenerado
		IF @P_TIPOPLAN = 'REG'
		BEGIN
			--Se busca el valor del desembolso
			SET @V_VALORCREDITO = (SELECT TOP 1 SUM([DesembolsosValorDesembolso]) FROM [dbo].[Desembolsos] 
									WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
			
			--Se busca ultima cuota pagada
			SET @V_ULTIMACUOTA = (SELECT TOP 1 MAX([PlAmDeNumeroCuota]) FROM [dbo].[PlanAmortizacionDef] 
									WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
									AND [PlAmDeCuotaCancelada] = 'S')

			IF @V_ULTIMACUOTA Is Null
			BEGIN
				SET @V_ULTIMACUOTA = 0
				SET @V_FECHAVENCIMIENTO = (SELECT TOP 1 MAX([DesembolsosFechaDesembolso]) FROM [dbo].[Desembolsos] 
											WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)
			END
			ELSE
			BEGIN
				--Se busca la fecha desembolso
				SET @V_FECHAVENCIMIENTO = (SELECT TOP 1 MAX([PlAmDeFechaVencimientoCuota]) FROM [dbo].[PlanAmortizacionDef]
											WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
											AND [PlAmDeNumeroCuota] = @V_ULTIMACUOTA)
			END

			--Calcular total abonos a capital
			SET @V_VALORABONOSTOTAL = (SELECT TOP 1 SUM([PagDetValorCapitalCuotaPagado]) FROM [dbo].[PagosDetalle] 
										WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
										AND [PagDetEstado] = '1')

			--Calcula nuevo saldo del credito
			 SET @V_VALORCREDITO = @V_VALORCREDITO - @V_VALORABONOSTOTAL	
			
			--Se elimina el plan actual para el proyecto
			DELETE FROM [dbo].[PlanAmortizacionDef] 
			WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO	
			AND [PlAmDeNumeroCuota] > @V_ULTIMACUOTA

			SET @V_ULTIMACUOTA = @V_ULTIMACUOTA + 1
		END

		--Se busca el valor de la tasa NMV
		SET @V_TASANMV = (SELECT TOP 1 [ProyectosTasaInteresNMV] FROM [dbo].[Proyectos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)

		--Si existe fecha de normalizacion se calcula los dias de diferencia con la fecha de vencimiento
		IF Not @V_FECHANORMALIZACION Is null and @V_FECHANORMALIZACION > @V_FECHAVENCIMIENTO
		BEGIN
		DECLARE CurDesembolsos CURSOR FOR SELECT [DesembolsosFechaDesembolso], [DesembolsosValorDesembolso] FROM [dbo].[Desembolsos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO ORDER BY [ProyectosNumeroProyecto], [DesembolsosFechaDesembolso]

		OPEN CurDesembolsos

		FETCH NEXT FROM CurDesembolsos INTO @V_FECHADESEMBOLSO_PRO, @V_VALORDESEMBOLSO_PRO

		WHILE @@fetch_status = 0 
		BEGIN

			SET @V_DIASNORMALIZACION = (SELECT DATEDIFF( DAY, @V_FECHADESEMBOLSO_PRO , @V_FECHANORMALIZACION))

			SET @V_VALORINTERESNORMALIZACION = ((((@V_VALORDESEMBOLSO_PRO * @V_TASANMV) / 100) / 30) * @V_DIASNORMALIZACION)

			SET @V_TOTALINTERESNORMALIZACION = @V_TOTALINTERESNORMALIZACION + @V_VALORINTERESNORMALIZACION

			--Inicializa variables de trabajo
			SET @V_DIASNORMALIZACION = 0
			SET @V_VALORINTERESNORMALIZACION = 0

			FETCH NEXT FROM CurDesembolsos INTO @V_FECHADESEMBOLSO_PRO, @V_VALORDESEMBOLSO_PRO	
		END	
					
		CLOSE CurDesembolsos 
		DEALLOCATE CurDesembolsos
		END

		--Se busca el valor del seguro
		SET @V_VALORSEGURO = (SELECT TOP 1 [ProyectosValorSeguroVida] FROM [dbo].[Proyectos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)

		--Se busca el valor de la cuota aprobada
		SET @V_VALORCUOTAAPROBADA = (SELECT TOP 1 [ProyectosValorCuotaAprobada] FROM [dbo].[Proyectos] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO)

		--SET @V_CreditoSaldoMesAPR = @V_VALORCREDITO

		--Cuota de credito menos la cuota aproximada del seguro
		--SET @V_ValorCuotaCreditoAPR = @V_VALORCUOTAAPROBADA - @V_VALORSEGURO

		--Se genera el plan amortización definitivo
		SET @V_VALORSALDOMES = @V_VALORCREDITO
		--SET @V_SeguroSaldoMes = @V_ValorSeguro 
		--SET @V_ValorCuotaSeguro = @V_ValorSeguro / @V_NCuotaMesAPR

		WHILE @V_VALORSALDOMES > 0
		BEGIN

			----SEGURO
			--SET @V_SeguroSaldoMes = @V_SeguroSaldoMes - @V_SeguroCapitalMes
			--SET @V_SeguroInteresMes = (@V_SeguroSaldoMes * @V_TASANMV) / 100

			--IF @V_SeguroSaldoMes > @V_SeguroCapitalMes
			--BEGIN
			--	SET @V_SeguroCapitalMes = @V_ValorCuotaSeguro
			--END
			--else
			--BEGIN
			--	SET @V_SeguroCapitalMes = @V_SeguroSaldoMes
			--END

			--CREDITO
			SET @V_VALORSALDOMES = @V_VALORSALDOMES - @V_VALORCAPITALMES
			SET @V_VALORINTERESMES = (@V_VALORSALDOMES * @V_TASANMV) / 100
			
			IF @V_VALORSALDOMES > @V_VALORCAPITALMES
			BEGIN
				IF @V_VALORSALDOMES	> @V_VALORCUOTAAPROBADA
				BEGIN
					SET @V_VALORCAPITALMES = @V_VALORCUOTAAPROBADA - @V_VALORINTERESMES - @V_VALORSEGURO
				END
				ELSE
				BEGIN
					SET @V_VALORCAPITALMES = @V_VALORSALDOMES
				END
			END
			ELSE
			BEGIN
				SET @V_VALORCAPITALMES = @V_VALORSALDOMES
			END

			If @V_NCUOTAMES = 1 AND @P_TIPOPLAN <> 'REG'
			BEGIN
				SET @V_VALORINTERESMES = @V_VALORINTERESMES + @V_TOTALINTERESNORMALIZACION 

				IF @V_TOTALINTERESNORMALIZACION > 0
				BEGIN
					SET @V_FECHAVENCIMIENTO = @V_FECHANORMALIZACION
				END
			END
			
			SET @V_FECHAVENCIMIENTO = DATEADD(month, 1, @V_FECHAVENCIMIENTO)

			IF @P_TIPOPLAN <> 'REG'
			BEGIN 
				INSERT INTO [dbo].[PlanAmortizacion] 
				VALUES(@P_NUMEROPROYECTO,
					   @V_NCUOTAMES,	
					   @V_FECHAVENCIMIENTO,
					   @V_VALORSALDOMES,
					   @V_VALORCAPITALMES,
					   @V_VALORINTERESMES,
					   @V_VALORSEGURO,
					   0, --Interes de mora
					   0, --Dias de mora
					   GETDATE(), --Fecha ultimo pago
					   'N', --Cuota cancelada
					   @P_TIPOPLAN,
					   '1',
					   @P_USUARIO,
					   GETDATE(),
					   @P_USUARIO,
					   GETDATE())

				SET @V_NCUOTAMES = @V_NCUOTAMES + 1
			END
			ELSE
			BEGIN
				INSERT INTO [dbo].[PlanAmortizacionDef]
				VALUES(@P_NUMEROPROYECTO,
					   @V_ULTIMACUOTA,	
					   @V_FECHAVENCIMIENTO,
					   @V_VALORSALDOMES,
					   @V_VALORCAPITALMES,
					   @V_VALORINTERESMES,
					   @V_VALORSEGURO,
					   0, --Interes de mora
					   0, --Dias de mora
					   GETDATE(), --Fecha ultimo pago
					   'N', --Cuota cancelada
					   @P_TIPOPLAN,
					   '1',
					   @P_USUARIO,
					   GETDATE(),
					   @P_USUARIO,
					   GETDATE())

				SET @V_ULTIMACUOTA = @V_ULTIMACUOTA + 1
			END

			IF @V_VALORSALDOMES <= @V_VALORCAPITALMES
			BEGIN
				SET @V_VALORSALDOMES = 0
			END
		END

		--Se valida si es plan definitivo
		IF @P_PLANDEF = 'S'
		BEGIN
			DELETE FROM [dbo].[PlanAmortizacionDef] WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO

			INSERT [dbo].[PlanAmortizacionDef] (
			[ProyectosNumeroProyecto],
			[PlAmDeNumeroCuota],
			[PlAmDeFechaVencimientoCuota],
			[PlAmDeValorSaldoCapital],
			[PlAmDeValorCapitalCuota],
			[PlAmDeValorInteresCuota],
			[PlAmDeValorSeguroCuota],
			[PlAmDeValorInteresMora],
			[PlAmDeDiasMora],
			[PlAmDeFechaUltimoPagoCuota],
			[PlAmDeCuotaCancelada],
			[PlAmDeEstadoPlanAmortizacion],
			[PlAmDeEstado],
			[PlAmDeUsuarioCreacion],
			[PlAmDeFechaCreacion],
			[PlAmDeUsuarioModificacion],
			[PlAmDeFechaModificacion])
			
			SELECT [ProyectosNumeroProyecto],
			[PlaAmoNumeroCuota],
			[PlaAmoFechaVencimientoCuota],
			[PlaAmoValorSaldoCapital],			
			[PlaAmoValorCapitalCuota],			
			[PlaAmoValorInteresCuota],			
			[PlaAmoValorSeguroCuota],			
			[PlaAmoValorInteresMora],			
			[PlaAmoDiasMora],			
			[PlaAmoFechaUltimoPagoCuota],			
			[PlaAmoCuotaCancelada],
			'DEF',	
			'1',
			@P_USUARIO,
			GETDATE(),
			@P_USUARIO,
			GETDATE()		
			FROM [dbo].[PlanAmortizacion] 
			WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
		END

		SET @V_ERRORMENSAJE = 'Proceso termino correctamente - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))
		INSERT INTO [dbo].[LogProceso] VALUES(
		GETDATE(), @P_TRANSACCION, 'Proceso', @V_ERRORMENSAJE, '1',
		@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())	

		RETURN

		R_PROCESAR_ERROR:
			SET @V_ERRORMENSAJE = @V_ERRORMENSAJE + ' - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))
			INSERT INTO [dbo].[LogProceso] VALUES(
			GETDATE(), @P_TRANSACCION, 'Error', @V_ERRORMENSAJE, '1',
			@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())
			RETURN
	END TRY
	BEGIN CATCH
		SET @V_ERRORMENSAJE = 'Error SQL: ' + ERROR_MESSAGE() + 
							  ' - Linea: ' + CAST((ERROR_LINE()) AS VARCHAR(MAX)) +
							  ' - Transacciones: ' + CAST((@@TRANCOUNT) AS VARCHAR(MAX)) +
							  ' - Msj: ' + @V_ERRORMENSAJE + ' - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))

		INSERT INTO [dbo].[LogProceso] VALUES(
		GETDATE(), @P_TRANSACCION, 'Catch', @V_ERRORMENSAJE, '1',
		@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())
	END CATCH
END