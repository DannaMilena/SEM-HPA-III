/* ============================================================
   02_cargar_imagenes.sql
   Carga el CONTENIDO de cada PNG en las columnas
   Platillos.Imagen, Bebidas.Imagen y Dietas.Icono (VARBINARY(MAX)).
   ============================================================ */
USE MenuInteractivo;
GO
SET NOCOUNT ON;

DECLARE @Ruta NVARCHAR(400) = N'C:\Users\danna\Documents\GitHub\SEM-HPA-III\imagenes';   -- <-- AJUSTAR
IF RIGHT(@Ruta, 1) <> N'\' SET @Ruta += N'\';

-- Lista de trabajo: tabla, columna de ID, columna destino, id y archivo
CREATE TABLE #Cargar (
    N INT IDENTITY(1,1) PRIMARY KEY,
    Tabla SYSNAME, ColId SYSNAME, ColImg SYSNAME, Id INT, Archivo NVARCHAR(200)
);

INSERT #Cargar (Tabla, ColId, ColImg, Id, Archivo)
SELECT N'Platillos', N'PlatilloID', N'Imagen', PlatilloID, ImagenNombre FROM dbo.Platillos WHERE ImagenNombre IS NOT NULL
UNION ALL
SELECT N'Bebidas',   N'BebidaID',   N'Imagen', BebidaID,   ImagenNombre FROM dbo.Bebidas   WHERE ImagenNombre IS NOT NULL
UNION ALL
SELECT N'Dietas',    N'DietaID',    N'Icono',  DietaID,    IconoNombre  FROM dbo.Dietas    WHERE IconoNombre  IS NOT NULL;

DECLARE @i INT = 1, @max INT = (SELECT MAX(N) FROM #Cargar);
DECLARE @Tabla SYSNAME, @ColId SYSNAME, @ColImg SYSNAME, @Id INT, @Archivo NVARCHAR(200), @sql NVARCHAR(MAX);
DECLARE @ok INT = 0, @fallos INT = 0;

WHILE @i <= @max
BEGIN
    SELECT @Tabla = Tabla, @ColId = ColId, @ColImg = ColImg, @Id = Id, @Archivo = Archivo
    FROM #Cargar WHERE N = @i;

    -- OPENROWSET(BULK ...) exige la ruta como literal, por eso se usa SQL dinamico
    SET @sql = N'UPDATE dbo.' + QUOTENAME(@Tabla) +
               N' SET ' + QUOTENAME(@ColImg) +
               N' = (SELECT BulkColumn FROM OPENROWSET(BULK N''' + REPLACE(@Ruta + @Archivo, N'''', N'''''') + N''', SINGLE_BLOB) AS x)' +
               N' WHERE ' + QUOTENAME(@ColId) + N' = ' + CAST(@Id AS NVARCHAR(10)) + N';';
    BEGIN TRY
        EXEC sys.sp_executesql @sql;
        SET @ok += 1;
    END TRY
    BEGIN CATCH
        SET @fallos += 1;
        PRINT CONCAT(N'No se pudo cargar ', @Tabla, N' #', @Id, N' (', @Archivo, N'): ', ERROR_MESSAGE());
    END CATCH;
    SET @i += 1;
END;

DROP TABLE #Cargar;
PRINT CONCAT(N'Imagenes cargadas: ', @ok, N' | con error: ', @fallos);

-- Verificacion
SELECT N'Platillos' AS Tabla, COUNT(*) AS Total, SUM(CASE WHEN Imagen IS NOT NULL THEN 1 ELSE 0 END) AS ConImagen FROM dbo.Platillos
UNION ALL SELECT N'Bebidas', COUNT(*), SUM(CASE WHEN Imagen IS NOT NULL THEN 1 ELSE 0 END) FROM dbo.Bebidas
UNION ALL SELECT N'Dietas',  COUNT(*), SUM(CASE WHEN Icono  IS NOT NULL THEN 1 ELSE 0 END) FROM dbo.Dietas;
GO
