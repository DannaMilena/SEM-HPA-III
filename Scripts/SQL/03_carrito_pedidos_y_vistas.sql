/* ============================================================
   03_carrito_pedidos_y_vistas.sql
   Procedimientos del carrito, generacion de pedido y vistas.
   ============================================================ */
USE MenuInteractivo;
GO

/* ---------- Vista: menu unificado (platillos + bebidas) con dietas ---------- */
CREATE OR ALTER VIEW dbo.vw_Menu
AS
SELECT  N'Platillo' AS TipoProducto, p.PlatilloID AS ProductoID, p.Nombre,
        p.Disponibilidad, p.Tipo AS Categoria, p.Ingredientes, p.Calorias, p.Precio, p.Imagen,
        (SELECT STRING_AGG(d.Nombre, N', ') FROM dbo.PlatilloDieta pd
           JOIN dbo.Dietas d ON d.DietaID = pd.DietaID WHERE pd.PlatilloID = p.PlatilloID) AS Dietas
FROM dbo.Platillos p
UNION ALL
SELECT  N'Bebida', b.BebidaID, b.Nombre,
        N'Siempre', b.Tipo, b.Ingredientes, b.Calorias, b.Precio, b.Imagen,
        (SELECT STRING_AGG(d.Nombre, N', ') FROM dbo.BebidaDieta bd
           JOIN dbo.Dietas d ON d.DietaID = bd.DietaID WHERE bd.BebidaID = b.BebidaID)
FROM dbo.Bebidas b;
GO

/* ---------- Vista: carrito con total ---------- */
CREATE OR ALTER VIEW dbo.vw_Carrito
AS
SELECT ItemCarritoID, TipoProducto, ProductoID, NombreProducto, Unidades, PrecioUnitario, Subtotal
FROM dbo.Carrito;
GO

