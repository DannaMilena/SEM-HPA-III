/* ============================================================
   04_menu_por_horario.sql
   sp_ObtenerMenu: devuelve el menu segun el momento del dia.

   Siempre se muestran:
     - Todas las bebidas
     - Los platillos con Disponibilidad = 'Siempre'
   Ademas se muestran los platillos de la disponibilidad pedida
   ('Desayuno', 'Almuerzo' o 'Cena').

   @Disponibilidad = NULL  -> devuelve TODO el menu (sin filtrar)
   @IncluirImagen  = 0     -> omite la columna Imagen (por si acaso);
                              por si la app carga las imagenes por separado)
   ============================================================ */
USE MenuInteractivo;
GO

CREATE OR ALTER PROCEDURE dbo.sp_ObtenerMenu
    @Disponibilidad NVARCHAR(20) = NULL,   -- 'Desayuno' | 'Almuerzo' | 'Cena' | NULL
    @IncluirImagen  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @Disponibilidad IS NOT NULL
       AND @Disponibilidad NOT IN (N'Desayuno', N'Almuerzo', N'Cena', N'Siempre')
        THROW 50006, N'Disponibilidad invalida. Use ''Desayuno'', ''Almuerzo'', ''Cena'' o NULL.', 1;

    SELECT  m.TipoProducto,
            m.ProductoID,
            m.Nombre,
            m.Disponibilidad,
            m.Categoria,
            m.Ingredientes,
            m.Calorias,
            m.Precio,
            m.Dietas,
            CASE WHEN @IncluirImagen = 1 THEN m.Imagen END AS Imagen
    FROM dbo.vw_Menu AS m
    WHERE  @Disponibilidad IS NULL
        OR m.TipoProducto = N'Bebida'              -- las bebidas siempre se ven
        OR m.Disponibilidad = N'Siempre'           -- los platillos "siempre" tambien
        OR m.Disponibilidad = @Disponibilidad      -- y los del horario elegido
    ORDER BY
        CASE m.TipoProducto WHEN N'Platillo' THEN 1 ELSE 2 END,       -- platillos primero
        CASE m.Categoria WHEN N'Entrada' THEN 1 WHEN N'Plato fuerte' THEN 2
                         WHEN N'Postre'  THEN 3 ELSE 4 END,
        m.Nombre;
END;
GO

/* ---------- Ejemplos ---------- */
-- EXEC dbo.sp_ObtenerMenu @Disponibilidad = N'Desayuno';
-- EXEC dbo.sp_ObtenerMenu @Disponibilidad = N'Almuerzo', @IncluirImagen = 0;
-- EXEC dbo.sp_ObtenerMenu @Disponibilidad = N'Cena';
-- EXEC dbo.sp_ObtenerMenu;      -- menu completo

-- Verificacion de conteos (esperado: 15 'Siempre' + 15 del horario + 12 bebidas = 42)
-- SELECT COUNT(*) FROM (EXEC ...) no es valido en T-SQL; usa:
-- EXEC dbo.sp_ObtenerMenu N'Desayuno', 0;   -- y revisa que devuelva 42 filas
GO
