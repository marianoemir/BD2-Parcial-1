# Food Store — Visión General del Proyecto

## Descripción

Sistema de venta de comida implementado íntegramente en **PostgreSQL**.
Cubre el ciclo completo: categorías → productos → usuarios → pedidos con sus detalles.

## Archivos del proyecto (consolidado — Entrega 1 del TPI)

| Archivo | Contenido |
|---|---|
| `schema.sql` | Tipos ENUM, tablas, TODOS los constraints y TODOS los índices (consolidado, incluye lo agregado en entregas posteriores) |
| `objects.sql` | Todas las vistas (incluida `v_usuario_seguro`), la vista materializada, función de cálculo, triggers (incluido el de transición de estado) y `sp_crear_pedido` (consolidado) |
| `data.sql` | Datos de prueba chicos (categorías, productos, usuarios, pedidos de ejemplo) |
| `queries.sql` | Historias de usuario resueltas + consultas analíticas (JOIN, agregación, GROUP BY/HAVING, subconsultas, funciones de ventana) |
| `transacciones.sql` | Escenarios de atomicidad, aislamiento y bloqueo concurrente |
| `carga_masiva.sql` | Script de población masiva: ≥50.000 productos, ≥20.000 usuarios, ≥200.000 pedidos con detalles |

**Nota:** `indices_semana3.sql`, `indices.sql`, `views.sql` y
`materializadas.sql` existieron como archivos separados en entregas
anteriores. Su contenido ya está fusionado dentro de `schema.sql` y
`objects.sql` — no forman parte del repo actual.

## Tablas del modelo

```
categoria
producto       → FK categoria_id → categoria
usuario
pedido         → FK usuario_id   → usuario
detalle_pedido → FK pedido_id    → pedido
               → FK producto_id  → producto
```

## Tipos ENUM definidos

```sql
CREATE TYPE rol          AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO');
CREATE TYPE forma_pago   AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');
```

## Orden de ejecución

```
schema.sql → objects.sql → data.sql → carga_masiva.sql (opcional) → queries.sql
```

Cada archivo depende del anterior; ejecutarlos fuera de orden producirá
errores de referencia. `transacciones.sql` es independiente y corre sobre la
base ya poblada, en cualquier momento después de `data.sql`. `queries.sql` no
se ejecuta de una sola vez: es un banco de consultas sueltas.

## Vistas disponibles

| Vista | Descripción |
|---|---|
| `v_categorias_vigentes` | Categorías con `eliminado = FALSE` |
| `v_productos_vigentes` | Productos y categorías activos, con JOIN entre ambas tablas |
| `v_pedidos_resumen` | Pedidos vigentes con nombre completo del usuario |
| `v_pedido_detalle` | Líneas de detalle vigentes con nombre del producto |
| `v_usuario_seguro` | Usuarios sin la columna `contrasena` |

## Vista materializada

| Vista materializada | Descripción |
|---|---|
| `mv_facturacion_categoria_mes` | Facturación agregada por categoría y mes. Requiere `REFRESH MATERIALIZED VIEW CONCURRENTLY` para actualizarse — no se actualiza sola. Tiene índice único `(categoria_id, mes)` que habilita el refresh concurrente. |
