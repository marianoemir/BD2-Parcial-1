-- ============================================================
-- FOOD STORE - queries.sql
-- Historias de usuario resueltas + consultas analíticas
-- Correr DESPUÉS de schema.sql + objects.sql + data.sql
-- ============================================================

-- ============================================================
-- ÉPICA 1 — GESTIÓN DE CATEGORÍAS
-- ============================================================

-- HU-CAT-01: Listar categorías vigentes
-- Criterio: solo eliminado = FALSE, no debe aparecer "Descontinuados"
SELECT id, nombre, descripcion
FROM categoria
WHERE eliminado = FALSE
ORDER BY id;

-- HU-CAT-02: Crear categoría (caso feliz)
INSERT INTO categoria(nombre, descripcion)
VALUES ('Vegano', 'Opciones sin productos de origen animal')
RETURNING id;

-- HU-CAT-02 (caso negativo): nombre duplicado -> debe fallar por UNIQUE
-- INSERT INTO categoria(nombre, descripcion) VALUES ('Pizzas', 'duplicado');
-- ERROR esperado: duplicate key value violates unique constraint

-- HU-CAT-03: Editar categoría
UPDATE categoria
SET nombre = 'Pizzas Artesanales', descripcion = 'Pizzas a la piedra, catálogo ampliado'
WHERE id = 1 AND eliminado = FALSE;

-- HU-CAT-03 (caso negativo): id inexistente -> 0 filas afectadas
UPDATE categoria
SET nombre = 'No existe'
WHERE id = 9999 AND eliminado = FALSE;

-- HU-CAT-04: Eliminar categoría (baja lógica)
-- (usamos la que acabamos de crear para no afectar categorías con productos)
UPDATE categoria
SET eliminado = TRUE
WHERE nombre = 'Vegano' AND eliminado = FALSE;

-- Verificación: ya no debe aparecer en v_categorias_vigentes
SELECT * FROM v_categorias_vigentes WHERE nombre = 'Vegano';


-- ============================================================
-- ÉPICA 2 — GESTIÓN DE PRODUCTOS
-- ============================================================

-- HU-PROD-01: Listar productos vigentes con su categoría
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
ORDER BY p.id;

-- HU-PROD-01 (filtro por categoría, ej: solo Pizzas = categoria_id 1)
SELECT p.id, p.nombre, p.precio, p.stock
FROM producto p
WHERE p.eliminado = FALSE AND p.categoria_id = 1
ORDER BY p.id;

-- HU-PROD-02: Crear producto (validando categoría vigente)
INSERT INTO producto(nombre, descripcion, precio, stock, disponible, categoria_id)
SELECT 'Calzone', 'Pizza cerrada rellena', 4700.00, 8, TRUE, c.id
FROM categoria c
WHERE c.id = 1 AND c.eliminado = FALSE
RETURNING id;

-- HU-PROD-03: Editar producto (precio y/o stock parcial)
UPDATE producto
SET precio = COALESCE(3700.00, precio),
    stock  = COALESCE(NULL, stock)  -- NULL conserva el stock actual
WHERE id = 1 AND eliminado = FALSE;

-- HU-PROD-04: Eliminar producto (baja lógica)
UPDATE producto
SET eliminado = TRUE
WHERE nombre = 'Producto temporalmente no disponible' AND eliminado = FALSE;


-- ============================================================
-- ÉPICA 3 — GESTIÓN DE USUARIOS
-- ============================================================

-- HU-USR-01: Listar usuarios vigentes
SELECT id, nombre, apellido, mail, rol
FROM usuario
WHERE eliminado = FALSE
ORDER BY id;

-- HU-USR-02: Crear usuario (caso feliz)
INSERT INTO usuario(nombre, apellido, mail, celular, contrasena)
VALUES ('Diego', 'Fernández', 'diego.fernandez@mail.com', '2616666666', 'hash_diego')
RETURNING id;

