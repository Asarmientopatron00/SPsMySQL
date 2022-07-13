USE [GX_KB_VISION]
GO
/****** Object:  StoredProcedure [dbo].[SP_PagosAplicar]    Script Date: 29/03/2022 12:13:13 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_PagosAplicar]
(@P_NUMEROPROYECTO INT = NULL,
 @P_FECHAPAGO DATE = NULL,
 @P_VALORPAGO MONEY = NULL,
 @+ VARCHAR(30) = NULL,
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
		--
		DECLARE @V_NUMEROCUOTA DECIMAL(10,0) = 0
		DECLARE @V_FECHAVENCIMIENTO DATE = NULL
		DECLARE @V_VALORCAPITALCUOTA MONEY = 0
		DECLARE @V_VALORINTERESCUOTA MONEY = 0
		DECLARE @V_VALORSEGUROCUOTA MONEY = 0
		DECLARE @V_VALORINTERESMORA MONEY = 0
		DECLARE @V_DIASMORA DECIMAL(10,0) = 0
		--
		DECLARE @V_VALORCAPITALPAGO MONEY = 0
		DECLARE @V_VALORCAPITALASALDAR MONEY = 0
		DECLARE @V_VALORINTERESPAGO MONEY = 0
		DECLARE @V_VALORSEGUROPAGO MONEY = 0
		DECLARE @V_VALORINTERESMORAPAGO MONEY = 0
		--
		DECLARE @V_APLICAEXTRA VARCHAR = NULL
		DECLARE @V_ULTIMACUOTAPAGADA DECIMAL(10,0) = 0
		DECLARE @V_ULTIMAFECHAPAGADA DATE = NULL
		DECLARE @V_APLICOPAGOS VARCHAR = NULL
		--
		DECLARE @V_CUOTACANCELADA VARCHAR(1) = NULL
		DECLARE @V_VALORABONOSTOTAL MONEY = 0
		DECLARE @V_VALORCREDITO INT = 0
		------------------------------------------------
        --Validar el ingreso de parametros obligatorios.
        ------------------------------------------------
        IF @P_NUMEROPROYECTO = 0 Or @P_NUMEROPROYECTO Is Null
        BEGIN  
			SET @V_ERRORMENSAJE = 'Número de proyecto es obligatorio.'
			GOTO R_PROCESAR_ERROR	         
        END

		IF @P_FECHAPAGO = ' ' Or @P_FECHAPAGO Is Null
        BEGIN  
			SET @V_ERRORMENSAJE = 'Fecha de pago es obligatorio.'
			GOTO R_PROCESAR_ERROR	         
        END

		IF @P_VALORPAGO = 0 Or @P_VALORPAGO Is Null
        BEGIN  
			SET @V_ERRORMENSAJE = 'Valor de pago es obligatorio.'
			GOTO R_PROCESAR_ERROR	         
        END
-----------------
--PROCESAR PAGOS.
-----------------
		IF @P_VALORPAGO <> 0
		BEGIN
			--Se velida el saldo del credito antes de aplicar
			--Se busca el valor del desembolso
			SET @V_VALORCREDITO = (SELECT TOP 1 SUM([DesembolsosValorDesembolso]) FROM [dbo].[Desembolsos] 
									WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
									AND [DesembolsosEstado] = '1')

			--Calcular total abonos a capital
			SET @V_VALORABONOSTOTAL = (SELECT TOP 1 SUM([PagDetValorCapitalCuotaPagado]) FROM [dbo].[PagosDetalle] 
										WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
										AND [PagDetEstado] = '1')
			
			IF @V_VALORCREDITO < @V_VALORABONOSTOTAL
			BEGIN  
				SET @V_ERRORMENSAJE = 'El saldo del credito es menor al pago a aplicar.'
				GOTO R_PROCESAR_ERROR	         
			END

			--Se selecciona las cuotas pendientes de pagar 
			DECLARE CurCuotasPendientes CURSOR FOR 
			SELECT [PlAmDeNumeroCuota], 
			[PlAmDeFechaVencimientoCuota], 
			[PlAmDeValorCapitalCuota],
			[PlAmDeValorInteresCuota], 
			[PlAmDeValorSeguroCuota], 
			[PlAmDeValorInteresMora], 
			[PlAmDeDiasMora]
			FROM [dbo].[PlanAmortizacionDef]
			WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
			AND [PlAmDeFechaVencimientoCuota] <= @P_FECHAPAGO
			AND [PlAmDeCuotaCancelada] = 'N'
			ORDER BY [ProyectosNumeroProyecto], [PlAmDeNumeroCuota]

			OPEN CurCuotasPendientes

			FETCH NEXT FROM CurCuotasPendientes INTO 
			@V_NUMEROCUOTA, @V_FECHAVENCIMIENTO, @V_VALORCAPITALCUOTA,
			@V_VALORINTERESCUOTA, @V_VALORSEGUROCUOTA, @V_VALORINTERESMORA,
			@V_DIASMORA

			--Procesar Cuotas
			WHILE @@fetch_status = 0
			BEGIN
				--Se selecciona los pagos aplicados a la cuota
				SET @V_VALORCAPITALPAGO = (SELECT SUM([PagDetValorCapitalCuotaPagado])
											FROM [dbo].[PagosDetalle]
											WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
											AND [PagDetNumeroCuota] = @V_NUMEROCUOTA
											AND [PagDetEstado] = '1')

				SET @V_VALORINTERESPAGO = (SELECT SUM([PagDetValorInteresCuotaPagado])
											FROM [dbo].[PagosDetalle]
											WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
											AND [PagDetNumeroCuota] = @V_NUMEROCUOTA
											AND [PagDetEstado] = '1')

				SET @V_VALORSEGUROPAGO = (SELECT SUM([PagDetValorSeguroCuotaPagado])
											FROM [dbo].[PagosDetalle]
											WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
											AND [PagDetNumeroCuota] = @V_NUMEROCUOTA
											AND [PagDetEstado] = '1')

				SET @V_VALORINTERESMORAPAGO = (SELECT SUM([PagDetValorInteresMoraPagado])
												FROM [dbo].[PagosDetalle]
												WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
												AND [PagDetNumeroCuota] = @V_NUMEROCUOTA
												AND [PagDetEstado] = '1')

				--Verifica si exiten pagos para la cuota
				If @V_VALORCAPITALPAGO <> 0 
				BEGIN
					SET @V_VALORCAPITALCUOTA = @V_VALORCAPITALCUOTA - @V_VALORCAPITALPAGO
				END
			
				If @V_VALORINTERESPAGO <> 0 
				BEGIN
					SET @V_VALORINTERESCUOTA = @V_VALORINTERESCUOTA - @V_VALORINTERESPAGO
				END
			
				If @V_VALORSEGUROPAGO <> 0 
				BEGIN
					SET @V_VALORSEGUROCUOTA = @V_VALORSEGUROCUOTA - @V_VALORSEGUROPAGO
				END

				If @V_VALORINTERESMORAPAGO <> 0
				BEGIN
					SET @V_VALORINTERESMORA = @V_VALORINTERESMORA - @V_VALORINTERESMORAPAGO
				END

				--------------
				--Aplica pagos
				--------------
				--Aplica Mora
				If @V_VALORINTERESMORA > @P_VALORPAGO
				BEGIN
					SET @V_VALORINTERESMORA = @P_VALORPAGO
					SET @P_VALORPAGO = 0
				END
				ELSE
				BEGIN
					SET @P_VALORPAGO = @P_VALORPAGO - @V_VALORINTERESMORA
				END

				--Aplica Interes
				If @V_VALORINTERESCUOTA > @P_VALORPAGO
				BEGIN
					SET @V_VALORINTERESCUOTA = @P_VALORPAGO
					SET @P_VALORPAGO = 0
				END
				ELSE
				BEGIN
					SET @P_VALORPAGO = @P_VALORPAGO - @V_VALORINTERESCUOTA
				END

				--Aplica Seguro
				If @V_VALORSEGUROCUOTA > @P_VALORPAGO
				BEGIN
					SET @V_VALORSEGUROCUOTA = @P_VALORPAGO
					SET @P_VALORPAGO = 0
				END
				ELSE
				BEGIN
					SET @P_VALORPAGO = @P_VALORPAGO - @V_VALORSEGUROCUOTA
				END

				--Aplica Capital
				SET @V_CUOTACANCELADA = 'S'

				If @V_VALORCAPITALCUOTA > @P_VALORPAGO
				BEGIN
					--Se calcula la diferencia de capital que falta por pagar para asignar a siguiente cuota
					SET @V_VALORCAPITALASALDAR = 0
					SET @V_VALORCAPITALASALDAR = @V_VALORCAPITALCUOTA - @P_VALORPAGO
					SET @V_VALORCAPITALCUOTA = @P_VALORPAGO
					SET @P_VALORPAGO = 0
				END
				ELSE
				BEGIN
					SET @P_VALORPAGO = @P_VALORPAGO - @V_VALORCAPITALCUOTA
				END

				--Graba registro de pago
				INSERT INTO [dbo].[PagosDetalle]
				VALUES(@P_NUMEROPROYECTO,
					@P_FECHAPAGO,
					@V_NUMEROCUOTA,
					@V_FECHAVENCIMIENTO,
					@V_VALORCAPITALCUOTA,
					@V_VALORINTERESCUOTA,
					@V_VALORSEGUROCUOTA,
					@V_VALORINTERESMORA,
					@V_DIASMORA,
					'1',
					@P_USUARIO,
					GETDATE(),
					@P_USUARIO,
					GETDATE())

				--Se cambia estado de la cuota
				UPDATE [dbo].[PlanAmortizacionDef] 
				SET [PlAmDeFechaUltimoPagoCuota] = @P_FECHAPAGO,
				[PlAmDeCuotaCancelada] = @V_CUOTACANCELADA 
				WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
				AND [PlAmDeNumeroCuota] = @V_NUMEROCUOTA

				--Valida si queda saldo a aplicar
				IF @P_VALORPAGO = 0
				BEGIN
					BREAK
				END

				--Leer siguiente cuota a aplicar
				FETCH NEXT FROM CurCuotasPendientes INTO 
				@V_NUMEROCUOTA, @V_FECHAVENCIMIENTO, @V_VALORCAPITALCUOTA,
				@V_VALORINTERESCUOTA, @V_VALORSEGUROCUOTA, @V_VALORINTERESMORA,
				@V_DIASMORA
			END
			CLOSE CurCuotasPendientes 
			DEALLOCATE CurCuotasPendientes

			--Aplica extra si despues de pagar cuotas vencidas queda saldo
			IF @P_VALORPAGO <> 0
			BEGIN 
				--Se busca la ultima cuota pagada
				SET @V_NUMEROCUOTA = (SELECT TOP 1 MAX([PlAmDeNumeroCuota]) 
										FROM [dbo].[PlanAmortizacionDef]
										WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
										AND [PlAmDeCuotaCancelada] = 'S')
					
				--Controla si no existen cuotas pagadas el valor se le asigna a la primera cuota
				IF @V_NUMEROCUOTA = 0 Or @V_NUMEROCUOTA Is Null
				BEGIN
					SET @V_NUMEROCUOTA = 1
				END
				ELSE
				BEGIN
					--Se busca la fecha de vencimiento de la proxima cuota a pagar
					SET @V_ULTIMAFECHAPAGADA = (SELECT TOP 1 [PlAmDeFechaUltimoPagoCuota] 
												FROM [dbo].[PlanAmortizacionDef]
												WHERE [PlAmDeNumeroCuota] = @V_NUMEROCUOTA)
				END

				--Se busca la fecha de vencimiento de la cuota que se procesa
				SET @V_FECHAVENCIMIENTO = (SELECT TOP 1 [PlAmDeFechaVencimientoCuota] 
											FROM [dbo].[PlanAmortizacionDef]
											WHERE [PlAmDeNumeroCuota] = @V_NUMEROCUOTA)
				
				--Inicializa variables de procesamiento
				SET @V_APLICAEXTRA = 'S'
				SET @V_CUOTACANCELADA = 'S'
				SET @V_VALORINTERESCUOTA = 0
				SET @V_VALORSEGUROCUOTA = 0
				SET @V_VALORCAPITALCUOTA = @P_VALORPAGO
				SET @P_VALORPAGO = 0

				--Se verifica si la fecha de pago es igual a la ultima cuota pagada
				IF @P_FECHAPAGO = @V_ULTIMAFECHAPAGADA
				BEGIN
					--Actualiza registro de pago
					UPDATE [dbo].[PagosDetalle] 
					SET [PagDetValorCapitalCuotaPagado] = [PagDetValorCapitalCuotaPagado] + @V_VALORCAPITALCUOTA
					WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
					AND [PagDetNumeroCuota] = @V_NUMEROCUOTA
				END
				ELSE
				BEGIN
					--Inserta registro de pago
					INSERT INTO [dbo].[PagosDetalle]
					VALUES(@P_NUMEROPROYECTO,
							@P_FECHAPAGO,
							@V_NUMEROCUOTA,
							@V_FECHAVENCIMIENTO,
							@V_VALORCAPITALCUOTA,
							@V_VALORINTERESCUOTA,
							@V_VALORSEGUROCUOTA,
							@V_VALORINTERESMORA,
							@V_DIASMORA,
							'1',
							@P_USUARIO,
							GETDATE(),
							@P_USUARIO,
							GETDATE())
				END

				--Se cambia estado de la cuota
				IF @V_NUMEROCUOTA = 1 
				BEGIN
					UPDATE [dbo].[PlanAmortizacionDef] 
					SET [PlAmDeFechaUltimoPagoCuota] = @P_FECHAPAGO,
					[PlAmDeCuotaCancelada] = @V_CUOTACANCELADA 
					WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
					AND [PlAmDeNumeroCuota] = @V_NUMEROCUOTA
				END
			END
		END

		--Aplica valor extra a capital y regenera plan de pagos
		IF @V_APLICAEXTRA = 'S' OR @V_VALORCAPITALASALDAR > 0
		BEGIN
			--Regenera Plan de Pagos
			EXEC [SP_PlanAmortizacionGenerar] @P_NUMEROPROYECTO,
                                              'REG',
											  'N',
											  @P_TRANSACCION,
										      @P_USUARIO,
										      @P_MSG

			--Recalcular mora
			EXEC [SP_CalcularValorInteresMora] @P_NUMEROPROYECTO, 1, @P_TRANSACCION, @P_USUARIO, @P_MSG
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