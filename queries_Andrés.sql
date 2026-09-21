-- ============================================================
-- FOOD STORE - queries.sql (Consolidado - Bloque B)
-- Proyecto Integrador - Base de Datos II (PostgreSQL 16+)
-- ============================================================
-- Este script consolida la ejecución de consultas operativas (HUs),
-- agregaciones, subconsultas avanzadas, funciones de ventana y 
-- pruebas de equivalencia con EXCEPT.
-- Correr DESPUÉS de: schema.sql -> objects.sql -> data.sql / carga_masiva.sql
-- ============================================================


-- ============================================================
-- SECCIÓN 1: HISTORIAS DE USUARIO (OPERATIVO Y DDL/DML)
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 ÉPICA: GESTIÓN DE CATEGORÍAS
-- ------------------------------------------------------------

-- HU-CAT-01: Listar categorías vigentes (borrado lógico aplicado)
SELECT id, nombre, descripcion
FROM categoria
WHERE eliminado = FALSE
ORDER BY id;

-- HU-CAT-02: Crear categoría (Caso feliz - Evita duplicados en reejecuciones)
INSERT INTO categoria(nombre, descripcion)
SELECT 'Vegano', 'Opciones sin productos de origen animal'
WHERE NOT EXISTS (
    SELECT 1 FROM categoria WHERE nombre = 'Vegano'
);

-- HU-CAT-03: Editar categoría
UPDATE categoria
SET nombre = 'Pizzas Artesanales', descripcion = 'Pizzas a la piedra, catálogo ampliado'
WHERE id = 1 AND eliminado = FALSE;

-- HU-CAT-04: Eliminar categoría (Baja lógica)
UPDATE categoria
SET eliminado = TRUE
WHERE nombre = 'Vegano' AND eliminado = FALSE;

-- Verificación en vista
SELECT * FROM v_categorias_vigentes WHERE nombre = 'Vegano';


-- ------------------------------------------------------------
-- 1.2 ÉPICA: GESTIÓN DE PRODUCTOS
-- ------------------------------------------------------------

-- HU-PROD-01: Listar productos vigentes con su categoría (JOIN explicito)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
ORDER BY p.id;

-- HU-PROD-02: Crear producto validando categoría vigente (Evita duplicados)
INSERT INTO producto(nombre, descripcion, precio, stock, disponible, categoria_id)
SELECT 'Calzone', 'Pizza cerrada rellena', 4700.00, 8, TRUE, c.id
FROM categoria c
WHERE c.id = 1 AND c.eliminado = FALSE
  AND NOT EXISTS (SELECT 1 FROM producto WHERE nombre = 'Calzone');

-- HU-PROD-03: Editar producto (actualización condicional)
UPDATE producto
SET precio = COALESCE(3700.00, precio),
    stock  = COALESCE(NULL, stock)
WHERE id = 1 AND eliminado = FALSE;


-- ------------------------------------------------------------
-- 1.3 ÉPICA: GESTIÓN DE USUARIOS
-- ------------------------------------------------------------

-- HU-USR-01: Listar usuarios vigentes
SELECT id, nombre, apellido, mail, rol
FROM usuario
WHERE eliminado = FALSE
ORDER BY id;

-- HU-USR-02: Crear usuario (Evita duplicados en reejecuciones)
INSERT INTO usuario(nombre, apellido, mail, celular, contrasena)
SELECT 'Diego', 'Fernández', 'diego.fernandez@mail.com', '2616666666', 'hash_diego'
WHERE NOT EXISTS (
    SELECT 1 FROM usuario WHERE mail = 'diego.fernandez@mail.com'
);

-- HU-USR-03: Baja lógica de usuario
UPDATE usuario
SET eliminado = TRUE
WHERE id = 5 AND eliminado = FALSE;


-- ------------------------------------------------------------
-- 1.4 ÉPICA: GESTIÓN DE PEDIDOS Y TRANSACCIONES
-- ------------------------------------------------------------

-- HU-PED-01: Consultar resumen de pedidos desde vista
SELECT id, usuario, fecha, estado, forma_pago, total
FROM v_pedidos_resumen
ORDER BY id;

-- HU-PED-02: Crear pedido vía Procedimiento Almacenado PL/pgSQL
CALL sp_crear_pedido(
    3, -- Lucía
    'EFECTIVO',
    '[{"producto_id":1,"cantidad":1}, {"producto_id":10,"cantidad":2}]'::jsonb
);

-- HU-PED-03: Transacción manual de baja lógica de un pedido y sus detalles
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 6;
    UPDATE pedido SET eliminado = TRUE WHERE id = 6;
COMMIT;


-- ============================================================
-- SECCIÓN 2: CONSULTAS ANALÍTICAS AVANZADAS Y OPTIMIZACIÓN
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 AGREGACIÓN, GROUP BY Y JOINs (Top Productos y Facturación)
-- ------------------------------------------------------------

-- Top 5 productos más vendidos por cantidad de unidades
SELECT pr.id, pr.nombre, SUM(dp.cantidad) AS unidades
FROM detalle_pedido dp
JOIN producto pr ON pr.id = dp.producto_id
WHERE dp.eliminado = FALSE
GROUP BY pr.id, pr.nombre
ORDER BY unidades DESC
LIMIT 5;

