USE [GX_KB_VISION]
GO
/****** Object:  StoredProcedure [dbo].[SP_FamiliasCalcularAportes]    Script Date: 10/05/2022 10:42:52 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[SP_FamiliasCalcularAportes]
(@P_FAMILIAID INT = NULL,
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
		DECLARE @V_VALOR_APORTES_FORMALES INT = NULL
		DECLARE @V_VALOR_APORTES_INFORMALES INT = NULL
		DECLARE @V_VALOR_APORTES_ARRIENDO INT = NULL
		DECLARE @V_VALOR_APORTES_SUBSIDIOS INT = NULL
		DECLARE @V_VALOR_APORTES_PATERNIDAD INT = NULL
		DECLARE @V_VALOR_APORTES_TERCEROS INT = NULL
		DECLARE @V_VALOR_APORTES_OTROS INT = NULL

-----------------------------
--PROCESAR PLAN AMORTIZACION.
-----------------------------
		--Sumar aportes por todos los integrantes
		SET @V_VALOR_APORTES_FORMALES = (SELECT SUM([PersonasAportesFormales]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_INFORMALES = (SELECT SUM([PersonasAportesInformales]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_ARRIENDO = (SELECT SUM([PersonasAportesArriendo]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_SUBSIDIOS = (SELECT SUM([PersonasAportesSubsidios]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_PATERNIDAD = (SELECT SUM([PersonasAportesPaternidad]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_TERCEROS = (SELECT SUM([PersonasAportesTerceros]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)
		SET @V_VALOR_APORTES_OTROS = (SELECT SUM([PersonasAportesOtros]) FROM [dbo].[Personas] WHERE [PersonasFamiliaId] = @P_FAMILIAID)

		UPDATE [dbo].[Familias2] 
		SET [Familias2AportesFormales] = @V_VALOR_APORTES_FORMALES,
		[Familias2AportesInformales] = @V_VALOR_APORTES_INFORMALES,
		[Familias2AportesArriendo] = @V_VALOR_APORTES_ARRIENDO,
		[Familias2AportesSubsidios] = @V_VALOR_APORTES_SUBSIDIOS,
		[Familias2AportesPaternidad] = @V_VALOR_APORTES_PATERNIDAD,
		[Familias2AportesTerceros] = @V_VALOR_APORTES_TERCEROS,
		[Familias2AportesOtros] = @V_VALOR_APORTES_OTROS
		WHERE [Familias2IdenPersona] = @P_FAMILIAID

		SET @V_ERROR_MENSAJE = 'Proceso termino correctamente - Familia : ' + CAST((@P_FAMILIAID) AS VARCHAR(MAX))
		INSERT INTO [dbo].[LogProceso] VALUES(
		GETDATE(), @P_TRANSACCION, 'Proceso', @V_ERROR_MENSAJE, '1',
		@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())	

		RETURN

		R_PROCESAR_ERROR:
			SET @V_ERROR_MENSAJE = @V_ERROR_MENSAJE + ' - Familia : ' + CAST((@P_FAMILIAID) AS VARCHAR(MAX))
			INSERT INTO [dbo].[LogProceso] VALUES(
			GETDATE(), @P_TRANSACCION, 'Error', @V_ERROR_MENSAJE, '1',
			@P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())			 
			RETURN
	END TRY

	BEGIN CATCH
		 SET @V_ERROR_MENSAJE = 'Error SQL: ' + ERROR_MESSAGE() + 
				    			' - Linea: ' + CAST((ERROR_LINE()) AS VARCHAR(MAX)) +
								' - Transacciones: ' + CAST((@@TRANCOUNT) AS VARCHAR(MAX)) +
								' - Msj: ' + @V_ERROR_MENSAJE + ' - Familia : ' + CAST((@P_FAMILIAID) AS VARCHAR(MAX))

		 INSERT INTO [dbo].[LogProceso] VALUES(
		 GETDATE(), @P_TRANSACCION, 'Catch', @V_ERROR_MENSAJE, '1',
		 @P_USUARIO, GETDATE(), @P_USUARIO, GETDATE())
	END CATCH
END