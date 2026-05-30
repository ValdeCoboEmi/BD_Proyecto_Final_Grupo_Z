--===============VISTAS=====================

-- Vista que obtiene el total de ingresos por mes correspondientes al año en curso
CREATE OR REPLACE VIEW ingresos_mes AS (
    SELECT
        EXTRACT('year' FROM CURRENT_DATE) AS año_en_curso,
        EXTRACT('month' FROM f.fecha) AS num_mes,
        TO_CHAR(f.fecha, 'Month') AS mes,
        SUM(f.total_a_pagar) AS ingresos
    FROM factura f
    WHERE
        -- Filtra las facturas para incluir únicamente las generadas en el año actual
        EXTRACT(YEAR FROM CURRENT_DATE) = EXTRACT('year' FROM f.fecha)
    GROUP BY año_en_curso, num_mes, mes
    ORDER BY num_mes ASC
);

select * from ingresos_mes;

-- Vista que resume la información general de los hoteles (calificación, capacidad y ganancias)
CREATE OR REPLACE VIEW info_general_hoteles AS (
    SELECT
        h.nombre AS hotel,
        h.calificacion,
        -- Cuenta las habitaciones de forma única para evitar multiplicaciones por el JOIN
        COUNT(DISTINCT h2.id_habitacion) AS cant_habitaciones,
        -- Suma el subtotal por detalle para evitar ingresos duplicados en facturas con múltiples líneas
        SUM(df.precio_total) AS ganancias
    FROM hotel h
    JOIN habitacion h2
        ON h.id_hotel = h2.id_hotel
    JOIN detalle_factura df
        ON h2.id_habitacion = df.id_habitacion
    JOIN factura f
        ON df.id_factura = f.id_factura
    GROUP BY h.id_hotel
);

SELECT * FROM info_general_hoteles;


--==================PROCEDIMIENTOS=====================

-- Procedimiento almacenado para calcular el detalle de la factura
-- Parámetros:
-- id_estadia (bigint, es el id de la estadia a procesar)
-- id_empleado (bigint, el id del empleado que cobra la factura)
-- metodo_pago (varchar, el metodo de pago de la factura)

