-- ============================================================
-- Escenario 1 — Atomicidad
-- ============================================================

CALL sp_crear_pedido(1, 'EFECTIVO', '[{"producto_id":1,"cantidad":999}]'::jsonb);
SELECT * FROM pedido;

-- ============================================================
-- Escenario 2 — Transacción manual (COMMIT vs ROLLBACK)
-- ============================================================

BEGIN;
UPDATE producto SET stock = stock - 1 WHERE id = 7;
SELECT stock FROM producto WHERE id = 7;
COMMIT;

SELECT stock FROM producto WHERE id = 7;

BEGIN;
UPDATE producto SET stock = stock - 1 WHERE id = 7;
SELECT stock FROM producto WHERE id = 7;
ROLLBACK;

SELECT stock FROM producto WHERE id = 7;

-- ============================================================
-- Escenario 3 — Aislamiento (dos sesiones al mismo tiempo)
-- ============================================================

--En la seccion A
BEGIN;
SELECT stock FROM producto WHERE id = 7;

--Sin cerrar A, vamos a la seccion B
BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id = 7;
COMMIT;

--Volvemos a la seccion A
SELECT stock FROM producto WHERE id = 7;
COMMIT;

--Repetimos lo anterior pero poniendo antes en A:

SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN;
SELECT stock FROM producto WHERE id = 7;

BEGIN;
UPDATE producto SET stock = stock - 5 WHERE id = 7;
COMMIT;

SELECT stock FROM producto WHERE id = 7;
COMMIT;

-- ============================================================
-- Escenario 4 — Bloqueo con FOR UPDATE (evitar sobreventa)
-- ============================================================

SELECT id, stock FROM producto WHERE id = 3;

--En la seccion A
BEGIN;
CALL sp_crear_pedido(1, 'EFECTIVO', '[{"producto_id":3,"cantidad":8}]'::jsonb);
--En la seccion B
CALL sp_crear_pedido(2, 'EFECTIVO', '[{"producto_id":3,"cantidad":8}]'::jsonb);
--En la seccion A
COMMIT;


