# Food Store — Objetos del Esquema y Patrones de Consulta

## Triggers — NO MODIFICAR

Los siguientes triggers están definidos y funcionan de forma automática.
**No hay que tocarlos, reescribirlos ni reemplazarlos.**

| Trigger | Tabla | Evento | Función | Qué hace |
|---|---|---|---|---|
| `trg_subtotal` | `detalle_pedido` | `BEFORE INSERT OR UPDATE` (fila) | `fn_set_subtotal()` | Copia `precio` de `producto` a `precio_unitario` si llega `NULL`; calcula `subtotal = cantidad × precio_unitario` |
| `trg_total_ins` | `detalle_pedido` | `AFTER INSERT` (sentencia) | `fn_recalcular_total()` | Recalcula `pedido.total` sumando los `subtotal` vigentes del pedido |
| `trg_total_upd` | `detalle_pedido` | `AFTER UPDATE` (sentencia) | `fn_recalcular_total()` | Ídem para actualizaciones sobre `detalle_pedido` |
| `trg_validar_estado_pedido` | `pedido` | `BEFORE UPDATE OF estado` (fila) | `fn_validar_estado_pedido()` | Bloquea la transición `CONFIRMADO → PENDIENTE`, lanzando excepción |

### Consecuencias prácticas

- Al insertar en `detalle_pedido` solo es obligatorio proveer `pedido_id`, `producto_id` y `cantidad`. El trigger completa `precio_unitario` y `subtotal`.
- El campo `pedido.total` se actualiza solo. Nunca hay que calcularlo ni actualizarlo a mano.
- La función auxiliar `calcular_total_pedido(p_pedido_id BIGINT)` puede usarse en consultas ad-hoc para obtener el total calculado sin pasar por el trigger.
- Un `UPDATE pedido SET estado = 'PENDIENTE' WHERE ...` sobre un pedido `CONFIRMADO` va a fallar por diseño — no es un bug, es la regla de negocio del TP2.

## Procedimiento `sp_crear_pedido` — usar siempre para altas de pedidos

```sql
CALL sp_crear_pedido(
    p_usuario_id BIGINT,
    p_forma_pago forma_pago,
    p_items      JSONB   -- [{"producto_id": N, "cantidad": N}, ...]
);
```

**Nunca hacer `INSERT INTO pedido` + `INSERT INTO detalle_pedido` manualmente.**
El procedimiento garantiza:

1. Que el usuario existe y no está eliminado.
2. Que cada producto existe, no está eliminado y tiene `disponible = TRUE`.
3. Que hay stock suficiente (`stock >= cantidad`).
4. Que el stock se descuenta dentro de la misma transacción.
5. Bloqueo con `FOR UPDATE` sobre la fila del producto para evitar sobreventa concurrente.
6. Rollback automático si cualquier ítem falla.

### Errores que lanza el procedimiento

| Condición | Mensaje |
|---|---|
| Usuario inexistente o eliminado | `'Usuario % inexistente o eliminado'` |
| Producto inexistente o eliminado | `'Producto % inexistente o eliminado'` |
| Producto no disponible | `'Producto % no disponible'` |
| Stock insuficiente | `'Stock insuficiente (producto %): hay %, se piden %'` |

## Vistas — usar en vez de reescribir el filtro a mano

| Vista | Para qué sirve |
|---|---|
| `v_categorias_vigentes` | Categorías con `eliminado = FALSE` |
| `v_productos_vigentes` | Productos + categoría, ambos vigentes |
| `v_pedidos_resumen` | Pedidos vigentes + nombre completo del usuario |
| `v_pedido_detalle` | Líneas de detalle vigentes + nombre del producto |
| `v_usuario_seguro` | Usuarios **sin** la columna `contrasena` — usar siempre esta vista para listar/exponer usuarios, nunca `SELECT * FROM usuario` fuera de la lógica de autenticación |

## Vista materializada `mv_facturacion_categoria_mes`

Facturación agregada por categoría y mes (solo pedidos `CONFIRMADO` y
vigentes). **No se actualiza sola** — hay que refrescarla explícitamente:

```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;
```

El `CONCURRENTLY` funciona porque existe el índice único
`idx_mv_facturacion_cat_mes_pk` sobre `(categoria_id, mes)` — no borrarlo.

## Patrones de consulta recomendados

### Listado de registros vigentes

Preferir las vistas cuando cubran el caso:

```sql
-- Bien
SELECT * FROM v_productos_vigentes WHERE categoria = 'Pizzas';

-- Solo si la vista no alcanza
SELECT p.id, p.nombre, p.precio
FROM producto p
WHERE p.eliminado = FALSE AND p.categoria_id = 1;
```

### Actualización parcial de campos (COALESCE)

Cuando se edita un registro y algunos campos son opcionales, usar `COALESCE` para preservar el valor existente si el nuevo es `NULL`:

```sql
UPDATE producto
SET precio = COALESCE(:nuevo_precio, precio),
    stock  = COALESCE(:nuevo_stock, stock)
WHERE id = :id AND eliminado = FALSE;
```

### Alta validando FK vigente

Al insertar un producto, verificar que la categoría no esté eliminada:

```sql
INSERT INTO producto(nombre, descripcion, precio, stock, disponible, categoria_id)
SELECT :nombre, :desc, :precio, :stock, TRUE, c.id
FROM categoria c
WHERE c.id = :categoria_id AND c.eliminado = FALSE
RETURNING id;
```

Si la categoría está eliminada, el `SELECT` devuelve 0 filas y el `INSERT` no se ejecuta.

### Consultas analíticas — buenas prácticas

- Siempre filtrar `eliminado = FALSE` en todas las tablas participantes.
- Para rankings usar funciones de ventana (`RANK() OVER`, `DENSE_RANK() OVER`).
- Para totales agregados usar `SUM` con `COALESCE(..., 0)` para evitar `NULL` cuando no hay filas.
- Para productos sin ventas usar `LEFT JOIN … WHERE fk IS NULL` en lugar de `NOT IN` (más eficiente y seguro con NULLs).
- Para búsquedas de texto por nombre, usar `lower(nombre) LIKE lower(:patron) || '%'` para aprovechar `idx_producto_nombre_lower_vigente`.

## Gestión de concurrencia y transacciones

- El bloqueo `FOR UPDATE` sobre `producto` ya está encapsulado en `sp_crear_pedido`. No replicarlo fuera del procedimiento salvo necesidad justificada.
- Para escenarios de aislamiento fuerte usar `SET TRANSACTION ISOLATION LEVEL SERIALIZABLE` antes del `BEGIN`.
- Las transacciones manuales (`BEGIN … COMMIT/ROLLBACK`) son necesarias solo para operaciones multi-tabla fuera del procedimiento (por ejemplo, baja lógica de un pedido completo, o el refresh de la vista materializada si se quiere encadenar con otra operación).
