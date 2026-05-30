-- ==============================================================================
-- FASE 1 CORREGIDA: ELIMINAR ESTADÍAS FUTURAS Y TODAS SUS DEPENDENCIAS
-- ==============================================================================

-- 1. Eliminamos los detalles de las facturas futuras
DELETE FROM public.detalle_factura 
WHERE id_factura IN (
    SELECT f.id_factura FROM public.factura f 
    JOIN public.estadia e ON f.id_estadia = e.id_estadia
    WHERE e.checkin > CURRENT_TIMESTAMP
);

-- 2. Eliminamos las facturas futuras
DELETE FROM public.factura 
WHERE id_estadia IN (
    SELECT id_estadia FROM public.estadia WHERE checkin > CURRENT_TIMESTAMP
);

-- 3. Eliminamos los consumos de servicios futuros
DELETE FROM public.consumo_servicio 
WHERE id_estadia IN (
    SELECT id_estadia FROM public.estadia WHERE checkin > CURRENT_TIMESTAMP
);

-- 4. NUEVO: Eliminamos las reseñas (resenia) asociadas a estadías futuras
DELETE FROM public.resenia
WHERE id_estadia IN (
    SELECT id_estadia FROM public.estadia WHERE checkin > CURRENT_TIMESTAMP
);

-- 5. Ahora sí, eliminamos las estadías futuras sin que la base de datos marque error
DELETE FROM public.estadia WHERE checkin > CURRENT_TIMESTAMP;
-- ==============================================================================
-- FASE 2: ARREGLAR INCONSISTENCIAS QUE CAUSAN FACTURAS DE $0 O MUY BAJAS
-- ==============================================================================

-- Problema A: Estadías donde el checkout es anterior o igual al checkin (0 días facturados)
-- Solución: Le sumamos aleatoriamente entre 2 a 5 días al checkin para crear un checkout lógico.
UPDATE public.estadia 
SET checkout = checkin + (floor(random() * 4 + 2) * INTERVAL '1 day')
WHERE checkout <= checkin OR checkout IS NULL;

-- Problema B: Precios de habitaciones irreales (Ej. habitaciones de $2 o $5)
-- Solución: Establecemos precios lógicos entre $60 y $150 para las que cuesten menos de $50.
UPDATE public.habitacion
SET precio = floor(random() * 90 + 60) 
WHERE precio < 50;

-- Problema C: Precios de servicios muy bajos
-- Solución: Establecemos precios lógicos entre $15 y $45.
UPDATE public.servicio
SET precio = floor(random() * 30 + 15) 
WHERE precio < 10;

-- ==============================================================================
-- FASE 3: REGENERAR TODAS LAS FACTURAS Y COBROS RESTANTES DESDE CERO
-- ==============================================================================

TRUNCATE TABLE detalle_factura, factura
RESTART IDENTITY;

