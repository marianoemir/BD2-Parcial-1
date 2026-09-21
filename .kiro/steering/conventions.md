# Food Store — Convenciones de Base de Datos

## Nombres de tablas

Los nombres de tabla son **en singular y en español**:

```
categoria, producto, usuario, pedido, detalle_pedido
```

No usar plural (`productos`), no usar inglés (`product`), no usar PascalCase.

## Columna `eliminado` — Borrado lógico

**Nunca se ejecuta `DELETE`** sobre ninguna tabla del proyecto.

Todas las tablas tienen `eliminado BOOLEAN NOT NULL DEFAULT FALSE`.
La baja de un registro consiste siempre en:

```sql
UPDATE <tabla> SET eliminado = TRUE WHERE id = :id AND eliminado = FALSE;
```

Toda consulta de datos vigentes debe filtrar `WHERE eliminado = FALSE`.
Las vistas `v_categorias_vigentes`, `v_productos_vigentes`,
`v_pedidos_resumen`, `v_pedido_detalle` y `v_usuario_seguro` ya aplican (o no
necesitan) ese filtro; úsalas en lugar de escribir el filtro a mano cuando
sea posible.

**En consultas con varios JOIN, el filtro debe aplicarse en CADA tabla
involucrada**, no solo en la principal. Omitirlo en una sola tabla del JOIN
puede hacer que dos consultas "parezcan" equivalentes sin serlo (por ejemplo,
sumar pedidos de un usuario ya eliminado, o incluir productos de una
categoría dada de baja).

### Baja de un pedido completo

La baja de un pedido requiere una transacción explícita que marque primero
los detalles y luego el pedido:

```sql
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = :id;
    UPDATE pedido SET eliminado = TRUE WHERE id = :id;
COMMIT;
```

## Columna `precio_unitario` en `detalle_pedido`

Este campo **congela el precio** del producto en el momento de la venta.
No se actualiza si el precio del producto cambia después.
El trigger `trg_subtotal` lo copia de `producto.precio` si llega `NULL`.

## Columna `disponible` en `producto`

Controla si el producto puede ser pedido. El procedimiento `sp_crear_pedido`
rechaza productos con `disponible = FALSE` aunque tengan stock.

## Estado de un pedido — transición controlada

`pedido.estado` es un ENUM (`PENDIENTE`, `CONFIRMADO`, `TERMINADO`,
`CANCELADO`). El trigger `trg_validar_estado_pedido` **impide** que un
pedido pase de `CONFIRMADO` de vuelta a `PENDIENTE` — cualquier `UPDATE` que
intente ese cambio lanza una excepción. No hay que validar esto a mano en
las consultas; el trigger ya lo garantiza.

## Restricciones de integridad destacadas

- `categoria.nombre` → `UNIQUE`
- `usuario.mail` → `UNIQUE` + `CHECK` de formato (`chk_usuario_mail_formato`,
  regex `^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$`)
- `pedido.fecha` → `CHECK (fecha <= CURRENT_DATE)` — no admite fechas futuras
- `detalle_pedido(pedido_id, producto_id)` → `UNIQUE` (un producto no puede repetirse en el mismo pedido)
- `producto.precio >= 0`, `producto.stock >= 0`, `detalle_pedido.cantidad > 0`
- `detalle_pedido.pedido_id` tiene `ON DELETE RESTRICT` (no se puede borrar un pedido con detalles via DELETE — consistente con la política de borrado lógico)

## Tipos de datos a respetar

| Campo | Tipo |
|---|---|
| IDs | `BIGINT GENERATED ALWAYS AS IDENTITY` |
| Precios y totales | `NUMERIC(10,2)` / `NUMERIC(12,2)` |
| Fechas con zona | `TIMESTAMPTZ` (campo `created_at`) |
| Fecha del pedido | `DATE` (campo `fecha`) |
| Contraseña | `VARCHAR(255)` — almacenar solo hash, nunca texto plano |

## Índices existentes (consolidados en `schema.sql`)

```sql
-- Originales
idx_producto_categoria_id   -- producto.categoria_id
idx_pedido_usuario_id       -- pedido.usuario_id
idx_producto_nombre_vigente -- producto(nombre) WHERE eliminado = FALSE  (parcial)

-- Agregados y medidos en entregas posteriores
idx_pedido_fecha_estado_vigente
    -- pedido(fecha, estado) WHERE eliminado = FALSE
    -- Acelera filtros por rango de fechas + estado (Seq Scan -> Bitmap Heap Scan, ~2.1x)

idx_pedido_usuario_total_estado
    -- pedido(usuario_id, total) WHERE eliminado = FALSE AND estado IN ('CONFIRMADO', 'TERMINADO')
    -- Habilita Index Only Scan para agregaciones de gasto por usuario (~1.7x)

idx_producto_nombre_lower_vigente
    -- producto(lower(nombre) text_pattern_ops) WHERE eliminado = FALSE
    -- Búsqueda de productos por nombre, case-insensitive (~226x)
```

**Pendiente de decisión del grupo** (comentado en `schema.sql`, no creado):
`idx_producto_cat_disp_precio_cov` — covering index sobre
`producto(categoria_id, disponible, precio DESC) INCLUDE (id, nombre, stock)`.

**No duplicar ninguno de estos índices** al proponer optimizaciones nuevas —
antes de sugerir un `CREATE INDEX`, verificar si alguno de los 6 ya cubre el
caso.