-- HU-USR-02 (caso negativo): mail duplicado -> debe fallar por UNIQUE
-- INSERT INTO usuario(nombre, apellido, mail, contrasena)
-- VALUES ('Otro', 'Usuario', 'ana.garcia@mail.com', 'hash');
-- ERROR esperado: duplicate key value violates unique constraint

-- HU-USR-03: Editar usuario
UPDATE usuario
SET celular = '2617777777'
WHERE id = 2 AND eliminado = FALSE;

-- HU-USR-04: Eliminar usuario (baja lógica)
UPDATE usuario
SET eliminado = TRUE
WHERE id = 5 AND eliminado = FALSE;

-- Verificación: el historial de pedidos de ese usuario se sigue viendo
SELECT * FROM v_pedidos_resumen WHERE usuario LIKE 'Sofía%';


-- ============================================================
-- ÉPICA 4 — GESTIÓN DE PEDIDOS Y DETALLES
-- ============================================================

-- HU-PED-01: Listar pedidos (con filtro opcional por usuario)
SELECT id, usuario, fecha, estado, forma_pago, total
FROM v_pedidos_resumen
ORDER BY id;

SELECT id, usuario, fecha, estado, forma_pago, total
FROM v_pedidos_resumen
WHERE usuario LIKE 'Ana%'
ORDER BY id;

-- HU-PED-02: Crear pedido con detalles (vía procedimiento transaccional)
CALL sp_crear_pedido(
    3, -- Lucía
    'EFECTIVO',
    '[{"producto_id":1,"cantidad":1},
      {"producto_id":10,"cantidad":2}]'::jsonb
);

-- Verificación: el total se calculó solo (no quedó en 0)
SELECT id, total FROM pedido ORDER BY id DESC LIMIT 1;

-- HU-PED-03: Actualizar estado / forma de pago
UPDATE pedido
SET estado = 'CONFIRMADO', forma_pago = 'TARJETA'
WHERE id = 3 AND eliminado = FALSE;

-- HU-PED-04: Eliminar pedido (baja lógica, en transacción)
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 6;
    UPDATE pedido SET eliminado = TRUE WHERE id = 6;
COMMIT;


-- ============================================================
-- CONSULTAS ANALÍTICAS
-- ============================================================

-- A) Top 5 productos más vendidos (por cantidad)
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
WHERE dp.eliminado = FALSE
GROUP BY pr.id, pr.nombre
ORDER BY unidades DESC
LIMIT 5;

-- B) Facturación por categoría y por mes
SELECT c.nombre AS categoria,
       date_trunc('month', ped.fecha) AS mes,
       SUM(dp.subtotal) AS facturado
FROM detalle_pedido dp
JOIN pedido ped ON ped.id = dp.pedido_id AND ped.eliminado = FALSE
JOIN producto pr ON pr.id = dp.producto_id
JOIN categoria c ON c.id = pr.categoria_id
WHERE dp.eliminado = FALSE
GROUP BY c.nombre, date_trunc('month', ped.fecha)
ORDER BY mes, facturado DESC;

-- C) Ranking de usuarios por gasto acumulado (función de ventana)
SELECT u.id, u.nombre || ' ' || u.apellido AS usuario,
       SUM(ped.total) AS gasto,
       RANK() OVER (ORDER BY SUM(ped.total) DESC) AS puesto
FROM pedido ped
JOIN usuario u ON u.id = ped.usuario_id
WHERE ped.eliminado = FALSE
GROUP BY u.id, u.nombre, u.apellido
ORDER BY puesto;

-- D) Pedidos cuyo total supera el promedio general (subconsulta)
SELECT id, total
FROM pedido
WHERE eliminado = FALSE
  AND total > (SELECT AVG(total) FROM pedido WHERE eliminado = FALSE)
ORDER BY total DESC;

-- E) Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id, pr.nombre
FROM producto pr
LEFT JOIN detalle_pedido dp
       ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE
  AND dp.id IS NULL
ORDER BY pr.id;