CREATE OR REPLACE PROCEDURE calcular_total_factura(
    p_id_estadia BIGINT,
    p_id_empleado BIGINT,
    p_metodo_pago VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    -- Variable para guardar el total a pagar de la factura
    v_total_a_pagar NUMERIC(10,2) := 0;

    -- Variable para verificar si la reservacion existe
    v_existe BOOLEAN;

    -- Variable para guardar el id del huesped
    v_id_huesped BIGINT;

    -- Variable para guardar el id de la factura creada
    v_id_factura BIGINT;

    -- Variable para guardar el select de las habitaciones de la estadia
    habitacion_estadia RECORD;

    -- Variable para guardar los dias sin temporada alta de la estadia
    v_dias_normal INT := 0;
	
    -- Variable para guardar el subtotal del detalle de factura
    v_subtotal NUMERIC(10,2) := 0;

    -- Variable para guardar el total del detalle de factura
    v_total NUMERIC(10,2) := 0;

    -- Variable para guardar el select de los servicios consumidos
    servicio_estadia RECORD;

    -- Variable para guardar el monto del descuento del detalle de factura
    v_monto_descuento NUMERIC(10,2) := 0;
	
	-- variable para guardar el porcentaje del descuento
	v_porcentaje_descuento NUMERIC(10,2) := 0;

    -- Variable para guardar el id del descuento
    v_id_descuento BIGINT ;
	
    -- Variable para guardar el monto del aumento
    v_monto_aumento NUMERIC(10,2) := 0;

    -- Variable para guardar el porcentaje total de aumento
    v_porcentaje_aumento NUMERIC(10,2) := 0;

    -- Variable para guardar el id del aumento por temporada
    v_id_aumento_costo BIGINT;

    -- Variable para guardar el select de la temporada activa (para los aumentos del precio)
    aumento_temporada RECORD;
	
BEGIN
    -- Se valida si la estadia existe
    SELECT EXISTS (
        SELECT 1
        FROM estadia
        WHERE id_estadia = p_id_estadia
    )
    INTO v_existe;

    -- Si no existe, se muestra un mensaje de error
    IF NOT v_existe THEN
        RAISE EXCEPTION 'La estadia con ID % no existe en la base de datos.', p_id_estadia;
    END IF;

    -- Se guarda el id del huesped en la variable global
    SELECT
        r.id_huesped
	INTO v_id_huesped
    FROM estadia e
    JOIN reservacion r
        ON e.id_reservacion = r.id_reservacion
    WHERE e.id_estadia = p_id_estadia;

    -- Se inserta la factura en la tabla con los campos obtenidos
    INSERT INTO factura (
        id_empleado,
        id_huesped,
        id_estadia,
        metodo_pago,
        total_a_pagar
    )
    VALUES (
        p_id_empleado,
        p_id_huesped,
        p_id_estadia,
        p_metodo_pago,
        0
    )
    RETURNING id_factura
    INTO v_id_factura;
    -- Se recorren todas las habitaciones sobre esa estadia
    FOR habitacion_estadia IN
        SELECT
            dr.id_habitacion,
            h.descripcion,
            h.precio,
            dr.fecha_entrada,
            dr.fecha_salida
        FROM estadia e
        JOIN reservacion r
            ON e.id_reservacion = r.id_reservacion
        JOIN detalle_reservacion dr
            ON r.id_reservacion = dr.id_reservacion
        JOIN habitacion h
            ON dr.id_habitacion = h.id_habitacion
        WHERE e.id_estadia = p_id_estadia
    LOOP
        -- Se calculan todos los dias de la estadia
        v_dias_normal := habitacion_estadia.fecha_salida - habitacion_estadia.fecha_entrada;
			
		-- se guarda el porcentaje del descuento en base a los dias totales de la estadia
	    SELECT d.id_descuento,
	           d.porcentaje_descuento
	    INTO v_id_descuento,
	    v_porcentaje_descuento
		FROM descuento d
	    WHERE d.cant_dia_hospedado <= v_dias_normal
	    ORDER BY d.cant_dia_hospedado DESC
	    LIMIT 1;
			
		-- Se recorren todos los registros de las temporadas activas, devuelve el nombre de la temporada, 
		-- los dias que coinciden con las fechas de la estadia y el porcentaje de aumento respectivo
    	FOR aumento_temporada IN
			SELECT
				id_aumento_costo,
			    nombre_temporada,
			    COALESCE(UPPER(rango_temporada * rango_estadia)- LOWER(rango_temporada * rango_estadia),0) AS dias_coincidentes,
			    porcentaje_aumento
			FROM (
			    SELECT
					ac.id_aumento_costo,
			        daterange(ac.fecha_inicio, ac.fecha_fin, '[]') AS rango_temporada,
			        ac.nombre_temporada,
			        ac.porcentaje_aumento,
			        daterange(habitacion_estadia.fecha_entrada, habitacion_estadia.fecha_salida, '[]') AS rango_estadia
			    FROM aumento_costos ac
			    WHERE ac.activado = TRUE
			) AS subconsulta
			WHERE rango_temporada && rango_estadia
		LOOP
			-- se calcula el subtotal (dias que coinciden * precio original de la habitacion)
			v_subtotal := ROUND(aumento_temporada.dias_coincidentes * habitacion_estadia.precio, 2);
			-- se calcula el monto aumentado (subtotal * porcentaje aumento / 100)
			v_monto_aumento := round((v_subtotal * aumento_temporada.porcentaje_aumento / 100),2);
			-- se calcula el total sumando el subtotal con el monto aumentado
			v_total := v_subtotal + v_monto_aumento;
			-- se restan los dias de temporada alta a los dias totales de la estadia (para aplicar descuento despues a esos dias)
			v_dias_normal := v_dias_normal - aumento_temporada.dias_coincidentes;
			-- Se inserta el detalle de la factura con la informacion de la habitacion
	        -- En este caso el campo "cantidad" hace referencia a los dias de la estadia que estan en temporada alta
	        INSERT INTO detalle_factura (
	            id_factura,
	            id_habitacion,
				id_aumento_costo,
	            concepto,
	            precio_unitario,
	            cantidad,
	            subtotal,
				monto_aumento,
	            precio_total
	        )
	        VALUES (
	            v_id_factura,
	            habitacion_estadia.id_habitacion,
				aumento_temporada.id_aumento_costo,
				-- se concatena la descripcion de la habitacion con la temporada actual
	            concat(habitacion_estadia.descripcion, ' - ', aumento_temporada.nombre_temporada),
	            habitacion_estadia.precio,
	            aumento_temporada.dias_coincidentes,
	            v_subtotal,
				v_monto_aumento,
	            v_total
	        );	

		END LOOP;
		
		if v_dias_normal > 0 then
			-- Se calcula el subtotal (dias * precio habitacion)
	        v_subtotal := ROUND(v_dias_normal * habitacion_estadia.precio, 2);
			
			-- se calcula el monto a descontar 
			v_monto_descuento := v_subtotal * (v_porcentaje_descuento / 100);

			-- se calcula el total (subtotal - monto a descontar)
	        v_total := v_subtotal - v_monto_descuento;
			
	        -- Se inserta el detalle de la factura con la informacion de la habitacion
	        -- En este caso el campo "cantidad" hace referencia a los dias de la estadia
	        INSERT INTO detalle_factura (
	            id_factura,
	            id_habitacion,
				id_descuento,
	            concepto,
	            precio_unitario,
	            cantidad,
	            subtotal,
				monto_descuento,
	            precio_total
	        )
	        VALUES (
	            v_id_factura,
	            habitacion_estadia.id_habitacion,
				v_id_descuento,
	            habitacion_estadia.descripcion,
	            habitacion_estadia.precio,
	            v_dias_normal,
	            v_subtotal,
				v_monto_descuento,
	            v_total
	        );

		end if;

    END LOOP;

    -- Se recorren todos los servicios que se consumieron por estadia
    FOR servicio_estadia IN
        SELECT
			cs.id_servicio,
            cs.id_estadia,
            s.tipo_servicio,
            s.precio,
            COUNT(cs.id_servicio) cantidad
        FROM consumo_servicio cs
        JOIN estadia e
            ON cs.id_estadia = e.id_estadia
        JOIN servicio s
            ON cs.id_servicio = s.id_servicio
        GROUP BY
            cs.id_servicio,
            cs.id_estadia,
            s.tipo_servicio,
            s.precio
        HAVING cs.id_estadia = p_id_estadia
    LOOP
        -- Se calcula el subtotal multiplicando el precio por la cantidad de veces que se consumió ese servicio
        v_subtotal = ROUND(servicio_estadia.precio * servicio_estadia.cantidad, 2);
        v_total = v_subtotal;

        INSERT INTO detalle_factura (
            id_factura,
            id_servicio,
            concepto,
            precio_unitario,
            cantidad,
            subtotal,
            precio_total
        )
        VALUES (
            v_id_factura,
            servicio_estadia.id_servicio,
            servicio_estadia.tipo_servicio,
            servicio_estadia.precio,
            servicio_estadia.cantidad,
            v_subtotal,
            v_total
        );
    END LOOP;

    -- Se calcula el total a pagar sumando todos los totales de cada detalle de factura
    SELECT SUM(precio_total) 
	INTO v_total_a_pagar 
	FROM detalle_factura 
	WHERE id_factura = v_id_factura;

    -- Se actualiza la tabla factura con el total a pagar
    UPDATE factura
    SET total_a_pagar = v_total_a_pagar
    WHERE id_factura = v_id_factura;

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE NOTICE 'Ocurrió un error: %', SQLERRM;
END;
$$;


-- ====================== TRIGGERS ================

-- TRIGGER para ejecutar el procedimiento que calcula el detalle de la factura
CREATE OR REPLACE FUNCTION fn_generar_factura_checkout()
RETURNS TRIGGER 
LANGUAGE plpgsql
AS $$
DECLARE
    -- Variables para el procedimiento
    v_id_empleado BIGINT;
    v_metodo_pago VARCHAR := 'EFECTIVO'; -- Valor temporal por defecto
BEGIN
    -- se valida que el checkout pasó de estar vacío (NULL) a tener una fecha
    IF OLD.checkout IS NULL AND NEW.checkout IS NOT NULL THEN
        
   		--SELECT para obtener el id_empleado desde la tabla reservacion
		select id_empleado into v_id_empleado from reservacion where id_reservacion = NEW.id_reservacion;
        -- se manda a llamar el procedimiento para calcular el detalle de la factura
        CALL calcular_total_factura(NEW.id_estadia, v_id_empleado, v_metodo_pago);
        
    END IF;
    
    RETURN NEW;
END;
$$;

-- se añade el trigger a la tabla de estadia para cada actualizacion del campo "checkout"
CREATE TRIGGER trg_checkout_factura
AFTER UPDATE OF checkout ON estadia
FOR EACH ROW
EXECUTE FUNCTION fn_generar_factura_checkout();
