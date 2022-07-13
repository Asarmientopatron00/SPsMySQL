USE [GX_KB_VISION]
GO
/****** Object:  StoredProcedure [dbo].[SP_CalcularValorInteresMora]    Script Date: 29/03/2022 13:52:45 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_CalcularValorInteresMora] 
(
	@P_NUMEROPROYECTO DECIMAL(15, 0) = NULL,
	@P_REINICIARMORA BIT = 0,
	@P_TRANSACCION VARCHAR(30) = NULL,
	@P_USUARIO VARCHAR(10) = NULL,
	@P_MSG VARCHAR(1000) OUTPUT
)
AS
BEGIN
	BEGIN TRY
		SET LANGUAGE Spanish
		------------
		--Variables.
		------------
		DECLARE @V_FECHA_EJECUCION DATE = GETDATE()
		DECLARE @V_ERROR_MENSAJE VARCHAR(MAX) = ''
		--
		DECLARE @V_NUMERO_PROYECTO DECIMAL(15, 0) = 0
		DECLARE @V_NUMERO_CUOTA DECIMAL(10, 0) = 0
		DECLARE @V_FECHA_VENCIMIENTO_CUOTA DATETIME = NULL
		DECLARE @V_VALOR_CAPITAL_CUOTA MONEY = 0
		DECLARE @V_DIAS_DE_MORA INT = NULL
		DECLARE @V_VALOR_INTERES_MORA MONEY = NULL
		--
		DECLARE @V_DIAS_GRACIA_CALCULO_MORA INT = NULL
		DECLARE @V_INTERES_CALCULO_MORA DECIMAL(9, 5) = NULL
		DECLARE @V_FECHA_ULTIMO_CALCULO_MORA DATE = NULL
		--
		DECLARE @V_FECHA_FINAL_DIAS_GRACIA DATE = NULL
		DECLARE @V_DIAS_INTERESES_PERDIDOS INT = NULL
		DECLARE @V_INTERES_CALCULADO DECIMAL(9, 5) = NULL
		DECLARE @V_EXISTE_CONFIGURACION SMALLINT = 0

		-------------------------------------
		--PROCESAR CALCULO VALOR INTERES MORA
		-------------------------------------
		--Obtener parametro de días de gracia
		SET @V_DIAS_GRACIA_CALCULO_MORA = (SELECT ConfiguracionValorNumerico 
											FROM Configuracion 
											WHERE ConfiguracionClave = 'DiasGraciaCalculoMora')
		SET @V_DIAS_GRACIA_CALCULO_MORA = (SELECT ISNULL(@V_DIAS_GRACIA_CALCULO_MORA, 1))

		--Obtener parametro interes de mora
		SET @V_INTERES_CALCULO_MORA = (SELECT ConfiguracionValorNumerico 
										FROM Configuracion 
										WHERE ConfiguracionClave = 'InteresCalculoMora')

		IF @V_INTERES_CALCULO_MORA IS NUll
        BEGIN  
			SET @V_ERROR_MENSAJE = 'El porcentaje de interes para el calculo de mora es obligatorio'
			GOTO R_PROCESAR_ERROR
        END
		
		--Se pasa de porcentual a decimal
		SET @V_INTERES_CALCULO_MORA = @V_INTERES_CALCULO_MORA / 100

		--Obtener parametro fecha de última ejecución proceso calculo mora
		SET @V_FECHA_ULTIMO_CALCULO_MORA = (SELECT CONVERT(DATE, ConfiguracionValorTexto, 5)			
											FROM Configuracion 
											WHERE ConfiguracionClave = 'FechaUltimaEjecucionCalculoMora');
		
		IF @V_FECHA_ULTIMO_CALCULO_MORA IS NOT NULL
		BEGIN
			SET @V_EXISTE_CONFIGURACION = 1;
			IF DATEDIFF(DAY, CAST(@V_FECHA_ULTIMO_CALCULO_MORA AS nvarchar(30)), 
					CAST(@V_FECHA_EJECUCION AS nvarchar(30))) = 0 AND @P_NUMEROPROYECTO IS NULL AND @P_REINICIARMORA = 1
			BEGIN
				SET @V_ERROR_MENSAJE = 'No se puede ejecutar el calculo del valor de interes por mora dos veces el mismo día'
				GOTO R_PROCESAR_ERROR
			END
		END
		ELSE
		BEGIN
			SET @V_FECHA_ULTIMO_CALCULO_MORA = (SELECT ISNULL(@V_FECHA_ULTIMO_CALCULO_MORA, @V_FECHA_EJECUCION));
		END

		--Se seleccionan las cuotas pendientes por pagar
		IF @P_NUMEROPROYECTO IS NOT NULL AND @P_NUMEROPROYECTO <> 0
		BEGIN
			DECLARE CurCuotasPendientes CURSOR FOR 
			SELECT ProyectosNumeroProyecto,
			PlAmDeNumeroCuota, 
			PlAmDeFechaVencimientoCuota, 
			PlAmDeValorCapitalCuota
			FROM PlanAmortizacionDef
			WHERE ProyectosNumeroProyecto = @P_NUMEROPROYECTO
			AND PlAmDeFechaVencimientoCuota <= @V_FECHA_EJECUCION
			AND PlAmDeCuotaCancelada = 'N'
			ORDER BY ProyectosNumeroProyecto, PlAmDeNumeroCuota
		END
		ELSE
		BEGIN
			DECLARE CurCuotasPendientes CURSOR FOR 
			SELECT ProyectosNumeroProyecto,
			PlAmDeNumeroCuota, 
			PlAmDeFechaVencimientoCuota, 
			PlAmDeValorCapitalCuota
			FROM PlanAmortizacionDef
			WHERE PlAmDeFechaVencimientoCuota <= @V_FECHA_EJECUCION
			AND PlAmDeCuotaCancelada = 'N'
			ORDER BY ProyectosNumeroProyecto, PlAmDeNumeroCuota
		END

		OPEN CurCuotasPendientes

		FETCH NEXT FROM CurCuotasPendientes INTO 
		@V_NUMERO_PROYECTO, @V_NUMERO_CUOTA,
		@V_FECHA_VENCIMIENTO_CUOTA, @V_VALOR_CAPITAL_CUOTA

		--Procesar Cuotas Pendientes
		WHILE @@fetch_status = 0
		BEGIN
			-- Reiniciar el calculo de la mora para las nuevas cuotas, luego de regenerar pagos
			IF @P_REINICIARMORA = 1
			BEGIN
				SET @V_FECHA_ULTIMO_CALCULO_MORA = (SELECT DATEADD(DAY, -1, @V_FECHA_VENCIMIENTO_CUOTA))
			END

			--Se obtiene la fecha del último día de gracia
			SET @V_FECHA_FINAL_DIAS_GRACIA = (SELECT DATEADD(DAY, 
													@V_DIAS_GRACIA_CALCULO_MORA, 
													@V_FECHA_VENCIMIENTO_CUOTA))

			--Se verifica que se cumplan los días de gracia para procesar
			IF DATEDIFF(DAY, CAST(@V_FECHA_FINAL_DIAS_GRACIA AS nvarchar(30)), 
						CAST(@V_FECHA_EJECUCION AS nvarchar(30))) >= 0
			BEGIN
				--Pasados los días gracia, se cobra el interes desde el día de vencimiento (Incluido)
				IF DATEDIFF(DAY, CAST(@V_FECHA_FINAL_DIAS_GRACIA AS nvarchar(30)), 
							CAST(@V_FECHA_EJECUCION AS nvarchar(30))) = 1
				BEGIN
					SET @V_DIAS_DE_MORA = @V_DIAS_GRACIA_CALCULO_MORA + 1
				END
				ELSE
				BEGIN
					--Si la última ejecución fue el día anterior, no se perdieron intereses
					IF DATEDIFF(DAY, CAST(@V_FECHA_ULTIMO_CALCULO_MORA AS nvarchar(30)), 
								CAST(@V_FECHA_EJECUCION AS nvarchar(30))) IN (0, 1)
					BEGIN
						SET @V_DIAS_DE_MORA = 1
					END
					ELSE
					BEGIN
						--Si la última fecha de ejecución fue despues del periodo de gracia
						--se calculan los días perdidos con respecto al día que se ejecuto
						--el proceso por última vez (Día no incluido)
						IF DATEDIFF(DAY, CAST(@V_FECHA_FINAL_DIAS_GRACIA AS nvarchar(30)), 
									CAST(@V_FECHA_ULTIMO_CALCULO_MORA AS nvarchar(30))) >= 0
						BEGIN
							SET @V_DIAS_INTERESES_PERDIDOS = (SELECT DATEDIFF(DAY, 
															CAST(@V_FECHA_ULTIMO_CALCULO_MORA AS nvarchar(30)), 
															CAST(@V_FECHA_EJECUCION AS nvarchar(30))) - 1)
						END
						--Si la última fecha de ejecución fue antes del periodo de gracia
						--se calculan los días perdidos con respecto a la fecha de 
						--vencimiento de la cuota (Día no incluido)
						ELSE
						BEGIN
							SET @V_DIAS_INTERESES_PERDIDOS = (SELECT DATEDIFF(DAY, 
															CAST(@V_FECHA_VENCIMIENTO_CUOTA AS nvarchar(30)), 
															CAST(@V_FECHA_EJECUCION AS nvarchar(30))) - 1)
						END

						SET @V_DIAS_DE_MORA = @V_DIAS_INTERESES_PERDIDOS + 1
					END
				END
			
				--Calculo del valor del interes diario
				SET @V_INTERES_CALCULADO = (@V_INTERES_CALCULO_MORA / 30) * @V_DIAS_DE_MORA
				-- SET @V_VALOR_INTERES_MORA = @V_VALOR_CAPITAL_CUOTA * @V_INTERES_CALCULADO
				SET @V_VALOR_INTERES_MORA = ROUND((@V_VALOR_CAPITAL_CUOTA * @V_INTERES_CALCULADO),0)

				IF @V_DIAS_DE_MORA IS NOT NULL AND @V_VALOR_INTERES_MORA IS NOT NULL
				BEGIN
					UPDATE PlanAmortizacionDef
					SET PlAmDeValorInteresMora = PlAmDeValorInteresMora + @V_VALOR_INTERES_MORA,
					PlAmDeDiasMora = PlAmDeDiasMora + @V_DIAS_DE_MORA
					WHERE ProyectosNumeroProyecto = @V_NUMERO_PROYECTO
					AND PlAmDeNumeroCuota = @V_NUMERO_CUOTA
				END
			END
						
			--Leer siguiente cuota a calcular interes
			FETCH NEXT FROM CurCuotasPendientes INTO 
			@V_NUMERO_PROYECTO, @V_NUMERO_CUOTA,
			@V_FECHA_VENCIMIENTO_CUOTA, @V_VALOR_CAPITAL_CUOTA
		END
		CLOSE CurCuotasPendientes 
		DEALLOCATE CurCuotasPendientes

		IF @V_EXISTE_CONFIGURACION = 1
		BEGIN
			UPDATE Configuracion 
			SET ConfiguracionValorTexto = CONVERT(VARCHAR, @V_FECHA_EJECUCION, 3) 
			WHERE ConfiguracionClave = 'FechaUltimaEjecucionCalculoMora';
		END
		ELSE
		BEGIN
			INSERT INTO Configuracion VALUES(
				'FechaUltimaEjecucionCalculoMora',
				NULL,
				CONVERT(VARCHAR, @V_FECHA_EJECUCION, 3))
		END
		
		SET @V_ERROR_MENSAJE = 'Proceso termino correctamente - Calculo de Valor Interes Mora'
		INSERT INTO LogProceso VALUES(
		GETDATE(), @P_TRANSACCION, 'Proceso', @V_ERROR_MENSAJE, '1',
		@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())	

		RETURN

		R_PROCESAR_ERROR:
			SET @V_ERROR_MENSAJE = @V_ERROR_MENSAJE + ' - Calculo de Valor Interes Mora'
			INSERT INTO LogProceso VALUES(
			GETDATE(), @P_TRANSACCION, 'Error', @V_ERROR_MENSAJE, '1',
			@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())			 
			RETURN
	END TRY

	BEGIN CATCH
		SET @V_ERROR_MENSAJE = 'Error SQL: ' + ERROR_MESSAGE() + 
				    			' - Linea: ' + CAST((ERROR_LINE()) AS VARCHAR(MAX)) +
								' - Transacciones: ' + CAST((@@TRANCOUNT) AS VARCHAR(MAX)) +
								' - Msj: ' + @V_ERROR_MENSAJE + ' - Calculo de Valor Interes Mora'

		 INSERT INTO LogProceso VALUES(
		 GETDATE(), @P_TRANSACCION, 'Catch', @V_ERROR_MENSAJE, '1',
		 @P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())
	END CATCH
END