-- 1. Insertar facturas base (Cambiamos 'TARJETA DE CREDITO' por 'TARJETA')
-- 1. Insertar facturas base con método de pago completamente aleatorio
INSERT INTO public.factura (id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar)
SELECT 
    r.id_empleado,
    r.id_huesped,
    e.id_estadia,
    e.checkout,
    -- Elegimos un índice al azar entre 1 y 5 dentro del arreglo de métodos permitidos
    (ARRAY['EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'BITCOIN', 'PAYPAL'])[floor(random() * 5 + 1)],
    0.00
FROM public.estadia e
JOIN public.reservacion r ON e.id_reservacion = r.id_reservacion;
-- 2. Cobro de las Noches de Habitación
INSERT INTO public.detalle_factura (id_factura, id_habitacion, concepto, precio_unitario, cantidad, subtotal, precio_total)
SELECT 
    f.id_factura,
    dr.id_habitacion,
    'Estadía de habitación',
    h.precio,
    EXTRACT(DAY FROM (e.checkout - e.checkin)), 
    h.precio * EXTRACT(DAY FROM (e.checkout - e.checkin)),
    h.precio * EXTRACT(DAY FROM (e.checkout - e.checkin))
FROM public.factura f
JOIN public.estadia e ON f.id_estadia = e.id_estadia
JOIN public.detalle_reservacion dr ON e.id_reservacion = dr.id_reservacion
JOIN public.habitacion h ON dr.id_habitacion = h.id_habitacion;

-- 3. Cobro de todos los Servicios Consumidos
INSERT INTO public.detalle_factura (id_factura, id_servicio, concepto, precio_unitario, cantidad, subtotal, precio_total)
SELECT 
    f.id_factura,
    cs.id_servicio,
    s.tipo_servicio,
    s.precio,
    1, 
    s.precio,
    s.precio
FROM public.factura f
JOIN public.consumo_servicio cs ON f.id_estadia = cs.id_estadia
JOIN public.servicio s ON cs.id_servicio = s.id_servicio;

-- 4. Actualizar el Total Real a Pagar
WITH totales AS (
    SELECT id_factura, SUM(precio_total) as suma_total
    FROM public.detalle_factura
    GROUP BY id_factura
)
UPDATE public.factura f
SET total_a_pagar = t.suma_total
FROM totales t
WHERE f.id_factura = t.id_factura;





-- 1. Eliminar el detalle de las facturas originadas por reservaciones inválidas
DELETE FROM public.detalle_factura 
WHERE id_factura IN (
    SELECT f.id_factura FROM public.factura f 
    JOIN public.estadia e ON f.id_estadia = e.id_estadia
    JOIN public.reservacion r ON e.id_reservacion = r.id_reservacion
    WHERE r.estado NOT IN ('CONFIRMADA', 'COMPLETADA')
);

-- 2. Eliminar las facturas generadas por error
DELETE FROM public.factura 
WHERE id_estadia IN (
    SELECT e.id_estadia FROM public.estadia e
    JOIN public.reservacion r ON e.id_reservacion = r.id_reservacion
    WHERE r.estado NOT IN ('CONFIRMADA', 'COMPLETADA')
);

-- 3. Eliminar los consumos de servicios en esas estadías fantasma
DELETE FROM public.consumo_servicio 
WHERE id_estadia IN (
    SELECT e.id_estadia FROM public.estadia e
    JOIN public.reservacion r ON e.id_reservacion = r.id_reservacion
    WHERE r.estado NOT IN ('CONFIRMADA', 'COMPLETADA')
);

-- 4. Eliminar las reseñas dejadas para estadías que nunca ocurrieron (evita error 23001)
DELETE FROM public.resenia
WHERE id_estadia IN (
    SELECT e.id_estadia FROM public.estadia e
    JOIN public.reservacion r ON e.id_reservacion = r.id_reservacion
    WHERE r.estado NOT IN ('CONFIRMADA', 'COMPLETADA')
);

-- 5. Finalmente, eliminar las estadías asociadas a cancelaciones, rechazos o pendientes
DELETE FROM public.estadia 
WHERE id_reservacion IN (
    SELECT id_reservacion FROM public.reservacion 
    WHERE estado NOT IN ('CONFIRMADA', 'COMPLETADA')
);





INSERT INTO public.detalle_reservacion (
    id_reservacion, 
    id_habitacion, 
    cant_huespedes, 
    fecha_entrada, 
    fecha_salida
)
SELECT 
    r.id_reservacion,
    h.id_habitacion,
    r.cant_huespedes_totales,
    -- Usamos la fecha del check-in si existe; si no, asume una fecha anterior lógica
    CAST(COALESCE(e.checkin, CURRENT_TIMESTAMP - INTERVAL '5 days') AS DATE) AS fecha_entrada,
    -- Aseguramos matemáticamente con GREATEST() que la fecha de salida sea 
    -- al menos 1 día mayor a la entrada para no violar tu restricción ck_fecha_entrada
    CAST(
        GREATEST(
            COALESCE(e.checkout, e.checkin + INTERVAL '3 days', CURRENT_TIMESTAMP - INTERVAL '2 days'),
            COALESCE(e.checkin, CURRENT_TIMESTAMP - INTERVAL '5 days') + INTERVAL '1 day'
        ) AS DATE
    ) AS fecha_salida
FROM public.reservacion r
LEFT JOIN public.estadia e ON r.id_reservacion = e.id_reservacion
CROSS JOIN LATERAL (
    -- Asignamos 1 habitación aleatoria a esta reservación huérfana
    SELECT id_habitacion FROM public.habitacion ORDER BY random() LIMIT 1
) h
WHERE r.id_reservacion NOT IN (SELECT id_reservacion FROM public.detalle_reservacion);






DO $$
DECLARE
    v_huesped bigint;
    v_empleado bigint;
    v_habitacion bigint;
    v_reservacion bigint;
    v_estadia bigint;
    v_factura bigint;
    v_checkin timestamp;
    v_checkout timestamp;
    v_dias int;
    v_precio_hab numeric;
    v_total numeric;
    v_servicio bigint;
    v_precio_serv numeric;
    v_tipo_serv varchar;
    i int;
BEGIN
    -- Iteramos sobre el arreglo con los IDs exactos de tus 5 clientes
    FOR v_huesped IN SELECT unnest(ARRAY[838, 143, 899, 827, 403]) LOOP
        
        -- 1. Obtenemos un empleado y una habitación al azar de tu catálogo
        SELECT id_empleado INTO v_empleado FROM public.empleado ORDER BY random() LIMIT 1;
        SELECT id_habitacion, precio INTO v_habitacion, v_precio_hab FROM public.habitacion ORDER BY random() LIMIT 1;
        
        -- 2. Matemáticas de tiempo: Generamos una fecha aleatoria en 2025
        -- y le sumamos entre 2 y 6 días para el checkout
        v_checkin := timestamp '2025-01-01 14:00:00' + (random() * 330) * interval '1 day';
        v_dias := floor(random() * 5 + 2)::int;
        v_checkout := v_checkin + (v_dias * interval '1 day');
        
        -- 3. Nace la Reservación (Capturamos el ID generado usando RETURNING)
        INSERT INTO public.reservacion (id_empleado, id_huesped, cant_huespedes_totales, estado)
        VALUES (v_empleado, v_huesped, 2, 'COMPLETADA')
        RETURNING id_reservacion INTO v_reservacion;
        
        -- 4. Amarramos la habitación a esa reservación (El Detalle)
        INSERT INTO public.detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida)
        VALUES (v_reservacion, v_habitacion, 2, v_checkin::date, v_checkout::date);
        
        -- 5. Nace la Estadía real del huésped en el hotel
        INSERT INTO public.estadia (id_reservacion, checkin, checkout)
        VALUES (v_reservacion, v_checkin, v_checkout)
        RETURNING id_estadia INTO v_estadia;
        
        -- 6. Se apertura la Factura con un método de pago aleatorio y total en $0
        INSERT INTO public.factura (id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar)
        VALUES (v_empleado, v_huesped, v_estadia, v_checkout, 
                (ARRAY['EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'BITCOIN', 'PAYPAL'])[floor(random() * 5 + 1)], 0.00)
        RETURNING id_factura INTO v_factura;
        
        -- 7. Facturamos las noches de la habitación
        v_total := v_precio_hab * v_dias;
        INSERT INTO public.detalle_factura (id_factura, id_habitacion, concepto, precio_unitario, cantidad, subtotal, precio_total)
        VALUES (v_factura, v_habitacion, 'Estadía de habitación', v_precio_hab, v_dias, v_total, v_total);
        
        -- 8. Simulamos que el huésped consumió 3 servicios durante esos días
        FOR i IN 1..3 LOOP
            -- Obtenemos un servicio al azar
            SELECT id_servicio, precio, tipo_servicio INTO v_servicio, v_precio_serv, v_tipo_serv 
            FROM public.servicio ORDER BY random() LIMIT 1;
            
            -- Lo insertamos en el historial de consumo, asegurando que la hora coincida dentro de su estadía
            INSERT INTO public.consumo_servicio (id_servicio, id_habitacion, id_estadia, hora_consumo)
            VALUES (v_servicio, v_habitacion, v_estadia, v_checkin + (random() * v_dias) * interval '1 day');
            
            -- Lo agregamos inmediatamente a la factura
            INSERT INTO public.detalle_factura (id_factura, id_servicio, concepto, precio_unitario, cantidad, subtotal, precio_total)
            VALUES (v_factura, v_servicio, v_tipo_serv, v_precio_serv, 1, v_precio_serv, v_precio_serv);
            
            -- Sumamos el costo al acumulador
            v_total := v_total + v_precio_serv;
        END LOOP;
        
        -- 9. Por último, actualizamos la tabla maestra de la factura con la suma exacta matemática
        UPDATE public.factura SET total_a_pagar = v_total WHERE id_factura = v_factura;
        
    END LOOP;
END $$;




DO $$
DECLARE
    v_hotel bigint; -- Nueva variable para fijar el hotel
    v_huesped bigint;
    v_empleado bigint;
    v_habitacion bigint;
    v_reservacion bigint;
    v_estadia bigint;
    v_factura bigint;
    v_checkin timestamp;
    v_checkout timestamp;
    v_dias int;
    v_precio_hab numeric;
    v_total numeric;
    v_servicio bigint;
    v_precio_serv numeric;
    v_tipo_serv varchar;
    i int;
BEGIN
    -- ================================================================
    -- 1. CAMBIO CLAVE: Seleccionamos UN SOLO HOTEL antes del ciclo
    -- ================================================================
    SELECT id_hotel INTO v_hotel FROM public.hotel ORDER BY random() LIMIT 1;
    
    -- Iniciamos el recorrido por tus 5 clientes
    FOR v_huesped IN SELECT unnest(ARRAY[838, 143, 899, 827, 403]) LOOP
        
        -- Obtenemos un empleado al azar para atender la reservación
        SELECT id_empleado INTO v_empleado FROM public.empleado ORDER BY random() LIMIT 1;
        
        -- ================================================================
        -- 2. CAMBIO CLAVE: Filtramos la habitación usando el v_hotel fijado
        -- ================================================================
        SELECT id_habitacion, precio INTO v_habitacion, v_precio_hab 
        FROM public.habitacion 
        WHERE id_hotel = v_hotel 
        ORDER BY random() 
        LIMIT 1;
        
        -- Generamos una fecha aleatoria en 2025 y le sumamos entre 2 y 6 días
        v_checkin := timestamp '2025-01-01 14:00:00' + (random() * 330) * interval '1 day';
        v_dias := floor(random() * 5 + 2)::int;
        v_checkout := v_checkin + (v_dias * interval '1 day');
        
        -- Nace la Reservación
        INSERT INTO public.reservacion (id_empleado, id_huesped, cant_huespedes_totales, estado)
        VALUES (v_empleado, v_huesped, 2, 'COMPLETADA')
        RETURNING id_reservacion INTO v_reservacion;
        
        -- Amarramos la habitación de ese hotel a la reservación
        INSERT INTO public.detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida)
        VALUES (v_reservacion, v_habitacion, 2, v_checkin::date, v_checkout::date);
        
        -- Nace la Estadía
        INSERT INTO public.estadia (id_reservacion, checkin, checkout)
        VALUES (v_reservacion, v_checkin, v_checkout)
        RETURNING id_estadia INTO v_estadia;
        
        -- Se apertura la Factura
        INSERT INTO public.factura (id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar)
        VALUES (v_empleado, v_huesped, v_estadia, v_checkout, 
                (ARRAY['EFECTIVO', 'TRANSFERENCIA', 'TARJETA', 'BITCOIN', 'PAYPAL'])[floor(random() * 5 + 1)], 0.00)
        RETURNING id_factura INTO v_factura;
        
        -- Facturamos las noches de la habitación
        v_total := v_precio_hab * v_dias;
        INSERT INTO public.detalle_factura (id_factura, id_habitacion, concepto, precio_unitario, cantidad, subtotal, precio_total)
        VALUES (v_factura, v_habitacion, 'Estadía de habitación', v_precio_hab, v_dias, v_total, v_total);
        
        -- Consumo de 3 servicios
        FOR i IN 1..3 LOOP
            SELECT id_servicio, precio, tipo_servicio INTO v_servicio, v_precio_serv, v_tipo_serv 
            FROM public.servicio ORDER BY random() LIMIT 1;
            
            INSERT INTO public.consumo_servicio (id_servicio, id_habitacion, id_estadia, hora_consumo)
            VALUES (v_servicio, v_habitacion, v_estadia, v_checkin + (random() * v_dias) * interval '1 day');
            
            INSERT INTO public.detalle_factura (id_factura, id_servicio, concepto, precio_unitario, cantidad, subtotal, precio_total)
            VALUES (v_factura, v_servicio, v_tipo_serv, v_precio_serv, 1, v_precio_serv, v_precio_serv);
            
            v_total := v_total + v_precio_serv;
        END LOOP;
        
        -- Actualizamos el total de la factura
        UPDATE public.factura SET total_a_pagar = v_total WHERE id_factura = v_factura;
        
    END LOOP;
END $$;