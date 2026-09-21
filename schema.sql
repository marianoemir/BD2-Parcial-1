-- ============================================================
-- FOOD STORE - schema.sql (CONSOLIDADO — Entrega 1 del TPI)
-- Tipos, tablas, restricciones e índices
--
-- Este archivo fusiona:
--   - schema.sql original (TP1)
--   - los 2 CHECK agregados en el TP2 (mail, fecha)
--   - los 3 índices agregados en TP3/TP4 (indices_semana3.sql) y TP5 (indices.sql)
-- ============================================================

-- Tipos enumerados
CREATE TYPE rol AS ENUM ('ADMIN','USUARIO');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE','CONFIRMADO','TERMINADO','CANCELADO');
CREATE TYPE forma_pago AS ENUM ('TARJETA','TRANSFERENCIA','EFECTIVO');

-- ============================================================
-- CATEGORIA
-- ============================================================
CREATE TABLE categoria (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, -- corregido: BIGGINT -> BIGINT
    nombre       VARCHAR(80) NOT NULL UNIQUE,
    descripcion  VARCHAR(255),
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- PRODUCTO
-- ============================================================
CREATE TABLE producto (
    id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre        VARCHAR(120) NOT NULL,
    precio        NUMERIC(10,2) NOT NULL CHECK (precio >= 0),
    descripcion   VARCHAR(255),
    stock         INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
    imagen        VARCHAR(255),
    disponible    BOOLEAN NOT NULL DEFAULT TRUE,
    categoria_id  BIGINT NOT NULL REFERENCES categoria(id),
    eliminado     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- USUARIO
-- ============================================================
CREATE TABLE usuario (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR(80) NOT NULL,
    apellido     VARCHAR(80) NOT NULL,
    mail         VARCHAR(120) NOT NULL UNIQUE,
    celular      VARCHAR(30),
    contrasena   VARCHAR(255) NOT NULL,
    rol          rol NOT NULL DEFAULT 'USUARIO',
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Agregado en TP2 (Semana 2 — Concurrencia e IA)
    CONSTRAINT chk_usuario_mail_formato CHECK (
        mail ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    )
);

-- ============================================================
-- PEDIDO
-- ============================================================
CREATE TABLE pedido (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- CHECK fecha <= CURRENT_DATE agregado en TP2
    fecha        DATE NOT NULL DEFAULT CURRENT_DATE CHECK (fecha <= CURRENT_DATE),
    estado       estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total        NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    forma_pago   forma_pago NOT NULL,
    usuario_id   BIGINT NOT NULL REFERENCES usuario(id),
    eliminado    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- DETALLE_PEDIDO
-- ============================================================
CREATE TABLE detalle_pedido (
    id               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cantidad         INTEGER NOT NULL CHECK (cantidad > 0),
    precio_unitario  NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    subtotal         NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    pedido_id        BIGINT NOT NULL REFERENCES pedido(id) ON DELETE RESTRICT,
    producto_id      BIGINT NOT NULL REFERENCES producto(id),
    eliminado        BOOLEAN NOT NULL DEFAULT FALSE,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (pedido_id, producto_id)
);

-- ============================================================
-- ÍNDICES — originales (TP1)
-- ============================================================

-- Soporta el listado de productos por categoría
CREATE INDEX idx_producto_categoria_id ON producto(categoria_id);

-- Soporta el historial de pedidos por usuario
CREATE INDEX idx_pedido_usuario_id ON pedido(usuario_id);

-- Índice parcial: solo productos no eliminados, para búsquedas por nombre
CREATE INDEX idx_producto_nombre_vigente ON producto(nombre) WHERE eliminado = FALSE;

-- ============================================================
-- ÍNDICES — agregados en TP3 (medidos y aceptados en indices_semana3.sql)
-- ============================================================

-- Historial de pedidos por rango de fechas y estado.
-- Medido: Seq Scan -> Bitmap Heap Scan, ~2.1x más rápido (27.9ms -> 13.3ms)
CREATE INDEX idx_pedido_fecha_estado_vigente
ON pedido(fecha, estado)
WHERE eliminado = FALSE;

-- Ranking / agregación de gasto por usuario.
-- Medido: Seq Scan -> Index Only Scan (Heap Fetches: 0), ~1.7x más rápido (88.9ms -> 52.3ms)
CREATE INDEX idx_pedido_usuario_total_estado
ON pedido(usuario_id, total)
WHERE eliminado = FALSE AND estado IN ('CONFIRMADO', 'TERMINADO');

-- Nota: idx_producto_categoria_precio_vigente (evaluado en el TP3) se descartó
-- a propósito — el optimizador lo ignoró y no dio mejora medible.

-- ============================================================
-- ÍNDICES — agregados en TP5 / Unidad 3 (indices.sql)
-- ============================================================

-- Búsqueda de productos por nombre, case-insensitive (LIKE 'prefijo%').
-- Requiere text_pattern_ops para que el índice soporte ese operador.
-- Medido: ~226x más rápido (50.2ms -> 0.22ms), Seq Scan -> Bitmap Heap Scan
CREATE INDEX idx_producto_nombre_lower_vigente
ON producto (lower(nombre) text_pattern_ops)
WHERE eliminado = FALSE;

-- PENDIENTE DE DECISIÓN DEL GRUPO:
-- idx_producto_cat_disp_precio_cov (índice covering ganador de la
-- "competencia" del TP3) no está incluido acá todavía. Si lo van a usar en
-- alguna consulta del informe final, sumarlo con:
-- CREATE INDEX idx_producto_cat_disp_precio_cov
-- ON producto (categoria_id, disponible, precio DESC)
-- INCLUDE (id, nombre, stock);

-- Actualizar estadísticas después de crear los índices nuevos
ANALYZE producto;
ANALYZE pedido;
