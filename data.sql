-- ============================================================
-- FOOD STORE - data.sql
-- Datos de ejemplo. Correr DESPUÉS de schema.sql y objects.sql
-- ============================================================

-- ============================================================
-- CATEGORIAS
-- ============================================================
INSERT INTO categoria (nombre, descripcion) VALUES
('Pizzas', 'Pizzas artesanales a la piedra'),
('Empanadas', 'Empanadas caseras variadas'),
('Bebidas', 'Gaseosas, aguas y jugos'),
('Postres', 'Postres y dulces caseros'),
('Hamburguesas', 'Hamburguesas artesanales');

-- Una categoría dada de baja lógica, para probar "vigentes"
INSERT INTO categoria (nombre, descripcion, eliminado) VALUES
('Descontinuados', 'Categoría vieja, ya no se usa', TRUE);

-- ============================================================
-- PRODUCTOS  (categoria_id: 1=Pizzas 2=Empanadas 3=Bebidas 4=Postres 5=Hamburguesas)
-- ============================================================
INSERT INTO producto (nombre, precio, descripcion, stock, disponible, categoria_id) VALUES
('Muzzarella', 3500.00, 'Pizza clásica de muzzarella', 20, TRUE, 1),
('Napolitana', 4200.00, 'Pizza con tomate y ajo', 15, TRUE, 1),
('Fugazzeta', 4500.00, 'Pizza de cebolla y muzzarella', 10, TRUE, 1),

('Empanada de carne', 900.00, 'Empanada frita de carne cortada a cuchillo', 50, TRUE, 2),
('Empanada de pollo', 850.00, 'Empanada al horno de pollo', 50, TRUE, 2),
('Empanada de jamón y queso', 800.00, 'Empanada al horno', 40, TRUE, 2),

('Coca-Cola 500ml', 1200.00, 'Gaseosa línea Coca-Cola', 100, TRUE, 3),
('Agua mineral 500ml', 700.00, 'Agua sin gas', 100, TRUE, 3),
('Jugo de naranja 500ml', 1000.00, 'Jugo exprimido', 30, TRUE, 3),

('Flan casero', 1500.00, 'Flan con dulce de leche', 12, TRUE, 4),
('Tiramisú', 2200.00, 'Postre italiano', 8, TRUE, 4),

('Hamburguesa clásica', 3800.00, 'Con cheddar y panceta', 25, TRUE, 5),
('Hamburguesa doble', 4900.00, 'Doble carne, doble cheddar', 15, TRUE, 5);

-- Un producto sin stock (para probar validación de sp_crear_pedido)
INSERT INTO producto (nombre, precio, descripcion, stock, disponible, categoria_id) VALUES
('Pizza especial (sin stock)', 5000.00, 'Solo para pruebas de stock insuficiente', 0, TRUE, 1);

-- Un producto no disponible
INSERT INTO producto (nombre, precio, descripcion, stock, disponible, categoria_id) VALUES
('Producto temporalmente no disponible', 2000.00, 'Solo para pruebas', 10, FALSE, 2);

-- Un producto dado de baja lógica
INSERT INTO producto (nombre, precio, descripcion, stock, disponible, categoria_id) VALUES
('Producto descontinuado', 1000.00, 'Ya no se vende', 0, FALSE, 1);
UPDATE producto SET eliminado = TRUE WHERE nombre = 'Producto descontinuado';

-- ============================================================
-- USUARIOS
-- ============================================================
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol) VALUES
('Ana', 'García', 'ana.garcia@mail.com', '2611111111', 'hash_ana', 'USUARIO'),
('Juan', 'Pérez', 'juan.perez@mail.com', '2612222222', 'hash_juan', 'USUARIO'),
('Lucía', 'Martínez', 'lucia.martinez@mail.com', '2613333333', 'hash_lucia', 'USUARIO'),
('Mariano', 'Chirino', 'mariano.chirino@mail.com', '2614444444', 'hash_mariano', 'ADMIN'),
('Sofía', 'Torres', 'sofia.torres@mail.com', '2615555555', 'hash_sofia', 'USUARIO');

-- Un usuario dado de baja lógica
INSERT INTO usuario (nombre, apellido, mail, contrasena) VALUES
('Usuario', 'Inactivo', 'inactivo@mail.com', 'hash_inactivo');
UPDATE usuario SET eliminado = TRUE WHERE mail = 'inactivo@mail.com';

-- ============================================================
-- PEDIDOS (usar SIEMPRE el procedimiento, nunca INSERT directo)
-- Los ids de producto se refieren al orden de inserción de arriba:
--  1 Muzzarella, 2 Napolitana, 3 Fugazzeta, 4 Emp. carne, 5 Emp. pollo,
--  6 Emp. jamón y queso, 7 Coca-Cola, 8 Agua, 9 Jugo naranja,
--  10 Flan, 11 Tiramisú, 12 Hamb. clásica, 13 Hamb. doble
-- Los ids de usuario: 1 Ana, 2 Juan, 3 Lucía, 4 Mariano, 5 Sofía
-- ============================================================

-- Pedido 1: Ana pide 2 pizzas + bebidas
CALL sp_crear_pedido(1, 'EFECTIVO',
    '[{"producto_id":1,"cantidad":2},
      {"producto_id":7,"cantidad":2}]'::jsonb);

-- Pedido 2: Juan pide empanadas
CALL sp_crear_pedido(2, 'TARJETA',
    '[{"producto_id":4,"cantidad":6},
      {"producto_id":5,"cantidad":6},
      {"producto_id":8,"cantidad":2}]'::jsonb);

-- Pedido 3: Lucía pide hamburguesas y postre
CALL sp_crear_pedido(3, 'TRANSFERENCIA',
    '[{"producto_id":12,"cantidad":1},
      {"producto_id":10,"cantidad":1}]'::jsonb);

-- Pedido 4: Ana vuelve a pedir (otro pedido distinto)
CALL sp_crear_pedido(1, 'TARJETA',
    '[{"producto_id":2,"cantidad":1},
      {"producto_id":9,"cantidad":1}]'::jsonb);

-- Pedido 5: Mariano pide bastante (para el ranking de gasto)
CALL sp_crear_pedido(4, 'EFECTIVO',
    '[{"producto_id":13,"cantidad":2},
      {"producto_id":3,"cantidad":1},
      {"producto_id":11,"cantidad":2}]'::jsonb);

-- Pedido 6: Sofía, pedido chico
CALL sp_crear_pedido(5, 'EFECTIVO',
    '[{"producto_id":6,"cantidad":4}]'::jsonb);

-- Actualizamos el estado de algunos pedidos para variar (por defecto quedan PENDIENTE)
UPDATE pedido SET estado = 'CONFIRMADO' WHERE id = 1;
UPDATE pedido SET estado = 'TERMINADO'  WHERE id = 2;
UPDATE pedido SET estado = 'CANCELADO'  WHERE id = 6;

-- ============================================================
-- BAJA LÓGICA DE UN PEDIDO COMPLETO (para probar HU-PED-04)
-- ============================================================
BEGIN;
    UPDATE detalle_pedido SET eliminado = TRUE WHERE pedido_id = 4;
    UPDATE pedido SET eliminado = TRUE WHERE id = 4;
COMMIT;
