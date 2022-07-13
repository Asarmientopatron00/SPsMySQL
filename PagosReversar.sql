USE [GX_KB_VISION]
GO
/****** Object:  StoredProcedure [dbo].[SP_PagosReversar]    Script Date: 29/03/2022 13:53:40 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_PagosReversar]
(@P_NUMEROPROYECTO INT = NULL,
 @P_FECHAPAGO DATE = NULL,
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
		DECLARE @V_ERROR_MENSAJE VARCHAR(MAX) = ''
		--
		DECLARE @V_NUMEROCUOTA DECIMAL(10,0) = 0
		DECLARE @V_INDREVERSAR VARCHAR(1) = ''

		------------------------------------------------
        --Validar el ingreso de parametros obligatorios.
        ------------------------------------------------
        IF @P_NUMEROPROYECTO = 0 Or @P_NUMEROPROYECTO Is Null
        BEGIN  
			SET @V_ERROR_MENSAJE = 'Número de proyecto es obligatorio.'
			GOTO R_PROCESAR_ERROR	         
        END

		IF @P_FECHAPAGO = ' ' Or @P_FECHAPAGO Is Null
        BEGIN  
			SET @V_ERROR_MENSAJE = 'Fecha de pago es obligatorio.'
			GOTO R_PROCESAR_ERROR	         
        END

		IF Exists (SELECT * FROM [dbo].[Pagos] 
					WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO 
					AND [PagEncFechaPago] > @P_FECHAPAGO
					AND [PagEncEstado] = '1')
        BEGIN   
			SET @V_ERROR_MENSAJE = 'Existe pagos con fecha posterior al que se va a reversar.'
			GOTO R_PROCESAR_ERROR
		END	
-----------------------------
--PROCESAR PAGOS A REVERSAR.
-----------------------------
		--Inactiva el pago
		UPDATE [dbo].[Pagos]
		SET [PagEncEstado] = '0'
		WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
		AND [PagEncFechaPago] = @P_FECHAPAGO

		--Inactiva el detalle del pago
		UPDATE [dbo].[PagosDetalle]
		SET [PagDetEstado] = '0'
		WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
		AND [PagEncFechaPago] = @P_FECHAPAGO

		--Busca las cuotas que se cancelaron con el pago a reversar para cambiarle el estado como no pagadas
		DECLARE CurCuotasAReversar CURSOR FOR 
		SELECT [PagDetNumeroCuota]
		FROM [dbo].[PagosDetalle]
		WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
		AND [PagEncFechaPago] = @P_FECHAPAGO
		ORDER BY [ProyectosNumeroProyecto], [PagEncFechaPago]

		OPEN CurCuotasAReversar

		FETCH NEXT FROM CurCuotasAReversar INTO @V_NUMEROCUOTA

		--Procesar Cuotas
		WHILE @@fetch_status = 0
		BEGIN
			--Se cambia el estado a las cuotas a reversar
			UPDATE [dbo].[PlanAmortizacionDef]
			SET [PlAmDeCuotaCancelada] = 'N'
			WHERE [ProyectosNumeroProyecto] = @P_NUMEROPROYECTO
			AND [PlAmDeNumeroCuota] = @V_NUMEROCUOTA
			AND [PlAmDeFechaUltimoPagoCuota] = @P_FECHAPAGO

			SET @V_INDREVERSAR = 'S'

			--Leer siguiente cuota a aplicar
			FETCH NEXT FROM CurCuotasAReversar INTO @V_NUMEROCUOTA
		END
		CLOSE CurCuotasAReversar 
		DEALLOCATE CurCuotasAReversar

		--Si se reversaron pagos, regenera plan de pagos
		IF @V_INDREVERSAR = 'S'
		BEGIN
			--Regenera Plan de Pagos
			EXEC [SP_PlanAmortizacionGenerar] @P_NUMEROPROYECTO,
                                              'REG',
											  'N',
											  @P_TRANSACCION,
										      @P_USUARIO,
										      @P_MSG
		END

		SET @V_ERROR_MENSAJE = 'Proceso termino correctamente - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))
		INSERT INTO [dbo].[LogProceso] VALUES(
		GETDATE(), @P_TRANSACCION, 'Proceso', @V_ERROR_MENSAJE, '1',
		@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())	

		RETURN

		R_PROCESAR_ERROR:
			SET @V_ERROR_MENSAJE = @V_ERROR_MENSAJE + ' - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))
			INSERT INTO [dbo].[LogProceso] VALUES(
			GETDATE(), @P_TRANSACCION, 'Error', @V_ERROR_MENSAJE, '1',
			@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())			 
			RETURN
	END TRY
	BEGIN CATCH
		 SET @V_ERROR_MENSAJE = 'Error SQL: ' + ERROR_MESSAGE() + 
				    			' - Linea: ' + CAST((ERROR_LINE()) AS VARCHAR(MAX)) +
								' - Transacciones: ' + CAST((@@TRANCOUNT) AS VARCHAR(MAX)) +
								' - Msj: ' + @V_ERROR_MENSAJE + ' - Proyecto : ' + CAST((@P_NUMEROPROYECTO) AS VARCHAR(MAX))

		 INSERT INTO [dbo].[LogProceso] VALUES(
		 GETDATE(), @P_TRANSACCION, 'Catch', @V_ERROR_MENSAJE, '1',
		 @P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())
	END CATCH
END