-- Facturación mensual por categoría
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

-- Productos sin ventas (LEFT JOIN + IS NULL)
SELECT pr.id, pr.nombre
FROM producto pr
LEFT JOIN detalle_pedido dp ON dp.producto_id = pr.id AND dp.eliminado = FALSE
WHERE pr.eliminado = FALSE AND dp.id IS NULL
ORDER BY pr.id;


-- ------------------------------------------------------------
-- 2.2 RANKING DE USUARIOS POR GASTO (Funciones de Ventana / CTE / Subqueries)
-- ------------------------------------------------------------

-- Opción A: JOIN Directo con DENSE_RANK()
SELECT 
    u.nombre || ' ' || u.apellido AS nombre_completo,
    SUM(p.total) AS total_gastado,
    DENSE_RANK() OVER (ORDER BY SUM(p.total) DESC, u.id ASC) AS puesto
FROM usuario u
INNER JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE
WHERE u.eliminado = FALSE
GROUP BY u.id, u.nombre, u.apellido;

-- Opción B: CTE (Common Table Expression) con precalculado
WITH totales_usuarios AS (
    SELECT 
        u.id AS usuario_id,
        u.nombre || ' ' || u.apellido AS nombre_completo,
        SUM(p.total) AS total_gastado
    FROM usuario u
    INNER JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE
    WHERE u.eliminado = FALSE
    GROUP BY u.id, u.nombre, u.apellido
)
SELECT 
    nombre_completo,
    total_gastado,
    DENSE_RANK() OVER (ORDER BY total_gastado DESC, usuario_id ASC) AS puesto
FROM totales_usuarios;

-- Opción C: Subconsulta en FROM con HAVING
SELECT 
    u.nombre || ' ' || u.apellido AS nombre_completo,
    sub.total_gastado,
    DENSE_RANK() OVER (ORDER BY sub.total_gastado DESC, u.id ASC) AS puesto
FROM usuario u
INNER JOIN (
    SELECT p.usuario_id, SUM(p.total) AS total_gastado
    FROM pedido p
    WHERE p.eliminado = FALSE
    GROUP BY p.usuario_id
    HAVING COUNT(p.id) >= 1
) sub ON sub.usuario_id = u.id
WHERE u.eliminado = FALSE;

-- Verificación de equivalencia con EXCEPT (Opción A vs Opción B)
WITH totales_usuarios AS (
    SELECT u.id AS usuario_id, u.nombre || ' ' || u.apellido AS nombre_completo, SUM(p.total) AS total_gastado
    FROM usuario u INNER JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE WHERE u.eliminado = FALSE GROUP BY u.id, u.nombre, u.apellido
)
SELECT u.nombre || ' ' || u.apellido AS nombre_completo, SUM(p.total) AS total_gastado, DENSE_RANK() OVER (ORDER BY SUM(p.total) DESC, u.id ASC) AS puesto
FROM usuario u INNER JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE WHERE u.eliminado = FALSE GROUP BY u.id, u.nombre, u.apellido
EXCEPT
SELECT nombre_completo, total_gastado, DENSE_RANK() OVER (ORDER BY total_gastado DESC, usuario_id ASC) AS puesto FROM totales_usuarios;


-- ------------------------------------------------------------
-- 2.3 PRODUCTOS CON PRECIO MAYOR AL PROMEDIO DE SU CATEGORÍA
-- ------------------------------------------------------------

-- Opción A: Subconsulta correlacionada en WHERE
SELECT p.id, p.nombre, p.categoria_id, p.precio
FROM producto p
WHERE p.eliminado = FALSE
AND p.precio > (
    SELECT AVG(p2.precio)
    FROM producto p2
    WHERE p2.categoria_id = p.categoria_id
    AND p2.eliminado = FALSE
);

-- Opción B: JOIN con subconsulta agrupada por categoría
SELECT p.id, p.nombre, p.categoria_id, p.precio
FROM producto p
INNER JOIN (
    SELECT categoria_id, AVG(precio) AS avg_precio
    FROM producto
    WHERE eliminado = FALSE
    GROUP BY categoria_id
) sub ON sub.categoria_id = p.categoria_id
WHERE p.eliminado = FALSE
AND p.precio > sub.avg_precio;

-- Verificación de equivalencia con EXCEPT (Opción A vs Opción B)
SELECT p.id, p.nombre, p.categoria_id, p.precio
FROM producto p
WHERE p.eliminado = FALSE AND p.precio > (
    SELECT AVG(p2.precio) FROM producto p2 WHERE p2.categoria_id = p.categoria_id AND p2.eliminado = FALSE
)
EXCEPT
SELECT p.id, p.nombre, p.categoria_id, p.precio
FROM producto p
INNER JOIN (
    SELECT categoria_id, AVG(precio) AS avg_precio FROM producto WHERE eliminado = FALSE GROUP BY categoria_id
) sub ON sub.categoria_id = p.categoria_id
WHERE p.eliminado = FALSE AND p.precio > sub.avg_precio;