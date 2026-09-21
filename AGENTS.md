# Food Store — Instrucciones para Agentes

## Stack Tecnológico

| Componente | Tecnología / Versión | Propósito |
|---|---|---|
| Motor BD | PostgreSQL 16+ | Base de datos relacional |
| Lenguaje | SQL / PL/pgSQL | Definición de esquema, vistas, funciones y procedimientos |

## Estructura de carpetas (consolidada — Entrega 1 del TPI)

Todos los archivos `.sql` del proyecto están dentro de
`Archivos necesarios para la BD/`:

```
Archivos necesarios para la BD/
├── schema.sql          (CONSOLIDADO: tipos, tablas, constraints, TODOS los índices)
├── objects.sql         (CONSOLIDADO: vistas, función, triggers, procedimiento, vista materializada)
├── data.sql             Datos de prueba chicos
├── queries.sql           Historias de usuario resueltas + consultas analíticas
├── transacciones.sql     Escenarios de atomicidad, aislamiento y bloqueo concurrente
└── carga_masiva.sql      Población masiva (≥50.000 productos, ≥20.000 usuarios, ≥200.000 pedidos)
```

**Importante:** `schema.sql` y `objects.sql` ya incluyen TODO lo que en
entregas anteriores estaba repartido en archivos sueltos
(`indices_semana3.sql`, `indices.sql`, `views.sql`, `materializadas.sql`).
Esos 4 archivos **ya no existen en el repo** — su contenido fue fusionado.
No recrearlos ni proponer un `CREATE INDEX`/`CREATE VIEW` que duplique algo
que ya está en `schema.sql` u `objects.sql` (ver listas completas más abajo).

## Orden de ejecución

```
schema.sql → objects.sql → data.sql → carga_masiva.sql (opcional) → queries.sql
```

Cada archivo depende del anterior. `transacciones.sql` es independiente —
corre sobre la base ya poblada, en cualquier momento después de `data.sql`.

## Base de Conocimiento y Steering

- `schema.sql`: Tipos ENUM, tablas, TODOS los constraints (incluye los 2 CHECK
  de mail y fecha) y TODOS los índices (los 3 originales + los 3 agregados en
  entregas posteriores).
- `objects.sql`: Las 5 vistas (incluida `v_usuario_seguro`), la vista
  materializada, la función de cálculo, los 4 triggers (incluido el de
  transición de estado) y `sp_crear_pedido`.
- `data.sql`: Datos de prueba chicos.
- `queries.sql`: Historias de usuario resueltas + consultas analíticas (JOIN,
  agregación, GROUP BY/HAVING, subconsultas, funciones de ventana).
- `transacciones.sql`: Escenarios de atomicidad, aislamiento y concurrencia.
- `carga_masiva.sql`: Población masiva, para medir performance con volumen real.
- `.kiro/steering/project-overview.md`: visión general y orden de ejecución.
- `.kiro/steering/conventions.md`: convenciones + índices y constraints existentes.
- `.kiro/steering/objects-and-patterns.md`: vistas, triggers, `sp_crear_pedido`, patrones.

## Índices existentes (NO recrear, ni duplicar)

- `idx_producto_categoria_id` — `producto(categoria_id)`
- `idx_pedido_usuario_id` — `pedido(usuario_id)`
- `idx_producto_nombre_vigente` — `producto(nombre) WHERE eliminado = FALSE` (parcial)
- `idx_pedido_fecha_estado_vigente` — `pedido(fecha, estado) WHERE eliminado = FALSE` (parcial)
- `idx_pedido_usuario_total_estado` — `pedido(usuario_id, total) WHERE eliminado = FALSE AND estado IN ('CONFIRMADO','TERMINADO')` (parcial)
- `idx_producto_nombre_lower_vigente` — `producto(lower(nombre) text_pattern_ops) WHERE eliminado = FALSE` (parcial)

**Pendiente de decisión del grupo** (no está creado, solo comentado en
`schema.sql`): `idx_producto_cat_disp_precio_cov` — índice covering sobre
`producto(categoria_id, disponible, precio DESC) INCLUDE (id, nombre, stock)`.
No proponerlo como si ya existiera; no volver a "descubrirlo" como si fuera
nuevo.

Antes de proponer un índice nuevo, verificar contra esta lista. Un índice que
duplica o es redundante con alguno de estos es candidato directo al descarte
por sobreindexación.

## Vistas y objetos existentes (NO recrear)

- `v_categorias_vigentes`, `v_productos_vigentes`, `v_pedidos_resumen`,
  `v_pedido_detalle` — vistas simples, todas filtran `eliminado = FALSE`.
- `v_usuario_seguro` — expone `usuario` sin la columna `contrasena`. Usar
  siempre esta vista quien necesite listar usuarios; nunca hacer
  `SELECT *` directo sobre `usuario` fuera de autenticación.
- `mv_facturacion_categoria_mes` — vista MATERIALIZADA de facturación por
  categoría y mes. No se actualiza sola: requiere
  `REFRESH MATERIALIZED VIEW CONCURRENTLY mv_facturacion_categoria_mes;`
  después de cambios relevantes en pedidos.

## Reglas Duras del Proyecto

1. **Nombres de tablas:** singular y español (`categoria`, `producto`, `usuario`, `pedido`, `detalle_pedido`).
2. **Borrado lógico:** nunca `DELETE`. Usar `UPDATE <tabla> SET eliminado = TRUE WHERE id = :id AND eliminado = FALSE`.
3. **Altas de pedidos:** siempre `CALL sp_crear_pedido(...)`.
4. **Triggers automáticos:** no modificar `trg_subtotal`, `trg_total_ins`, `trg_total_upd`, `trg_validar_estado_pedido`.
5. **Vistas vigentes:** usarlas para filtrar registros activos en vez de escribir el filtro a mano.
6. **JOINs y borrado lógico:** el filtro `eliminado = FALSE` debe aplicarse en cada tabla involucrada.
7. **Índices propuestos:** ninguno se aplica sin poder explicar qué nodo del
   plan ataca y por qué se espera que mejore — ni sin verificar primero que
   no duplique uno de los 6 ya existentes.
8. **Vistas de seguridad:** ninguna vista de usuario expuesta debe incluir la
   columna `contrasena` (usar `v_usuario_seguro`).
9. **Datos sensibles:** `usuario.mail` debe respetar el formato validado por
   `chk_usuario_mail_formato`; `pedido.fecha` nunca puede ser futura
   (`fecha <= CURRENT_DATE`).