/* ---------- Agregar al carrito ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_AgregarAlCarrito
    @TipoProducto NVARCHAR(10),   -- 'Platillo' o 'Bebida'
    @ProductoID   INT,
    @Unidades     INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Unidades IS NULL OR @Unidades <= 0
        THROW 50001, N'Las unidades deben ser mayores que cero.', 1;

    DECLARE @Nombre NVARCHAR(100), @Precio DECIMAL(8,2);

    IF @TipoProducto = N'Platillo'
        SELECT @Nombre = Nombre, @Precio = Precio FROM dbo.Platillos WHERE PlatilloID = @ProductoID;
    ELSE IF @TipoProducto = N'Bebida'
        SELECT @Nombre = Nombre, @Precio = Precio FROM dbo.Bebidas WHERE BebidaID = @ProductoID;
    ELSE
        THROW 50002, N'TipoProducto invalido. Use ''Platillo'' o ''Bebida''.', 1;

    IF @Nombre IS NULL
        THROW 50003, N'El producto indicado no existe.', 1;

    BEGIN TRAN;
        -- Si el producto ya esta en el carrito, se suman las unidades
        UPDATE dbo.Carrito WITH (UPDLOCK, HOLDLOCK)
           SET Unidades = Unidades + @Unidades
         WHERE TipoProducto = @TipoProducto AND ProductoID = @ProductoID;

        IF @@ROWCOUNT = 0
            INSERT dbo.Carrito (TipoProducto, ProductoID, NombreProducto, Unidades, PrecioUnitario)
            VALUES (@TipoProducto, @ProductoID, @Nombre, @Unidades, @Precio);
    COMMIT;
END;
GO

/* ---------- Cambiar unidades (0 o menos = quitar) ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_ActualizarUnidadesCarrito
    @ItemCarritoID INT,
    @Unidades      INT
AS
BEGIN
    SET NOCOUNT ON;
    IF NOT EXISTS (SELECT 1 FROM dbo.Carrito WHERE ItemCarritoID = @ItemCarritoID)
        THROW 50004, N'El item no existe en el carrito.', 1;

    IF @Unidades <= 0
        DELETE dbo.Carrito WHERE ItemCarritoID = @ItemCarritoID;
    ELSE
        UPDATE dbo.Carrito SET Unidades = @Unidades WHERE ItemCarritoID = @ItemCarritoID;
END;
GO

/* ---------- Quitar un item ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_QuitarDelCarrito
    @ItemCarritoID INT
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dbo.Carrito WHERE ItemCarritoID = @ItemCarritoID;
END;
GO

/* ---------- Vaciar carrito ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_VaciarCarrito
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dbo.Carrito;
END;
GO

/* ---------- Ver carrito + total ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_VerCarrito
AS
BEGIN
    SET NOCOUNT ON;
    SELECT * FROM dbo.Carrito ORDER BY ItemCarritoID;
    SELECT ISNULL(SUM(Subtotal), 0) AS TotalCarrito FROM dbo.Carrito;
END;
GO

/* ---------- Generar pedido ----------
   - Crea un registro en Pedidos con un ID nuevo (IDENTITY)
   - DetallePedido = factura en texto con todo el contenido del carrito
   - PrecioTotal   = suma de los subtotales
   - Vacia el carrito. Todo en una sola transaccion.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GenerarPedido
    @PedidoID INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NL NVARCHAR(2) = NCHAR(13) + NCHAR(10);
    DECLARE @Linea NVARCHAR(50) = REPLICATE(N'-', 50);
    DECLARE @Fecha DATETIME2(0) = SYSDATETIME();
    DECLARE @Total DECIMAL(10,2), @Items INT, @Detalle NVARCHAR(MAX);

    BEGIN TRAN;

        SELECT @Total = ISNULL(SUM(Subtotal), 0), @Items = COUNT(*)
        FROM dbo.Carrito WITH (UPDLOCK, HOLDLOCK);

        IF @Items = 0
            THROW 50005, N'El carrito esta vacio: no hay nada que facturar.', 1;

        -- 1) Se inserta primero para obtener el ID nuevo
        INSERT dbo.Pedidos (DetallePedido, PrecioTotal, FechaPedido)
        VALUES (N'', @Total, @Fecha);
        SET @PedidoID = SCOPE_IDENTITY();

        -- 2) Se arma la factura (ya con el numero de pedido)
        SELECT @Detalle = STRING_AGG(
                   CAST(CONCAT(Unidades, N' x ', NombreProducto, N' (', TipoProducto, N')',
                               N'  $', CAST(PrecioUnitario AS NVARCHAR(20)),
                               N' c/u = $', CAST(Subtotal AS NVARCHAR(20))) AS NVARCHAR(MAX)),
                   @NL) WITHIN GROUP (ORDER BY ItemCarritoID)
        FROM dbo.Carrito;

        SET @Detalle = CONCAT(
              N'FACTURA - PEDIDO No. ', @PedidoID, @NL,
              N'Fecha: ', CONVERT(NVARCHAR(19), @Fecha, 120), @NL,
              @Linea, @NL,
              @Detalle, @NL,
              @Linea, @NL,
              N'TOTAL A PAGAR: $', CAST(@Total AS NVARCHAR(20)));

        UPDATE dbo.Pedidos SET DetallePedido = @Detalle WHERE PedidoID = @PedidoID;

        -- 3) Se limpia el carrito
        DELETE dbo.Carrito;

    COMMIT;

    SELECT PedidoID, DetallePedido, PrecioTotal, FechaPedido
    FROM dbo.Pedidos WHERE PedidoID = @PedidoID;
END;
GO

/* ---------- Consultar pedido ---------- */
CREATE OR ALTER PROCEDURE dbo.sp_ObtenerPedido
    @PedidoID INT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT PedidoID, FechaPedido, PrecioTotal, DetallePedido FROM dbo.Pedidos WHERE PedidoID = @PedidoID;
END;
GO
