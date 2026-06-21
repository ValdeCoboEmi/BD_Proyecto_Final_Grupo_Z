--
-- PostgreSQL database dump
--

\restrict DrF9YcJq10JHFoatMdUQRUb7WLoRMhuWfhjhO526eocQNwsWGNZbcGGJPlO8ecc

-- Dumped from database version 18.4
-- Dumped by pg_dump version 18.4

-- Started on 2026-06-20 23:23:39

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 290 (class 1255 OID 31025)
-- Name: actualizar_calificacion_hotel(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.actualizar_calificacion_hotel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_hotel bigint;
    v_nueva_calificacion numeric(2,1);
BEGIN 
    -- 1. Se obtiene el ID del hotel relacionado a la nueva rese├▒a
    -- LIMIT 1 por si la reservaci├│n tiene m├║ltiples habitaciones para el mismo hotel
    SELECT hab.id_hotel INTO v_id_hotel
    FROM estadia est
    INNER JOIN detalle_reservacion det ON est.id_reservacion = det.id_reservacion
    INNER JOIN habitacion hab ON det.id_habitacion = hab.id_habitacion
    WHERE est.id_estadia = NEW.id_estadia
    LIMIT 1;
    
    -- 2. Calcula el promedio de calificaci├│n para ese hotel
    -- ROUND a 1 decimal para que coincida con la calificacion de la tabla
    SELECT ROUND(AVG(r.calificacion), 1) INTO v_nueva_calificacion
    FROM resenia r
    INNER JOIN estadia est ON r.id_estadia = est.id_estadia
    INNER JOIN detalle_reservacion det ON est.id_reservacion = det.id_reservacion
    INNER JOIN habitacion hab ON det.id_habitacion = hab.id_habitacion
    WHERE hab.id_hotel = v_id_hotel;
    
    -- 3. Actualiza la tabla hotel con el nuevo promedio
    UPDATE hotel
    SET calificacion = v_nueva_calificacion
    WHERE id_hotel = v_id_hotel;

    -- Como es un trigger AFTER para INSERT/UPDATE, devolvemos NEW
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.actualizar_calificacion_hotel() OWNER TO postgres;

--
-- TOC entry 292 (class 1255 OID 31528)
-- Name: fn_actualizar_calificacion_hotel(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_actualizar_calificacion_hotel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_id_hotel bigint;
    v_nueva_calificacion numeric(2,1);
BEGIN 
    -- Buscamos si ya existe otra reseña registrada para esta misma estadía/reservación
    IF EXISTS (
        SELECT 1 
        FROM resenia 
        WHERE id_estadia = NEW.id_estadia 
          -- Esto evita que marque error si el huésped está actualizando su propia reseña
          AND id_resenia IS DISTINCT FROM NEW.id_resenia
    ) THEN
        -- Si encuentra una reseña previa, aborta la operación
        RAISE EXCEPTION 'Ya existe una calificación ingresada para la estadía/reservación %.', NEW.id_estadia;
    END IF;

    -- Si no hay choque, continúa normalmente con el cálculo
    
    -- 1. Obtener el ID del hotel relacionado a la nueva reseña
    SELECT hab.id_hotel INTO v_id_hotel
    FROM estadia est
    INNER JOIN detalle_reservacion det ON est.id_reservacion = det.id_reservacion
    INNER JOIN habitacion hab ON det.id_habitacion = hab.id_habitacion
    WHERE est.id_estadia = NEW.id_estadia
    LIMIT 1;
    
    -- 2. Calcular el promedio de calificación para ese hotel
    SELECT ROUND(AVG(r.calificacion), 1) INTO v_nueva_calificacion
    FROM resenia r
    INNER JOIN estadia est ON r.id_estadia = est.id_estadia
    INNER JOIN detalle_reservacion det ON est.id_reservacion = det.id_reservacion
    INNER JOIN habitacion hab ON det.id_habitacion = hab.id_habitacion
    WHERE hab.id_hotel = v_id_hotel;
    
    -- 3. Actualizar la tabla hotel con el nuevo promedio
    UPDATE hotel
    SET calificacion = v_nueva_calificacion
    WHERE id_hotel = v_id_hotel;

    -- Devolver NEW para que la operación se complete con éxito
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_actualizar_calificacion_hotel() OWNER TO postgres;

--
-- TOC entry 295 (class 1255 OID 31534)
-- Name: fn_buscar_habitaciones_disponibles(date, date, bigint); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_buscar_habitaciones_disponibles(p_fecha_entrada date, p_fecha_salida date, p_id_tipo_habitacion bigint) RETURNS TABLE(id_habitacion_libre bigint, nombre_hotel_pertenece character varying, numero_habitacion_libre integer, tipo_habitacion_libre character varying, precio_habitacion numeric)
    LANGUAGE plpgsql
    AS $$
begin
    return query
    select 
        h.id_habitacion, 
        ho.nombre,
        h.numero_habitacion, 
        th.tipo_habitacion,
        h.precio
    from habitacion h
    inner join hotel ho on h.id_hotel = ho.id_hotel 
    inner join tipo_habitacion th on h.id_tipo_habitacion = th.id_tipo_habitacion 
    where h.id_tipo_habitacion = p_id_tipo_habitacion
      and h.estado = 'DISPONIBLE'
      and h.id_habitacion not in (
          select dr.id_habitacion 
          from detalle_reservacion dr
          join reservacion r on dr.id_reservacion = r.id_reservacion
          where r.estado in ('PENDIENTE', 'CONFIRMADA')
            and not (p_fecha_salida <= dr.fecha_entrada or p_fecha_entrada >= dr.fecha_salida)
      );
end;
$$;


ALTER FUNCTION public.fn_buscar_habitaciones_disponibles(p_fecha_entrada date, p_fecha_salida date, p_id_tipo_habitacion bigint) OWNER TO postgres;

--
-- TOC entry 294 (class 1255 OID 31532)
-- Name: fn_generar_factura_checkout(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_generar_factura_checkout() RETURNS trigger
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


ALTER FUNCTION public.fn_generar_factura_checkout() OWNER TO postgres;

--
-- TOC entry 278 (class 1255 OID 31526)
-- Name: fn_validar_disponibilidad_habitacion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_disponibilidad_habitacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    -- buscamos si ya existe una reserva activa que choque con las fechas nuevas
    if exists (
        select 1 
        from public.detalle_reservacion dr
        inner join public.reservacion r on dr.id_reservacion = r.id_reservacion
        where dr.id_habitacion = new.id_habitacion 
          and dr.fecha_entrada < new.fecha_salida 
          and dr.fecha_salida > new.fecha_entrada
          and r.estado not in ('cancelada', 'rechazada')	
          and dr.id_detalle_reservacion is distinct from new.id_detalle_reservacion
    ) then
        -- si encuentra un choque con una reserva válida, aborta la operación
        raise exception 'la habitación % ya se encuentra reservada en esas fechas.', new.id_habitacion;
    end if;

    -- si no hay choques, deja pasar los datos 
    return new;
end;
$$;


ALTER FUNCTION public.fn_validar_disponibilidad_habitacion() OWNER TO postgres;

--
-- TOC entry 296 (class 1255 OID 31535)
-- Name: fn_validar_nivel_habitacion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validar_nivel_habitacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare nivel_hotel int;
begin 
	-- se guarda el nivel del hotel de la habitacion en una variable
	select niveles_edificios into nivel_hotel
	from hotel where id_hotel = NEW.id_hotel;
	-- se valida si el nivel ingresado es mayor al del hotel
	if NEW.nivel > nivel_hotel then
		raise exception 'Operación cancelada: el nivel ingresado (%) es mayor al del hotel (%).', NEW.nivel, nivel_hotel;
	end if;
	
	return new;
end;
$$;


ALTER FUNCTION public.fn_validar_nivel_habitacion() OWNER TO postgres;

--
-- TOC entry 293 (class 1255 OID 31530)
-- Name: sp_calcular_total_factura(bigint, bigint, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_calcular_total_factura(IN p_id_estadia bigint, IN p_id_empleado bigint, IN p_metodo_pago character varying)
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
        V_id_huesped,
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
END;
$$;


ALTER PROCEDURE public.sp_calcular_total_factura(IN p_id_estadia bigint, IN p_id_empleado bigint, IN p_metodo_pago character varying) OWNER TO postgres;

--
-- TOC entry 291 (class 1255 OID 31026)
-- Name: validar_disponibilidad_habitacion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.validar_disponibilidad_habitacion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Buscamos si ya existe una reserva que choque con las fechas nuevas
    IF EXISTS (
        SELECT 1 
        FROM detalle_reservacion 
        WHERE id_habitacion = NEW.id_habitacion 
          -- Esta es la l├│gica matem├ítica para detectar si dos rangos de fecha se cruzan
          AND fecha_entrada < NEW.fecha_salida 
          AND fecha_salida > NEW.fecha_entrada
          -- Esto evita que marque error si estamos actualizando (UPDATE) la misma reserva
          AND id_detalle_reservacion IS DISTINCT FROM NEW.id_detalle_reservacion
    ) THEN
        -- Si encuentra un choque, aborta la operaci├│n y lanza este mensaje
        RAISE EXCEPTION 'La habitaci├│n % ya est├í reservada en esas fechas.', NEW.id_habitacion;
    END IF;

    -- Si no hay choques, deja pasar los datos (retorna NEW)
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.validar_disponibilidad_habitacion() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 219 (class 1259 OID 31027)
-- Name: aumento_costos; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.aumento_costos (
    id_aumento_costo bigint NOT NULL,
    porcentaje_aumento numeric(5,2) NOT NULL,
    fecha_inicio date NOT NULL,
    fecha_fin date NOT NULL,
    nombre_temporada character varying(100),
    activado boolean DEFAULT true,
    CONSTRAINT ck_fecha_inicio CHECK ((fecha_inicio < fecha_fin)),
    CONSTRAINT ck_porcentaje_aumento CHECK ((porcentaje_aumento >= (0)::numeric))
);


ALTER TABLE public.aumento_costos OWNER TO postgres;

--
-- TOC entry 220 (class 1259 OID 31037)
-- Name: aumento_costos_id_aumento_costo_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.aumento_costos ALTER COLUMN id_aumento_costo ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.aumento_costos_id_aumento_costo_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 221 (class 1259 OID 31038)
-- Name: comodidad_tipo_habitacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.comodidad_tipo_habitacion (
    id_comodidad_habitacion bigint NOT NULL,
    id_tipo_habitacion bigint NOT NULL,
    id_tipo_comodidad bigint NOT NULL,
    detalle text NOT NULL
);


ALTER TABLE public.comodidad_tipo_habitacion OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 31047)
-- Name: comodidad_tipo_habitacion_id_comodidad_habitacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.comodidad_tipo_habitacion ALTER COLUMN id_comodidad_habitacion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.comodidad_tipo_habitacion_id_comodidad_habitacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 223 (class 1259 OID 31048)
-- Name: consumo_servicio; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.consumo_servicio (
    id_consumo_servicio bigint NOT NULL,
    id_servicio bigint NOT NULL,
    id_habitacion bigint NOT NULL,
    id_estadia bigint NOT NULL,
    hora_consumo timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.consumo_servicio OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 31057)
-- Name: consumo_servicio_id_consumo_servicio_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.consumo_servicio ALTER COLUMN id_consumo_servicio ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.consumo_servicio_id_consumo_servicio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 225 (class 1259 OID 31058)
-- Name: detalle_reservacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.detalle_reservacion (
    id_detalle_reservacion bigint NOT NULL,
    id_reservacion bigint NOT NULL,
    id_habitacion bigint NOT NULL,
    cant_huespedes integer NOT NULL,
    fecha_entrada date NOT NULL,
    fecha_salida date NOT NULL,
    CONSTRAINT ck_cant_huespedes_detalle CHECK ((cant_huespedes > 0)),
    CONSTRAINT ck_fecha_entrada CHECK ((fecha_entrada < fecha_salida))
);


ALTER TABLE public.detalle_reservacion OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 31069)
-- Name: estadia; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.estadia (
    id_estadia bigint NOT NULL,
    id_reservacion bigint NOT NULL,
    checkin timestamp without time zone DEFAULT now() NOT NULL,
    checkout timestamp without time zone,
    CONSTRAINT ck_checkin CHECK (((checkout IS NULL) OR (checkin < checkout)))
);


ALTER TABLE public.estadia OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 31077)
-- Name: factura; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.factura (
    id_factura bigint NOT NULL,
    id_empleado bigint NOT NULL,
    id_huesped bigint NOT NULL,
    id_estadia bigint NOT NULL,
    fecha timestamp without time zone DEFAULT now() NOT NULL,
    metodo_pago character varying(50) NOT NULL,
    total_a_pagar numeric(10,2) NOT NULL,
    CONSTRAINT ck_metodo_pago CHECK (((metodo_pago)::text = ANY (ARRAY[('EFECTIVO'::character varying)::text, ('TRANSFERENCIA'::character varying)::text, ('TARJETA'::character varying)::text, ('BITCOIN'::character varying)::text, ('PAYPAL'::character varying)::text]))),
    CONSTRAINT ck_total_pagar CHECK ((total_a_pagar >= (0)::numeric))
);


ALTER TABLE public.factura OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 31090)
-- Name: habitacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.habitacion (
    id_habitacion bigint NOT NULL,
    id_hotel bigint NOT NULL,
    nivel integer NOT NULL,
    numero_habitacion integer NOT NULL,
    id_tipo_habitacion bigint NOT NULL,
    precio numeric(10,2) NOT NULL,
    estado character varying(50) NOT NULL,
    capacidad_maxima integer NOT NULL,
    descripcion text,
    CONSTRAINT ck_capacidad_maxima CHECK (((capacidad_maxima >= 1) AND (capacidad_maxima <= 15))),
    CONSTRAINT ck_estado CHECK (((estado)::text = ANY (ARRAY[('DISPONIBLE'::character varying)::text, ('OCUPADA'::character varying)::text, ('MANTENIMIENTO'::character varying)::text]))),
    CONSTRAINT ck_nivel CHECK ((nivel >= 0)),
    CONSTRAINT ck_num_habitacion CHECK ((numero_habitacion >= 0)),
    CONSTRAINT ck_precio CHECK ((precio >= (0)::numeric))
);


ALTER TABLE public.habitacion OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 31108)
-- Name: hotel; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.hotel (
    id_hotel bigint NOT NULL,
    nombre character varying(255) NOT NULL,
    direccion character varying(255),
    niveles_edificios integer NOT NULL,
    calificacion numeric(2,1),
    descripcion text,
    CONSTRAINT ck_calificacion CHECK (((calificacion >= (1)::numeric) AND (calificacion <= (5)::numeric))),
    CONSTRAINT ck_niveles CHECK ((niveles_edificios > 0))
);


ALTER TABLE public.hotel OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 31118)
-- Name: datos_generales_hoteles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.datos_generales_hoteles AS
 WITH ganancia_por_anio AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            sum(f.total_a_pagar) AS total_del_anio
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha))
        ), promedio_anual AS (
         SELECT ganancia_por_anio.id_hotel,
            round(avg(ganancia_por_anio.total_del_anio), 2) AS ganancia_promedio_anual
           FROM ganancia_por_anio
          GROUP BY ganancia_por_anio.id_hotel
        ), ganancia_por_mes AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            EXTRACT(month FROM f.fecha) AS mes,
            sum(f.total_a_pagar) AS total_del_mes
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha)), (EXTRACT(month FROM f.fecha))
        ), promedio_mensual AS (
         SELECT ganancia_por_mes.id_hotel,
            round(avg(ganancia_por_mes.total_del_mes), 2) AS ganancia_promedio_mensual
           FROM ganancia_por_mes
          GROUP BY ganancia_por_mes.id_hotel
        ), habitaciones_hotel AS (
         SELECT habitacion.id_hotel,
            count(*) AS habitaciones_totales,
            sum((((habitacion.estado)::text = 'DISPONIBLE'::text))::integer) AS habitaciones_disponibles,
            sum((((habitacion.estado)::text = 'OCUPADA'::text))::integer) AS habitaciones_ocupadas,
            sum((((habitacion.estado)::text = 'MANTENIMIENTO'::text))::integer) AS habitaciones_mantenimiento
           FROM public.habitacion
          GROUP BY habitacion.id_hotel
        )
 SELECT hot.id_hotel,
    hot.nombre AS nombre_hotel,
    hot.calificacion,
    hot.direccion,
    hot.niveles_edificios,
    hot.descripcion,
    h.habitaciones_totales,
    h.habitaciones_disponibles,
    h.habitaciones_ocupadas,
    h.habitaciones_mantenimiento,
    COALESCE(pa.ganancia_promedio_anual, 0.00) AS ganancia_promedio_anual,
    COALESCE(pm.ganancia_promedio_mensual, 0.00) AS ganancia_promedio_mensual
   FROM (((public.hotel hot
     LEFT JOIN promedio_anual pa ON ((hot.id_hotel = pa.id_hotel)))
     LEFT JOIN promedio_mensual pm ON ((hot.id_hotel = pm.id_hotel)))
     JOIN habitaciones_hotel h ON ((hot.id_hotel = h.id_hotel)))
  ORDER BY hot.calificacion DESC;


ALTER VIEW public.datos_generales_hoteles OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 31123)
-- Name: descuento; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.descuento (
    id_descuento bigint NOT NULL,
    porcentaje_descuento numeric(5,2) NOT NULL,
    cant_dia_hospedado integer,
    CONSTRAINT ck_cant_dia CHECK ((cant_dia_hospedado > 0)),
    CONSTRAINT ck_porcentaje CHECK (((porcentaje_descuento >= (0)::numeric) AND (porcentaje_descuento <= (100)::numeric)))
);


ALTER TABLE public.descuento OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 31130)
-- Name: descuento_id_descuento_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.descuento ALTER COLUMN id_descuento ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.descuento_id_descuento_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 233 (class 1259 OID 31131)
-- Name: detalle_factura; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.detalle_factura (
    id_detalle_factura bigint NOT NULL,
    id_factura bigint NOT NULL,
    id_servicio bigint,
    id_habitacion bigint,
    id_descuento bigint,
    id_aumento_costo bigint,
    concepto character varying(255) NOT NULL,
    precio_unitario numeric(10,2) NOT NULL,
    cantidad integer NOT NULL,
    subtotal numeric(10,2) NOT NULL,
    monto_descuento numeric(10,2) DEFAULT 0.00,
    monto_aumento numeric(10,2) DEFAULT 0.00,
    precio_total numeric(10,2) NOT NULL,
    CONSTRAINT ck_cantidad CHECK ((cantidad >= 1)),
    CONSTRAINT ck_monto_aumento CHECK ((monto_aumento >= (0)::numeric)),
    CONSTRAINT ck_monto_descuento CHECK ((monto_descuento >= (0)::numeric)),
    CONSTRAINT ck_origen_cobro CHECK ((((id_servicio IS NOT NULL) AND (id_habitacion IS NULL)) OR ((id_servicio IS NULL) AND (id_habitacion IS NOT NULL)))),
    CONSTRAINT ck_precio_total CHECK ((precio_total >= (0)::numeric)),
    CONSTRAINT ck_precio_unitario CHECK ((precio_unitario >= (0)::numeric)),
    CONSTRAINT ck_subtotal CHECK ((subtotal >= (0)::numeric))
);


ALTER TABLE public.detalle_factura OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 31150)
-- Name: detalle_factura_id_detalle_factura_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.detalle_factura ALTER COLUMN id_detalle_factura ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.detalle_factura_id_detalle_factura_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 235 (class 1259 OID 31151)
-- Name: detalle_reservacion_id_detalle_reservacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.detalle_reservacion ALTER COLUMN id_detalle_reservacion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.detalle_reservacion_id_detalle_reservacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 236 (class 1259 OID 31152)
-- Name: empleado; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.empleado (
    id_empleado bigint NOT NULL,
    id_tipo_empleado bigint NOT NULL,
    nombre character varying(255) NOT NULL,
    correo character varying(100) NOT NULL,
    telefono character varying(20),
    dui character varying(10) NOT NULL,
    salario numeric(10,2) NOT NULL,
    CONSTRAINT ck_correo CHECK (((correo)::text ~~ '%@%.%'::text)),
    CONSTRAINT ck_dui CHECK (((dui)::text ~ '^[0-9]{8}-[0-9]{1}$'::text)),
    CONSTRAINT ck_salario CHECK ((salario >= (0)::numeric)),
    CONSTRAINT ck_telefono CHECK (((telefono)::text ~ '^\+503[267][0-9]{7}$'::text))
);


ALTER TABLE public.empleado OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 31165)
-- Name: empleado_id_empleado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.empleado ALTER COLUMN id_empleado ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.empleado_id_empleado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 238 (class 1259 OID 31166)
-- Name: estadia_id_estadia_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.estadia ALTER COLUMN id_estadia ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.estadia_id_estadia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 239 (class 1259 OID 31167)
-- Name: factura_id_factura_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.factura ALTER COLUMN id_factura ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.factura_id_factura_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 240 (class 1259 OID 31168)
-- Name: habitacion_id_habitacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.habitacion ALTER COLUMN id_habitacion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.habitacion_id_habitacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 241 (class 1259 OID 31169)
-- Name: hotel_id_hotel_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.hotel ALTER COLUMN id_hotel ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.hotel_id_hotel_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 242 (class 1259 OID 31170)
-- Name: huesped; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.huesped (
    id_huesped bigint NOT NULL,
    nombre character varying(255) NOT NULL,
    correo character varying(255) NOT NULL,
    telefono character varying(20) NOT NULL,
    documento character varying(50) NOT NULL,
    tipo_documento character varying(50) NOT NULL,
    CONSTRAINT ck_correo CHECK (((correo)::text ~~ '%@%.%'::text)),
    CONSTRAINT ck_telefono_huesped CHECK (((telefono)::text ~ '^\+?[0-9\s\-]{7,20}$'::text)),
    CONSTRAINT ck_tipo_documento CHECK (((tipo_documento)::text = ANY (ARRAY[('DUI'::character varying)::text, ('PASAPORTE'::character varying)::text, ('CONSTANCIA DE RESIDENCIA'::character varying)::text])))
);


ALTER TABLE public.huesped OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 31184)
-- Name: huesped_id_huesped_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.huesped ALTER COLUMN id_huesped ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.huesped_id_huesped_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 244 (class 1259 OID 31185)
-- Name: resenia; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.resenia (
    id_resenia bigint NOT NULL,
    id_estadia bigint NOT NULL,
    id_huesped bigint NOT NULL,
    calificacion numeric(2,1),
    comentario text,
    CONSTRAINT ck_calificacion CHECK (((calificacion >= (1)::numeric) AND (calificacion <= (5)::numeric)))
);


ALTER TABLE public.resenia OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 31194)
-- Name: resenia_id_resenia_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.resenia ALTER COLUMN id_resenia ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.resenia_id_resenia_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 246 (class 1259 OID 31195)
-- Name: reservacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.reservacion (
    id_reservacion bigint NOT NULL,
    id_empleado bigint NOT NULL,
    id_huesped bigint NOT NULL,
    cant_huespedes_totales integer NOT NULL,
    estado character varying(50) NOT NULL,
    CONSTRAINT ck_cant_huepedes CHECK ((cant_huespedes_totales > 0)),
    CONSTRAINT ck_estado CHECK (((estado)::text = ANY (ARRAY[('PENDIENTE'::character varying)::text, ('CONFIRMADA'::character varying)::text, ('CANCELADA'::character varying)::text, ('RECHAZADA'::character varying)::text, ('COMPLETADA'::character varying)::text])))
);


ALTER TABLE public.reservacion OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 31205)
-- Name: reservacion_id_reservacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.reservacion ALTER COLUMN id_reservacion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.reservacion_id_reservacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 248 (class 1259 OID 31206)
-- Name: servicio; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.servicio (
    id_servicio bigint NOT NULL,
    tipo_servicio character varying(100) NOT NULL,
    precio numeric(10,2) NOT NULL,
    CONSTRAINT ck_precio CHECK ((precio >= (0)::numeric))
);


ALTER TABLE public.servicio OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 31213)
-- Name: servicio_id_servicio_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.servicio ALTER COLUMN id_servicio ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.servicio_id_servicio_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 250 (class 1259 OID 31214)
-- Name: tipo_habitacion; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_habitacion (
    id_tipo_habitacion bigint NOT NULL,
    tipo_habitacion character varying(100) NOT NULL
);


ALTER TABLE public.tipo_habitacion OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 31219)
-- Name: servicios_mas_consumidos_tipo_habitacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.servicios_mas_consumidos_tipo_habitacion AS
 SELECT th.id_tipo_habitacion,
    th.tipo_habitacion,
    s.id_servicio,
    s.tipo_servicio,
    sum(df_serv.cantidad) AS total_consumos
   FROM ((((((public.detalle_factura df_serv
     JOIN public.servicio s ON ((df_serv.id_servicio = s.id_servicio)))
     JOIN public.factura f ON ((df_serv.id_factura = f.id_factura)))
     JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
     JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
     JOIN public.habitacion h ON ((dr.id_habitacion = h.id_habitacion)))
     JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
  GROUP BY th.id_tipo_habitacion, th.tipo_habitacion, s.id_servicio, s.tipo_servicio
  ORDER BY th.tipo_habitacion, (sum(df_serv.cantidad)) DESC;


ALTER VIEW public.servicios_mas_consumidos_tipo_habitacion OWNER TO postgres;

--
-- TOC entry 252 (class 1259 OID 31224)
-- Name: tipo_comodidad; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_comodidad (
    id_tipo_comodidad bigint NOT NULL,
    tipo_comodidad character varying(100) NOT NULL
);


ALTER TABLE public.tipo_comodidad OWNER TO postgres;

--
-- TOC entry 253 (class 1259 OID 31229)
-- Name: tipo_comodidad_id_tipo_comodidad_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_comodidad ALTER COLUMN id_tipo_comodidad ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tipo_comodidad_id_tipo_comodidad_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 254 (class 1259 OID 31230)
-- Name: tipo_empleado; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.tipo_empleado (
    id_tipo_empleado bigint NOT NULL,
    tipo_empleado character varying(100) NOT NULL
);


ALTER TABLE public.tipo_empleado OWNER TO postgres;

--
-- TOC entry 255 (class 1259 OID 31235)
-- Name: tipo_empleado_id_tipo_empleado_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_empleado ALTER COLUMN id_tipo_empleado ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tipo_empleado_id_tipo_empleado_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 256 (class 1259 OID 31236)
-- Name: tipo_habitacion_id_tipo_habitacion_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.tipo_habitacion ALTER COLUMN id_tipo_habitacion ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.tipo_habitacion_id_tipo_habitacion_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- TOC entry 276 (class 1259 OID 31517)
-- Name: v_consumo_estadia; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_consumo_estadia AS
 SELECT e.id_estadia,
    h.nombre,
    h.documento,
    json_build_object('habitaciones', ( SELECT json_agg(json_build_object('numero_habitacion', h2.numero_habitacion, 'consumos', ( SELECT COALESCE(json_agg(json_build_object('servicio', s.tipo_servicio, 'precio', s.precio)), '[]'::json) AS "coalesce"
                   FROM (public.consumo_servicio cs
                     JOIN public.servicio s ON ((cs.id_servicio = s.id_servicio)))
                  WHERE ((cs.id_estadia = e.id_estadia) AND (cs.id_habitacion = h2.id_habitacion))))) AS json_agg
           FROM (public.detalle_reservacion dr
             JOIN public.habitacion h2 ON ((dr.id_habitacion = h2.id_habitacion)))
          WHERE (dr.id_reservacion = r.id_reservacion)), 'gasto_total', f.total_a_pagar) AS reporte_json
   FROM (((public.estadia e
     JOIN public.reservacion r ON ((e.id_reservacion = r.id_reservacion)))
     JOIN public.huesped h ON ((r.id_huesped = h.id_huesped)))
     LEFT JOIN public.factura f ON ((e.id_estadia = f.id_estadia)));


ALTER VIEW public.v_consumo_estadia OWNER TO postgres;

--
-- TOC entry 266 (class 1259 OID 31468)
-- Name: v_datos_generales_hoteles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_datos_generales_hoteles AS
 WITH ganancia_por_anio AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            sum(f.total_a_pagar) AS total_del_anio
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha))
        ), promedio_anual AS (
         SELECT ganancia_por_anio.id_hotel,
            round(avg(ganancia_por_anio.total_del_anio), 2) AS ganancia_promedio_anual
           FROM ganancia_por_anio
          GROUP BY ganancia_por_anio.id_hotel
        ), ganancia_por_mes AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            EXTRACT(month FROM f.fecha) AS mes,
            sum(f.total_a_pagar) AS total_del_mes
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha)), (EXTRACT(month FROM f.fecha))
        ), promedio_mensual AS (
         SELECT ganancia_por_mes.id_hotel,
            round(avg(ganancia_por_mes.total_del_mes), 2) AS ganancia_promedio_mensual
           FROM ganancia_por_mes
          GROUP BY ganancia_por_mes.id_hotel
        ), habitaciones_hotel AS (
         SELECT habitacion.id_hotel,
            count(*) AS habitaciones_totales,
            sum((((habitacion.estado)::text = 'DISPONIBLE'::text))::integer) AS habitaciones_disponibles,
            sum((((habitacion.estado)::text = 'OCUPADA'::text))::integer) AS habitaciones_ocupadas,
            sum((((habitacion.estado)::text = 'MANTENIMIENTO'::text))::integer) AS habitaciones_mantenimiento
           FROM public.habitacion
          GROUP BY habitacion.id_hotel
        )
 SELECT hot.id_hotel,
    hot.nombre AS nombre_hotel,
    hot.calificacion,
    hot.direccion,
    hot.niveles_edificios,
    hot.descripcion,
    h.habitaciones_totales,
    h.habitaciones_disponibles,
    h.habitaciones_ocupadas,
    h.habitaciones_mantenimiento,
    COALESCE(pa.ganancia_promedio_anual, 0.00) AS ganancia_promedio_anual,
    COALESCE(pm.ganancia_promedio_mensual, 0.00) AS ganancia_promedio_mensual
   FROM (((public.hotel hot
     LEFT JOIN promedio_anual pa ON ((hot.id_hotel = pa.id_hotel)))
     LEFT JOIN promedio_mensual pm ON ((hot.id_hotel = pm.id_hotel)))
     JOIN habitaciones_hotel h ON ((hot.id_hotel = h.id_hotel)))
  ORDER BY hot.calificacion DESC;


ALTER VIEW public.v_datos_generales_hoteles OWNER TO postgres;

--
-- TOC entry 274 (class 1259 OID 31507)
-- Name: v_detalle_habitaciones_y_comodidades; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_detalle_habitaciones_y_comodidades AS
 SELECT h.id_habitacion,
    h.numero_habitacion,
    h.precio,
    h.estado,
    h.capacidad_maxima,
    th.tipo_habitacion,
    ( SELECT count(*) AS count
           FROM public.habitacion h2
          WHERE (h2.id_tipo_habitacion = th.id_tipo_habitacion)) AS total_habitaciones_este_tipo,
    string_agg(DISTINCT (tc.tipo_comodidad)::text, ', '::text) AS comodidades,
    count(DISTINCT tc.id_tipo_comodidad) AS total_comodidades
   FROM (((public.habitacion h
     JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
     LEFT JOIN public.comodidad_tipo_habitacion cth ON ((th.id_tipo_habitacion = cth.id_tipo_habitacion)))
     LEFT JOIN public.tipo_comodidad tc ON ((cth.id_tipo_comodidad = tc.id_tipo_comodidad)))
  GROUP BY h.id_habitacion, h.numero_habitacion, h.nivel, h.precio, h.estado, h.capacidad_maxima, th.id_tipo_habitacion, th.tipo_habitacion
  ORDER BY th.tipo_habitacion, h.numero_habitacion;


ALTER VIEW public.v_detalle_habitaciones_y_comodidades OWNER TO postgres;

--
-- TOC entry 273 (class 1259 OID 31502)
-- Name: v_dias_restantes_reservacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_dias_restantes_reservacion AS
 SELECT r.id_reservacion,
    h.nombre AS nombre_huesped,
    h.documento AS documento_huesped,
    h.telefono AS telefono_huesped,
    e.nombre AS nombre_empleado,
    r.cant_huespedes_totales,
    r.estado AS estado_reservacion,
    min(dr.fecha_entrada) AS fecha_entrada_proxima,
    min(dr.fecha_salida) AS fecha_salida_proxima,
    (min(dr.fecha_entrada) - CURRENT_DATE) AS dias_para_iniciar
   FROM (((public.reservacion r
     JOIN public.huesped h ON ((r.id_huesped = h.id_huesped)))
     JOIN public.empleado e ON ((r.id_empleado = e.id_empleado)))
     JOIN public.detalle_reservacion dr ON ((r.id_reservacion = dr.id_reservacion)))
  WHERE (((r.estado)::text = ANY ((ARRAY['PENDIENTE'::character varying, 'CONFIRMADA'::character varying])::text[])) AND (dr.fecha_entrada >= CURRENT_DATE))
  GROUP BY r.id_reservacion, h.nombre, h.documento, h.telefono, e.nombre, r.cant_huespedes_totales, r.estado
  ORDER BY (min(dr.fecha_entrada) - CURRENT_DATE);


ALTER VIEW public.v_dias_restantes_reservacion OWNER TO postgres;

--
-- TOC entry 267 (class 1259 OID 31473)
-- Name: v_factura_completa; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_factura_completa AS
 SELECT f.id_factura,
    f.fecha,
    f.metodo_pago,
    f.total_a_pagar,
    f.id_estadia,
    e.nombre AS nombre_empleado,
    h.nombre AS nombre_huesped,
    h.correo AS correo_huesped,
    h.id_huesped,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('id_detalle_factura', df.id_detalle_factura, 'concepto', df.concepto, 'precio_unitario', df.precio_unitario, 'cantidad', df.cantidad, 'subtotal', df.subtotal, 'monto_descuento', df.monto_descuento, 'monto_aumento', df.monto_aumento, 'precio_total', df.precio_total, 'servicio',
                CASE
                    WHEN (df.id_servicio IS NOT NULL) THEN jsonb_build_object('id_servicio', s.id_servicio, 'tipo_servicio', s.tipo_servicio)
                    ELSE NULL::jsonb
                END, 'habitacion',
                CASE
                    WHEN (df.id_habitacion IS NOT NULL) THEN jsonb_build_object('id_habitacion', hab.id_habitacion, 'numero', hab.numero_habitacion, 'nivel', hab.nivel)
                    ELSE NULL::jsonb
                END, 'descuento',
                CASE
                    WHEN (df.id_descuento IS NOT NULL) THEN jsonb_build_object('id_descuento', d.id_descuento, 'porcentaje', d.porcentaje_descuento)
                    ELSE NULL::jsonb
                END, 'aumento_costo',
                CASE
                    WHEN (df.id_aumento_costo IS NOT NULL) THEN jsonb_build_object('id_aumento_costo', ac.id_aumento_costo, 'temporada', ac.nombre_temporada, 'porcentaje', ac.porcentaje_aumento)
                    ELSE NULL::jsonb
                END)) AS jsonb_agg
           FROM ((((public.detalle_factura df
             LEFT JOIN public.servicio s ON ((df.id_servicio = s.id_servicio)))
             LEFT JOIN public.habitacion hab ON ((df.id_habitacion = hab.id_habitacion)))
             LEFT JOIN public.descuento d ON ((df.id_descuento = d.id_descuento)))
             LEFT JOIN public.aumento_costos ac ON ((df.id_aumento_costo = ac.id_aumento_costo)))
          WHERE (df.id_factura = f.id_factura)), '[]'::jsonb) AS detalle_factura
   FROM ((((public.factura f
     JOIN public.estadia es ON ((es.id_estadia = f.id_estadia)))
     JOIN public.reservacion r ON ((r.id_reservacion = es.id_reservacion)))
     JOIN public.empleado e ON ((e.id_empleado = r.id_empleado)))
     JOIN public.huesped h ON ((h.id_huesped = r.id_huesped)));


ALTER VIEW public.v_factura_completa OWNER TO postgres;

--
-- TOC entry 271 (class 1259 OID 31492)
-- Name: v_gasto_historica; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_gasto_historica AS
 SELECT h.id_huesped,
    h.nombre AS huesped,
    h.correo,
    h.documento,
    h.tipo_documento,
    sum(f.total_a_pagar) AS gasto_total,
    count(f.id_factura) AS cantidad_facturas
   FROM (public.huesped h
     JOIN public.factura f ON ((h.id_huesped = f.id_huesped)))
  GROUP BY h.id_huesped, h.nombre, h.correo, h.documento, h.tipo_documento
  ORDER BY (sum(f.total_a_pagar)) DESC;


ALTER VIEW public.v_gasto_historica OWNER TO postgres;

--
-- TOC entry 270 (class 1259 OID 31487)
-- Name: v_habitaciones_disponibles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_habitaciones_disponibles AS
 SELECT h.id_habitacion,
    ho.nombre AS hotel,
    ho.direccion,
    h.nivel,
    h.numero_habitacion,
    th.tipo_habitacion,
    h.precio,
    h.estado,
    h.capacidad_maxima
   FROM ((public.habitacion h
     JOIN public.hotel ho ON ((h.id_hotel = ho.id_hotel)))
     JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
  WHERE ((h.estado)::text = 'DISPONIBLE'::text);


ALTER VIEW public.v_habitaciones_disponibles OWNER TO postgres;

--
-- TOC entry 265 (class 1259 OID 31463)
-- Name: v_huespedes_por_hotel; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_huespedes_por_hotel AS
 SELECT h.id_huesped,
    h.nombre AS huesped,
    h.correo,
    h.documento,
    h.tipo_documento,
    hot.nombre AS nombre_hotel,
    count(DISTINCT f.id_factura) AS veces_hospedado
   FROM (((((public.huesped h
     JOIN public.factura f ON ((h.id_huesped = f.id_huesped)))
     JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
     JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
     JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
     JOIN public.hotel hot ON ((hab.id_hotel = hot.id_hotel)))
  GROUP BY h.id_huesped, h.nombre, h.correo, h.documento, h.tipo_documento, hot.nombre;


ALTER VIEW public.v_huespedes_por_hotel OWNER TO postgres;

--
-- TOC entry 269 (class 1259 OID 31482)
-- Name: v_info_general_hoteles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_info_general_hoteles AS
SELECT
    NULL::character varying(255) AS hotel,
    NULL::numeric(2,1) AS calificacion,
    NULL::bigint AS cant_habitaciones,
    NULL::numeric AS ganancias;


ALTER VIEW public.v_info_general_hoteles OWNER TO postgres;

--
-- TOC entry 268 (class 1259 OID 31478)
-- Name: v_ingresos_mes; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ingresos_mes AS
 SELECT EXTRACT(year FROM fecha) AS anio,
    EXTRACT(month FROM fecha) AS num_mes,
    to_char(fecha, 'Month'::text) AS mes,
    sum(total_a_pagar) AS ingresos
   FROM public.factura f
  GROUP BY (EXTRACT(year FROM fecha)), (EXTRACT(month FROM fecha)), (to_char(fecha, 'Month'::text))
  ORDER BY (EXTRACT(year FROM fecha)) DESC, (EXTRACT(month FROM fecha));


ALTER VIEW public.v_ingresos_mes OWNER TO postgres;

--
-- TOC entry 272 (class 1259 OID 31497)
-- Name: v_servicios_mas_consumidos_tipo_habitacion; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_servicios_mas_consumidos_tipo_habitacion AS
 SELECT th.id_tipo_habitacion,
    th.tipo_habitacion,
    s.id_servicio,
    s.tipo_servicio,
    sum(df_serv.cantidad) AS total_consumos
   FROM ((((((public.detalle_factura df_serv
     JOIN public.servicio s ON ((df_serv.id_servicio = s.id_servicio)))
     JOIN public.factura f ON ((df_serv.id_factura = f.id_factura)))
     JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
     JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
     JOIN public.habitacion h ON ((dr.id_habitacion = h.id_habitacion)))
     JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
  GROUP BY th.id_tipo_habitacion, th.tipo_habitacion, s.id_servicio, s.tipo_servicio
  ORDER BY th.tipo_habitacion, (sum(df_serv.cantidad)) DESC;


ALTER VIEW public.v_servicios_mas_consumidos_tipo_habitacion OWNER TO postgres;

--
-- TOC entry 264 (class 1259 OID 31458)
-- Name: v_tasa_ocupacion_mensual; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_tasa_ocupacion_mensual AS
 WITH dias_ocupados AS (
         SELECT dr.id_habitacion,
            h.id_tipo_habitacion,
            th.tipo_habitacion,
            (generate_series(((e.checkin)::date)::timestamp with time zone, (((COALESCE(e.checkout, (dr.fecha_salida)::timestamp without time zone) - '1 day'::interval))::date)::timestamp with time zone, '1 day'::interval))::date AS fecha_ocupada
           FROM ((((public.detalle_reservacion dr
             JOIN public.reservacion r ON ((dr.id_reservacion = r.id_reservacion)))
             JOIN public.estadia e ON ((r.id_reservacion = e.id_reservacion)))
             JOIN public.habitacion h ON ((dr.id_habitacion = h.id_habitacion)))
             JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
          WHERE ((r.estado)::text = 'CONFIRMADA'::text)
        ), ocupacion_agrupada AS (
         SELECT dias_ocupados.id_tipo_habitacion,
            dias_ocupados.tipo_habitacion,
            to_char((dias_ocupados.fecha_ocupada)::timestamp with time zone, 'YYYY-MM'::text) AS mes_anio,
            (date_trunc('month'::text, (dias_ocupados.fecha_ocupada)::timestamp with time zone))::date AS fecha_base_mes,
            count(dias_ocupados.id_habitacion) AS total_dias_ocupados
           FROM dias_ocupados
          GROUP BY dias_ocupados.id_tipo_habitacion, dias_ocupados.tipo_habitacion, (to_char((dias_ocupados.fecha_ocupada)::timestamp with time zone, 'YYYY-MM'::text)), (date_trunc('month'::text, (dias_ocupados.fecha_ocupada)::timestamp with time zone))
        ), capacidad_habitaciones AS (
         SELECT habitacion.id_tipo_habitacion,
            count(habitacion.id_habitacion) AS cantidad_habitaciones
           FROM public.habitacion
          GROUP BY habitacion.id_tipo_habitacion
        )
 SELECT oa.mes_anio AS mes,
    oa.tipo_habitacion,
    oa.total_dias_ocupados,
    (((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval))))::integer AS total_dias_disponibles,
    to_char((((oa.total_dias_ocupados)::numeric / ((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval)))) * (100)::numeric), 'FM990.00"%"'::text) AS porcentaje_ocupacion
   FROM (ocupacion_agrupada oa
     JOIN capacidad_habitaciones ch ON ((oa.id_tipo_habitacion = ch.id_tipo_habitacion)))
  ORDER BY oa.mes_anio DESC, (to_char((((oa.total_dias_ocupados)::numeric / ((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval)))) * (100)::numeric), 'FM990.00"%"'::text)) DESC;


ALTER VIEW public.v_tasa_ocupacion_mensual OWNER TO postgres;

--
-- TOC entry 275 (class 1259 OID 31512)
-- Name: v_total_habitaciones_por_tipo; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_total_habitaciones_por_tipo AS
 SELECT th.tipo_habitacion,
    count(h.id_habitacion) AS total_habitaciones
   FROM (public.tipo_habitacion th
     LEFT JOIN public.habitacion h ON ((th.id_tipo_habitacion = h.id_tipo_habitacion)))
  GROUP BY th.id_tipo_habitacion, th.tipo_habitacion
  ORDER BY (count(h.id_habitacion)) DESC;


ALTER VIEW public.v_total_habitaciones_por_tipo OWNER TO postgres;

--
-- TOC entry 257 (class 1259 OID 31237)
-- Name: vista_calificacion_y_ganancias_prom; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_calificacion_y_ganancias_prom AS
 WITH ganancia_por_anio AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            sum(f.total_a_pagar) AS total_del_anio
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha))
        ), promedio_anual AS (
         SELECT ganancia_por_anio.id_hotel,
            round(avg(ganancia_por_anio.total_del_anio), 2) AS ganancia_promedio_anual
           FROM ganancia_por_anio
          GROUP BY ganancia_por_anio.id_hotel
        ), ganancia_por_mes AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            EXTRACT(month FROM f.fecha) AS mes,
            sum(f.total_a_pagar) AS total_del_mes
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha)), (EXTRACT(month FROM f.fecha))
        ), promedio_mensual AS (
         SELECT ganancia_por_mes.id_hotel,
            round(avg(ganancia_por_mes.total_del_mes), 2) AS ganancia_promedio_mensual
           FROM ganancia_por_mes
          GROUP BY ganancia_por_mes.id_hotel
        ), promedio_calificacion AS (
         SELECT hab.id_hotel,
            round(avg(r.calificacion), 2) AS calificacion_promedio_hotel
           FROM (((public.resenia r
             JOIN public.estadia est ON ((r.id_estadia = est.id_estadia)))
             JOIN public.detalle_reservacion det ON ((est.id_reservacion = det.id_reservacion)))
             JOIN public.habitacion hab ON ((det.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel
        )
 SELECT hot.id_hotel,
    hot.nombre AS nombre_hotel,
    COALESCE(pc.calificacion_promedio_hotel, 0.00) AS calificacion_promedio_hotel,
    COALESCE(pa.ganancia_promedio_anual, 0.00) AS ganancia_promedio_anual,
    COALESCE(pm.ganancia_promedio_mensual, 0.00) AS ganancia_promedio_mensual
   FROM (((public.hotel hot
     LEFT JOIN promedio_anual pa ON ((hot.id_hotel = pa.id_hotel)))
     LEFT JOIN promedio_mensual pm ON ((hot.id_hotel = pm.id_hotel)))
     LEFT JOIN promedio_calificacion pc ON ((hot.id_hotel = pc.id_hotel)));


ALTER VIEW public.vista_calificacion_y_ganancias_prom OWNER TO postgres;

--
-- TOC entry 277 (class 1259 OID 31522)
-- Name: vista_empleados; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_empleados AS
 SELECT e.nombre AS empleado,
    e.dui AS documento_de_identidad,
    e.telefono AS "teléfono",
    e.correo AS email,
    te.tipo_empleado AS rol_de_trabajo,
    e.salario
   FROM (public.empleado e
     JOIN public.tipo_empleado te ON ((e.id_tipo_empleado = te.id_tipo_empleado)));


ALTER VIEW public.vista_empleados OWNER TO postgres;

--
-- TOC entry 258 (class 1259 OID 31242)
-- Name: vista_factura_completa; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_factura_completa AS
 SELECT f.id_factura,
    f.fecha,
    f.metodo_pago,
    f.total_a_pagar,
    f.id_estadia,
    e.nombre AS nombre_empleado,
    h.nombre AS nombre_huesped,
    h.correo AS correo_huesped,
    COALESCE(( SELECT jsonb_agg(jsonb_build_object('id_detalle_factura', df.id_detalle_factura, 'concepto', df.concepto, 'precio_unitario', df.precio_unitario, 'cantidad', df.cantidad, 'subtotal', df.subtotal, 'monto_descuento', df.monto_descuento, 'monto_aumento', df.monto_aumento, 'precio_total', df.precio_total, 'servicio',
                CASE
                    WHEN (df.id_servicio IS NOT NULL) THEN jsonb_build_object('id_servicio', s.id_servicio, 'tipo_servicio', s.tipo_servicio)
                    ELSE NULL::jsonb
                END, 'habitacion',
                CASE
                    WHEN (df.id_habitacion IS NOT NULL) THEN jsonb_build_object('id_habitacion', hab.id_habitacion, 'numero', hab.numero_habitacion, 'nivel', hab.nivel)
                    ELSE NULL::jsonb
                END, 'descuento',
                CASE
                    WHEN (df.id_descuento IS NOT NULL) THEN jsonb_build_object('id_descuento', d.id_descuento, 'porcentaje', d.porcentaje_descuento)
                    ELSE NULL::jsonb
                END, 'aumento_costo',
                CASE
                    WHEN (df.id_aumento_costo IS NOT NULL) THEN jsonb_build_object('id_aumento_costo', ac.id_aumento_costo, 'temporada', ac.nombre_temporada, 'porcentaje', ac.porcentaje_aumento)
                    ELSE NULL::jsonb
                END)) AS jsonb_agg
           FROM ((((public.detalle_factura df
             LEFT JOIN public.servicio s ON ((df.id_servicio = s.id_servicio)))
             LEFT JOIN public.habitacion hab ON ((df.id_habitacion = hab.id_habitacion)))
             LEFT JOIN public.descuento d ON ((df.id_descuento = d.id_descuento)))
             LEFT JOIN public.aumento_costos ac ON ((df.id_aumento_costo = ac.id_aumento_costo)))
          WHERE (df.id_factura = f.id_factura)), '[]'::jsonb) AS detalle_factura
   FROM ((((public.factura f
     JOIN public.estadia es ON ((es.id_estadia = f.id_estadia)))
     JOIN public.reservacion r ON ((r.id_reservacion = es.id_reservacion)))
     JOIN public.empleado e ON ((e.id_empleado = r.id_empleado)))
     JOIN public.huesped h ON ((h.id_huesped = r.id_huesped)));


ALTER VIEW public.vista_factura_completa OWNER TO postgres;

--
-- TOC entry 259 (class 1259 OID 31247)
-- Name: vista_gasto_historica; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_gasto_historica AS
 SELECT h.id_huesped,
    h.nombre AS huesped,
    h.correo,
    h.documento,
    h.tipo_documento,
    sum(f.total_a_pagar) AS gasto_total,
    count(f.id_factura) AS cantidad_facturas
   FROM (public.huesped h
     JOIN public.factura f ON ((h.id_huesped = f.id_huesped)))
  GROUP BY h.id_huesped, h.nombre, h.correo, h.documento, h.tipo_documento
  ORDER BY (sum(f.total_a_pagar)) DESC;


ALTER VIEW public.vista_gasto_historica OWNER TO postgres;

--
-- TOC entry 260 (class 1259 OID 31252)
-- Name: vista_habitaciones_disponibles; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_habitaciones_disponibles AS
 SELECT h.id_habitacion,
    ho.nombre AS hotel,
    ho.direccion,
    h.nivel,
    h.numero_habitacion,
    th.tipo_habitacion,
    h.precio,
    h.estado,
    h.capacidad_maxima
   FROM ((public.habitacion h
     JOIN public.hotel ho ON ((h.id_hotel = ho.id_hotel)))
     JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
  WHERE ((h.estado)::text = 'DISPONIBLE'::text);


ALTER VIEW public.vista_habitaciones_disponibles OWNER TO postgres;

--
-- TOC entry 261 (class 1259 OID 31257)
-- Name: vista_resenias_y_ganancias; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_resenias_y_ganancias AS
 WITH ganancia_por_anio AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            sum(f.total_a_pagar) AS total_del_anio
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha))
        ), promedio_anual AS (
         SELECT ganancia_por_anio.id_hotel,
            round(avg(ganancia_por_anio.total_del_anio), 2) AS ganancia_promedio_anual
           FROM ganancia_por_anio
          GROUP BY ganancia_por_anio.id_hotel
        ), ganancia_por_mes AS (
         SELECT hab.id_hotel,
            EXTRACT(year FROM f.fecha) AS anio,
            EXTRACT(month FROM f.fecha) AS mes,
            sum(f.total_a_pagar) AS total_del_mes
           FROM (((public.factura f
             JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
             JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
             JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel, (EXTRACT(year FROM f.fecha)), (EXTRACT(month FROM f.fecha))
        ), promedio_mensual AS (
         SELECT ganancia_por_mes.id_hotel,
            round(avg(ganancia_por_mes.total_del_mes), 2) AS ganancia_promedio_mensual
           FROM ganancia_por_mes
          GROUP BY ganancia_por_mes.id_hotel
        ), promedio_calificacion AS (
         SELECT hab.id_hotel,
            round(avg(r.calificacion), 2) AS calificacion_promedio_hotel
           FROM (((public.resenia r
             JOIN public.estadia est ON ((r.id_estadia = est.id_estadia)))
             JOIN public.detalle_reservacion det ON ((est.id_reservacion = det.id_reservacion)))
             JOIN public.habitacion hab ON ((det.id_habitacion = hab.id_habitacion)))
          GROUP BY hab.id_hotel
        )
 SELECT hot.id_hotel,
    hot.nombre AS nombre_hotel,
    COALESCE(pc.calificacion_promedio_hotel, 0.00) AS calificacion_promedio_hotel,
    COALESCE(pa.ganancia_promedio_anual, 0.00) AS ganancia_promedio_anual,
    COALESCE(pm.ganancia_promedio_mensual, 0.00) AS ganancia_promedio_mensual
   FROM (((public.hotel hot
     LEFT JOIN promedio_anual pa ON ((hot.id_hotel = pa.id_hotel)))
     LEFT JOIN promedio_mensual pm ON ((hot.id_hotel = pm.id_hotel)))
     LEFT JOIN promedio_calificacion pc ON ((hot.id_hotel = pc.id_hotel)));


ALTER VIEW public.vista_resenias_y_ganancias OWNER TO postgres;

--
-- TOC entry 262 (class 1259 OID 31262)
-- Name: vista_tasa_ocupacion_mensual; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vista_tasa_ocupacion_mensual AS
 WITH dias_ocupados AS (
         SELECT dr.id_habitacion,
            h.id_tipo_habitacion,
            th.tipo_habitacion,
            (generate_series(((e.checkin)::date)::timestamp with time zone, (((COALESCE(e.checkout, (dr.fecha_salida)::timestamp without time zone) - '1 day'::interval))::date)::timestamp with time zone, '1 day'::interval))::date AS fecha_ocupada
           FROM ((((public.detalle_reservacion dr
             JOIN public.reservacion r ON ((dr.id_reservacion = r.id_reservacion)))
             JOIN public.estadia e ON ((r.id_reservacion = e.id_reservacion)))
             JOIN public.habitacion h ON ((dr.id_habitacion = h.id_habitacion)))
             JOIN public.tipo_habitacion th ON ((h.id_tipo_habitacion = th.id_tipo_habitacion)))
          WHERE ((r.estado)::text = 'CONFIRMADA'::text)
        ), ocupacion_agrupada AS (
         SELECT dias_ocupados.id_tipo_habitacion,
            dias_ocupados.tipo_habitacion,
            to_char((dias_ocupados.fecha_ocupada)::timestamp with time zone, 'YYYY-MM'::text) AS mes_anio,
            (date_trunc('month'::text, (dias_ocupados.fecha_ocupada)::timestamp with time zone))::date AS fecha_base_mes,
            count(dias_ocupados.id_habitacion) AS total_dias_ocupados
           FROM dias_ocupados
          GROUP BY dias_ocupados.id_tipo_habitacion, dias_ocupados.tipo_habitacion, (to_char((dias_ocupados.fecha_ocupada)::timestamp with time zone, 'YYYY-MM'::text)), (date_trunc('month'::text, (dias_ocupados.fecha_ocupada)::timestamp with time zone))
        ), capacidad_habitaciones AS (
         SELECT habitacion.id_tipo_habitacion,
            count(habitacion.id_habitacion) AS cantidad_habitaciones
           FROM public.habitacion
          GROUP BY habitacion.id_tipo_habitacion
        )
 SELECT oa.mes_anio AS mes,
    oa.tipo_habitacion,
    oa.total_dias_ocupados,
    (((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval))))::integer AS total_dias_disponibles,
    to_char((((oa.total_dias_ocupados)::numeric / ((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval)))) * (100)::numeric), 'FM990.00"%"'::text) AS porcentaje_ocupacion
   FROM (ocupacion_agrupada oa
     JOIN capacidad_habitaciones ch ON ((oa.id_tipo_habitacion = ch.id_tipo_habitacion)))
  ORDER BY oa.mes_anio DESC, (to_char((((oa.total_dias_ocupados)::numeric / ((ch.cantidad_habitaciones)::numeric * EXTRACT(day FROM ((oa.fecha_base_mes + '1 mon'::interval) - '1 day'::interval)))) * (100)::numeric), 'FM990.00"%"'::text)) DESC;


ALTER VIEW public.vista_tasa_ocupacion_mensual OWNER TO postgres;

--
-- TOC entry 263 (class 1259 OID 31267)
-- Name: vistas_huespuedes; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vistas_huespuedes AS
 SELECT h.id_huesped,
    h.nombre AS huesped,
    h.correo,
    h.documento,
    h.tipo_documento,
    hot.nombre AS nombre_hotel,
    count(DISTINCT f.id_factura) AS veces_hospedado
   FROM (((((public.huesped h
     JOIN public.factura f ON ((h.id_huesped = f.id_huesped)))
     JOIN public.estadia e ON ((f.id_estadia = e.id_estadia)))
     JOIN public.detalle_reservacion dr ON ((e.id_reservacion = dr.id_reservacion)))
     JOIN public.habitacion hab ON ((dr.id_habitacion = hab.id_habitacion)))
     JOIN public.hotel hot ON ((hab.id_hotel = hot.id_hotel)))
  GROUP BY h.id_huesped, h.nombre, h.correo, h.documento, h.tipo_documento, hot.nombre
  ORDER BY hot.nombre DESC, (count(DISTINCT f.id_factura)) DESC;


ALTER VIEW public.vistas_huespuedes OWNER TO postgres;

--
-- TOC entry 5340 (class 0 OID 31027)
-- Dependencies: 219
-- Data for Name: aumento_costos; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.aumento_costos (id_aumento_costo, porcentaje_aumento, fecha_inicio, fecha_fin, nombre_temporada, activado) FROM stdin;
1	10.00	2026-12-15	2027-01-05	Navidad 2026	t
2	15.00	2026-03-25	2026-04-05	Semana Santa 2026	t
3	5.00	2026-08-01	2026-08-07	Agostinas 2026	t
4	20.00	2027-12-15	2028-01-05	Navidad 2027	f
5	15.00	2027-03-20	2027-03-30	Semana Santa 2027	f
6	5.00	2027-08-01	2027-08-07	Agostinas 2027	f
7	8.00	2026-11-01	2026-11-03	D??a de Muertos 2026	t
8	12.00	2026-09-14	2026-09-16	Independencia 2026	t
9	10.00	2026-05-01	2026-05-03	D??a del Trabajo 2026	t
10	25.00	2026-12-30	2027-01-02	Fin de A??o 2026	t
\.


--
-- TOC entry 5342 (class 0 OID 31038)
-- Dependencies: 221
-- Data for Name: comodidad_tipo_habitacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.comodidad_tipo_habitacion (id_comodidad_habitacion, id_tipo_habitacion, id_tipo_comodidad, detalle) FROM stdin;
1	7	1	Disponible bajo petici??n
2	8	7	Incluido en la tarifa
3	6	8	Disponible bajo petici??n
4	7	4	Mantenimiento mensual
5	4	3	Incluido en la tarifa
6	9	4	Mantenimiento mensual
7	1	1	Incluido en la tarifa
8	1	10	Disponible bajo petici??n
9	9	10	Mantenimiento mensual
10	4	8	Disponible bajo petici??n
11	10	4	Requiere activaci??n previa
12	3	8	Incluido en la tarifa
13	9	4	Disponible bajo petici??n
14	6	8	Requiere activaci??n previa
15	8	3	Mantenimiento mensual
16	6	5	Disponible bajo petici??n
17	1	8	Requiere activaci??n previa
18	5	5	Incluido en la tarifa
19	3	10	Disponible bajo petici??n
20	9	10	Mantenimiento mensual
21	5	7	Incluido en la tarifa
22	3	1	Requiere activaci??n previa
23	4	1	Disponible bajo petici??n
24	2	5	Mantenimiento mensual
25	3	3	Disponible bajo petici??n
26	6	6	Incluido en la tarifa
27	9	9	Incluido en la tarifa
28	2	1	Mantenimiento mensual
29	3	1	Incluido en la tarifa
30	4	5	Requiere activaci??n previa
31	3	7	Requiere activaci??n previa
32	5	10	Mantenimiento mensual
33	9	10	Disponible bajo petici??n
34	7	2	Mantenimiento mensual
35	9	6	Disponible bajo petici??n
36	6	3	Disponible bajo petici??n
37	8	5	Incluido en la tarifa
38	1	1	Disponible bajo petici??n
39	4	10	Requiere activaci??n previa
40	7	5	Incluido en la tarifa
41	6	7	Incluido en la tarifa
42	9	1	Mantenimiento mensual
43	3	10	Mantenimiento mensual
44	5	10	Incluido en la tarifa
45	10	1	Incluido en la tarifa
46	6	8	Incluido en la tarifa
47	5	1	Incluido en la tarifa
48	6	9	Incluido en la tarifa
49	6	5	Disponible bajo petici??n
50	3	3	Mantenimiento mensual
51	8	7	Disponible bajo petici??n
52	5	8	Incluido en la tarifa
53	4	6	Mantenimiento mensual
54	3	9	Disponible bajo petici??n
55	6	3	Incluido en la tarifa
56	1	8	Mantenimiento mensual
57	7	10	Requiere activaci??n previa
58	4	4	Disponible bajo petici??n
59	8	7	Incluido en la tarifa
60	5	3	Disponible bajo petici??n
61	6	4	Incluido en la tarifa
62	9	2	Requiere activaci??n previa
63	10	5	Mantenimiento mensual
64	10	9	Requiere activaci??n previa
65	3	7	Incluido en la tarifa
66	3	10	Incluido en la tarifa
67	10	5	Requiere activaci??n previa
68	10	2	Incluido en la tarifa
69	8	6	Disponible bajo petici??n
70	6	3	Mantenimiento mensual
71	5	9	Incluido en la tarifa
72	6	7	Mantenimiento mensual
73	2	2	Disponible bajo petici??n
74	8	7	Disponible bajo petici??n
75	9	10	Requiere activaci??n previa
76	7	4	Incluido en la tarifa
77	5	7	Mantenimiento mensual
78	8	3	Incluido en la tarifa
79	4	2	Incluido en la tarifa
80	7	5	Incluido en la tarifa
81	8	7	Mantenimiento mensual
82	5	10	Disponible bajo petici??n
83	3	2	Disponible bajo petici??n
84	5	10	Requiere activaci??n previa
85	4	1	Incluido en la tarifa
86	1	2	Disponible bajo petici??n
87	2	2	Mantenimiento mensual
88	7	9	Requiere activaci??n previa
89	2	8	Mantenimiento mensual
90	8	5	Disponible bajo petici??n
91	1	1	Requiere activaci??n previa
92	2	3	Disponible bajo petici??n
93	2	3	Mantenimiento mensual
94	5	7	Mantenimiento mensual
95	8	3	Incluido en la tarifa
96	9	5	Disponible bajo petici??n
97	3	6	Incluido en la tarifa
98	5	6	Mantenimiento mensual
99	8	6	Requiere activaci??n previa
100	8	10	Mantenimiento mensual
101	6	10	Incluido en la tarifa
102	4	1	Disponible bajo petici??n
103	10	10	Mantenimiento mensual
104	10	6	Incluido en la tarifa
105	2	6	Requiere activaci??n previa
106	3	6	Requiere activaci??n previa
107	4	5	Incluido en la tarifa
108	6	6	Disponible bajo petici??n
109	1	4	Incluido en la tarifa
110	7	4	Disponible bajo petici??n
111	10	1	Mantenimiento mensual
112	8	2	Requiere activaci??n previa
113	6	8	Mantenimiento mensual
114	1	5	Requiere activaci??n previa
115	9	6	Incluido en la tarifa
116	8	1	Disponible bajo petici??n
117	9	10	Mantenimiento mensual
118	1	2	Requiere activaci??n previa
119	4	6	Requiere activaci??n previa
120	5	3	Incluido en la tarifa
121	4	3	Incluido en la tarifa
122	4	1	Mantenimiento mensual
123	1	10	Mantenimiento mensual
124	9	10	Requiere activaci??n previa
125	2	6	Disponible bajo petici??n
126	4	10	Disponible bajo petici??n
127	3	1	Incluido en la tarifa
128	6	7	Mantenimiento mensual
129	2	10	Mantenimiento mensual
130	9	10	Mantenimiento mensual
131	8	7	Mantenimiento mensual
132	6	5	Mantenimiento mensual
133	4	3	Disponible bajo petici??n
134	3	9	Requiere activaci??n previa
135	7	6	Disponible bajo petici??n
136	3	10	Requiere activaci??n previa
137	6	9	Incluido en la tarifa
138	7	5	Requiere activaci??n previa
139	7	3	Mantenimiento mensual
140	9	7	Incluido en la tarifa
141	1	5	Mantenimiento mensual
142	10	1	Incluido en la tarifa
143	9	1	Incluido en la tarifa
144	6	3	Disponible bajo petici??n
145	4	2	Requiere activaci??n previa
146	5	6	Requiere activaci??n previa
147	5	9	Requiere activaci??n previa
148	4	8	Requiere activaci??n previa
149	1	9	Requiere activaci??n previa
150	5	1	Disponible bajo petici??n
151	8	2	Requiere activaci??n previa
152	7	3	Disponible bajo petici??n
153	6	6	Requiere activaci??n previa
154	7	10	Mantenimiento mensual
155	7	1	Mantenimiento mensual
156	8	9	Disponible bajo petici??n
157	2	6	Requiere activaci??n previa
158	2	7	Requiere activaci??n previa
159	8	7	Disponible bajo petici??n
160	1	9	Incluido en la tarifa
161	8	6	Disponible bajo petici??n
162	10	7	Requiere activaci??n previa
163	6	6	Incluido en la tarifa
164	9	10	Incluido en la tarifa
165	10	1	Mantenimiento mensual
166	6	10	Incluido en la tarifa
167	7	4	Mantenimiento mensual
168	6	2	Mantenimiento mensual
169	6	4	Incluido en la tarifa
170	4	2	Mantenimiento mensual
171	10	8	Requiere activaci??n previa
172	6	8	Mantenimiento mensual
173	6	5	Mantenimiento mensual
174	10	2	Requiere activaci??n previa
175	5	1	Mantenimiento mensual
176	9	2	Disponible bajo petici??n
177	3	7	Mantenimiento mensual
178	10	8	Mantenimiento mensual
179	3	10	Incluido en la tarifa
180	3	10	Requiere activaci??n previa
181	6	10	Disponible bajo petici??n
182	2	7	Mantenimiento mensual
183	3	10	Disponible bajo petici??n
184	5	8	Incluido en la tarifa
185	10	1	Incluido en la tarifa
186	2	5	Incluido en la tarifa
187	8	6	Disponible bajo petici??n
188	7	1	Mantenimiento mensual
189	9	4	Incluido en la tarifa
190	6	6	Mantenimiento mensual
191	7	8	Disponible bajo petici??n
192	6	9	Incluido en la tarifa
193	9	3	Requiere activaci??n previa
194	9	1	Incluido en la tarifa
195	5	5	Incluido en la tarifa
196	9	5	Mantenimiento mensual
197	6	10	Disponible bajo petici??n
198	2	8	Incluido en la tarifa
199	2	8	Mantenimiento mensual
200	3	4	Disponible bajo petici??n
201	8	4	Requiere activaci??n previa
202	3	8	Requiere activaci??n previa
203	10	10	Requiere activaci??n previa
204	2	10	Mantenimiento mensual
205	10	2	Mantenimiento mensual
206	8	5	Mantenimiento mensual
207	9	6	Mantenimiento mensual
208	1	7	Mantenimiento mensual
209	3	8	Disponible bajo petici??n
210	10	5	Mantenimiento mensual
211	6	1	Disponible bajo petici??n
212	7	5	Requiere activaci??n previa
213	4	3	Incluido en la tarifa
214	8	3	Disponible bajo petici??n
215	7	7	Incluido en la tarifa
216	7	5	Requiere activaci??n previa
217	1	9	Incluido en la tarifa
218	5	3	Incluido en la tarifa
219	9	10	Disponible bajo petici??n
220	6	1	Incluido en la tarifa
221	10	6	Mantenimiento mensual
222	7	9	Mantenimiento mensual
223	1	4	Incluido en la tarifa
224	4	5	Disponible bajo petici??n
225	1	4	Requiere activaci??n previa
226	5	9	Incluido en la tarifa
227	1	5	Requiere activaci??n previa
228	5	2	Disponible bajo petici??n
229	1	6	Requiere activaci??n previa
230	5	4	Incluido en la tarifa
231	10	2	Disponible bajo petici??n
232	7	7	Incluido en la tarifa
233	5	2	Mantenimiento mensual
234	10	10	Incluido en la tarifa
235	4	1	Mantenimiento mensual
236	10	7	Disponible bajo petici??n
237	5	4	Requiere activaci??n previa
238	10	3	Disponible bajo petici??n
239	5	2	Incluido en la tarifa
240	8	5	Disponible bajo petici??n
241	1	6	Requiere activaci??n previa
242	10	7	Incluido en la tarifa
243	6	4	Mantenimiento mensual
244	9	9	Mantenimiento mensual
245	9	4	Incluido en la tarifa
246	4	10	Disponible bajo petici??n
247	2	1	Incluido en la tarifa
248	5	5	Disponible bajo petici??n
249	4	10	Mantenimiento mensual
250	8	6	Requiere activaci??n previa
251	5	10	Requiere activaci??n previa
252	8	7	Disponible bajo petici??n
253	3	6	Incluido en la tarifa
254	7	9	Requiere activaci??n previa
255	1	4	Disponible bajo petici??n
256	2	7	Incluido en la tarifa
257	9	8	Disponible bajo petici??n
258	6	7	Requiere activaci??n previa
259	3	10	Incluido en la tarifa
260	9	8	Requiere activaci??n previa
261	10	5	Incluido en la tarifa
262	2	1	Requiere activaci??n previa
263	3	1	Requiere activaci??n previa
264	10	10	Requiere activaci??n previa
265	6	9	Disponible bajo petici??n
266	8	4	Requiere activaci??n previa
267	5	5	Disponible bajo petici??n
268	4	4	Disponible bajo petici??n
269	3	6	Mantenimiento mensual
270	9	6	Disponible bajo petici??n
271	4	10	Incluido en la tarifa
272	4	9	Incluido en la tarifa
273	7	7	Requiere activaci??n previa
274	8	9	Mantenimiento mensual
275	2	4	Requiere activaci??n previa
276	10	6	Incluido en la tarifa
277	10	5	Mantenimiento mensual
278	4	2	Requiere activaci??n previa
279	5	10	Requiere activaci??n previa
280	10	2	Incluido en la tarifa
281	10	2	Mantenimiento mensual
282	1	7	Disponible bajo petici??n
283	10	6	Incluido en la tarifa
284	8	9	Requiere activaci??n previa
285	4	5	Incluido en la tarifa
286	10	6	Incluido en la tarifa
287	9	10	Incluido en la tarifa
288	4	1	Requiere activaci??n previa
289	4	4	Incluido en la tarifa
290	3	1	Disponible bajo petici??n
291	2	6	Disponible bajo petici??n
292	8	9	Incluido en la tarifa
293	7	9	Incluido en la tarifa
294	2	9	Mantenimiento mensual
295	2	3	Mantenimiento mensual
296	9	2	Disponible bajo petici??n
297	6	7	Incluido en la tarifa
298	1	2	Requiere activaci??n previa
299	9	8	Mantenimiento mensual
300	3	3	Requiere activaci??n previa
301	1	7	Disponible bajo petici??n
302	8	6	Requiere activaci??n previa
303	2	10	Requiere activaci??n previa
304	10	2	Incluido en la tarifa
305	3	10	Incluido en la tarifa
306	9	10	Incluido en la tarifa
307	2	4	Requiere activaci??n previa
308	6	3	Incluido en la tarifa
309	1	2	Disponible bajo petici??n
310	4	10	Disponible bajo petici??n
311	6	5	Mantenimiento mensual
312	5	2	Disponible bajo petici??n
313	1	5	Incluido en la tarifa
314	8	7	Disponible bajo petici??n
315	4	1	Disponible bajo petici??n
316	3	1	Disponible bajo petici??n
317	3	4	Disponible bajo petici??n
318	5	6	Disponible bajo petici??n
319	5	6	Incluido en la tarifa
320	7	3	Requiere activaci??n previa
321	1	10	Requiere activaci??n previa
322	10	5	Disponible bajo petici??n
323	2	9	Incluido en la tarifa
324	5	7	Incluido en la tarifa
325	5	7	Disponible bajo petici??n
326	6	5	Requiere activaci??n previa
327	10	10	Disponible bajo petici??n
328	2	8	Mantenimiento mensual
329	9	1	Incluido en la tarifa
330	2	3	Mantenimiento mensual
331	10	7	Incluido en la tarifa
332	9	3	Mantenimiento mensual
333	8	1	Requiere activaci??n previa
334	8	8	Disponible bajo petici??n
335	7	8	Disponible bajo petici??n
336	10	10	Disponible bajo petici??n
337	4	2	Mantenimiento mensual
338	10	1	Incluido en la tarifa
339	2	5	Disponible bajo petici??n
340	9	10	Incluido en la tarifa
341	1	8	Disponible bajo petici??n
342	7	10	Disponible bajo petici??n
343	6	3	Incluido en la tarifa
344	10	5	Requiere activaci??n previa
345	8	9	Mantenimiento mensual
346	8	8	Requiere activaci??n previa
347	3	6	Requiere activaci??n previa
348	7	8	Mantenimiento mensual
349	7	1	Mantenimiento mensual
350	4	7	Requiere activaci??n previa
351	9	6	Requiere activaci??n previa
352	10	4	Disponible bajo petici??n
353	7	3	Requiere activaci??n previa
354	4	10	Mantenimiento mensual
355	2	9	Requiere activaci??n previa
356	6	6	Disponible bajo petici??n
357	5	6	Requiere activaci??n previa
358	10	4	Requiere activaci??n previa
359	5	9	Requiere activaci??n previa
360	4	10	Disponible bajo petici??n
361	6	10	Mantenimiento mensual
362	1	8	Incluido en la tarifa
363	2	2	Incluido en la tarifa
364	6	6	Requiere activaci??n previa
365	5	9	Incluido en la tarifa
366	1	7	Requiere activaci??n previa
367	1	5	Mantenimiento mensual
368	1	8	Incluido en la tarifa
369	2	5	Mantenimiento mensual
370	9	9	Disponible bajo petici??n
371	1	3	Requiere activaci??n previa
372	6	6	Incluido en la tarifa
373	7	8	Incluido en la tarifa
374	3	1	Disponible bajo petici??n
375	6	9	Mantenimiento mensual
376	10	5	Incluido en la tarifa
377	2	8	Disponible bajo petici??n
378	4	5	Disponible bajo petici??n
379	9	7	Mantenimiento mensual
380	5	7	Requiere activaci??n previa
381	8	6	Mantenimiento mensual
382	1	2	Incluido en la tarifa
383	7	8	Mantenimiento mensual
384	5	8	Mantenimiento mensual
385	7	8	Incluido en la tarifa
386	1	5	Disponible bajo petici??n
387	1	4	Requiere activaci??n previa
388	8	5	Incluido en la tarifa
389	5	10	Disponible bajo petici??n
390	5	1	Mantenimiento mensual
391	5	5	Incluido en la tarifa
392	7	5	Incluido en la tarifa
393	10	4	Disponible bajo petici??n
394	3	9	Disponible bajo petici??n
395	3	5	Incluido en la tarifa
396	5	7	Incluido en la tarifa
397	7	2	Disponible bajo petici??n
398	8	3	Incluido en la tarifa
399	7	1	Requiere activaci??n previa
400	5	3	Requiere activaci??n previa
401	6	5	Incluido en la tarifa
402	7	3	Mantenimiento mensual
403	8	1	Incluido en la tarifa
404	4	5	Requiere activaci??n previa
405	10	8	Incluido en la tarifa
406	2	4	Disponible bajo petici??n
407	8	1	Requiere activaci??n previa
408	1	1	Incluido en la tarifa
409	9	4	Requiere activaci??n previa
410	10	4	Disponible bajo petici??n
411	4	9	Disponible bajo petici??n
412	3	10	Disponible bajo petici??n
413	6	3	Disponible bajo petici??n
414	6	6	Disponible bajo petici??n
415	6	4	Requiere activaci??n previa
416	5	5	Requiere activaci??n previa
417	10	10	Mantenimiento mensual
418	7	9	Requiere activaci??n previa
419	8	7	Requiere activaci??n previa
420	5	5	Incluido en la tarifa
421	8	5	Requiere activaci??n previa
422	1	2	Mantenimiento mensual
423	6	3	Incluido en la tarifa
424	6	5	Requiere activaci??n previa
425	1	2	Mantenimiento mensual
426	4	1	Disponible bajo petici??n
427	7	3	Incluido en la tarifa
428	1	5	Disponible bajo petici??n
429	10	1	Mantenimiento mensual
430	6	1	Requiere activaci??n previa
431	2	8	Incluido en la tarifa
432	5	8	Requiere activaci??n previa
433	4	10	Mantenimiento mensual
434	9	1	Requiere activaci??n previa
435	7	8	Mantenimiento mensual
436	7	3	Disponible bajo petici??n
437	10	8	Incluido en la tarifa
438	7	10	Disponible bajo petici??n
439	7	4	Incluido en la tarifa
440	1	3	Mantenimiento mensual
441	4	1	Disponible bajo petici??n
442	7	7	Disponible bajo petici??n
443	3	2	Requiere activaci??n previa
444	3	7	Requiere activaci??n previa
445	9	4	Mantenimiento mensual
446	9	2	Requiere activaci??n previa
447	9	2	Incluido en la tarifa
448	5	8	Disponible bajo petici??n
449	2	10	Mantenimiento mensual
450	8	6	Requiere activaci??n previa
451	8	2	Mantenimiento mensual
452	4	4	Requiere activaci??n previa
453	8	5	Requiere activaci??n previa
454	7	6	Requiere activaci??n previa
455	6	6	Requiere activaci??n previa
456	4	10	Incluido en la tarifa
457	3	2	Incluido en la tarifa
458	2	4	Requiere activaci??n previa
459	1	2	Mantenimiento mensual
460	5	2	Incluido en la tarifa
461	1	8	Requiere activaci??n previa
462	5	4	Requiere activaci??n previa
463	1	7	Requiere activaci??n previa
464	1	8	Incluido en la tarifa
465	9	4	Disponible bajo petici??n
466	5	3	Incluido en la tarifa
467	7	7	Mantenimiento mensual
468	6	10	Incluido en la tarifa
469	4	10	Mantenimiento mensual
470	5	8	Disponible bajo petici??n
471	10	7	Disponible bajo petici??n
472	5	3	Incluido en la tarifa
473	5	1	Mantenimiento mensual
474	6	8	Mantenimiento mensual
475	1	9	Mantenimiento mensual
476	7	3	Incluido en la tarifa
477	9	6	Mantenimiento mensual
478	3	5	Disponible bajo petici??n
479	7	1	Incluido en la tarifa
480	3	2	Requiere activaci??n previa
481	3	1	Incluido en la tarifa
482	3	10	Mantenimiento mensual
483	8	8	Requiere activaci??n previa
484	6	9	Disponible bajo petici??n
485	8	2	Incluido en la tarifa
486	3	7	Requiere activaci??n previa
487	1	1	Disponible bajo petici??n
488	7	9	Mantenimiento mensual
489	9	3	Disponible bajo petici??n
490	9	7	Incluido en la tarifa
491	7	1	Mantenimiento mensual
492	1	1	Incluido en la tarifa
493	9	9	Incluido en la tarifa
494	7	10	Disponible bajo petici??n
495	9	2	Disponible bajo petici??n
496	1	10	Requiere activaci??n previa
497	9	8	Mantenimiento mensual
498	3	7	Incluido en la tarifa
499	4	7	Incluido en la tarifa
500	8	3	Mantenimiento mensual
501	10	5	Mantenimiento mensual
502	10	6	Mantenimiento mensual
503	5	7	Disponible bajo petici??n
504	5	3	Disponible bajo petici??n
505	2	2	Requiere activaci??n previa
506	1	8	Mantenimiento mensual
507	1	4	Disponible bajo petici??n
508	8	1	Incluido en la tarifa
509	4	2	Disponible bajo petici??n
510	10	8	Disponible bajo petici??n
511	2	10	Requiere activaci??n previa
512	10	9	Disponible bajo petici??n
513	1	8	Disponible bajo petici??n
514	7	2	Mantenimiento mensual
515	6	2	Mantenimiento mensual
516	9	2	Incluido en la tarifa
517	9	2	Incluido en la tarifa
518	1	9	Requiere activaci??n previa
519	3	2	Disponible bajo petici??n
520	2	5	Mantenimiento mensual
521	4	9	Mantenimiento mensual
522	7	5	Incluido en la tarifa
523	6	10	Incluido en la tarifa
524	1	3	Mantenimiento mensual
525	6	8	Incluido en la tarifa
526	1	8	Incluido en la tarifa
527	4	7	Mantenimiento mensual
528	5	3	Requiere activaci??n previa
529	10	8	Mantenimiento mensual
530	9	6	Incluido en la tarifa
531	2	2	Requiere activaci??n previa
532	6	3	Requiere activaci??n previa
533	1	7	Requiere activaci??n previa
534	8	2	Mantenimiento mensual
535	4	10	Requiere activaci??n previa
536	10	4	Requiere activaci??n previa
537	10	2	Incluido en la tarifa
538	8	8	Incluido en la tarifa
539	3	6	Disponible bajo petici??n
540	3	8	Requiere activaci??n previa
541	8	1	Requiere activaci??n previa
542	10	2	Mantenimiento mensual
543	8	1	Mantenimiento mensual
544	1	5	Disponible bajo petici??n
545	4	8	Requiere activaci??n previa
546	3	6	Incluido en la tarifa
547	2	3	Disponible bajo petici??n
548	1	7	Disponible bajo petici??n
549	1	8	Incluido en la tarifa
550	10	8	Requiere activaci??n previa
551	6	3	Incluido en la tarifa
552	5	3	Disponible bajo petici??n
553	1	10	Incluido en la tarifa
554	8	3	Incluido en la tarifa
555	10	10	Incluido en la tarifa
556	5	4	Mantenimiento mensual
557	9	9	Disponible bajo petici??n
558	4	7	Incluido en la tarifa
559	4	4	Mantenimiento mensual
560	4	9	Mantenimiento mensual
561	1	3	Disponible bajo petici??n
562	7	6	Disponible bajo petici??n
563	1	7	Disponible bajo petici??n
564	2	4	Requiere activaci??n previa
565	7	9	Disponible bajo petici??n
566	6	9	Disponible bajo petici??n
567	5	8	Requiere activaci??n previa
568	6	1	Incluido en la tarifa
569	2	8	Requiere activaci??n previa
570	5	1	Disponible bajo petici??n
571	9	10	Mantenimiento mensual
572	8	7	Disponible bajo petici??n
573	2	8	Disponible bajo petici??n
574	7	6	Requiere activaci??n previa
575	6	7	Requiere activaci??n previa
576	10	6	Mantenimiento mensual
577	7	9	Requiere activaci??n previa
578	2	3	Mantenimiento mensual
579	2	2	Disponible bajo petici??n
580	1	1	Mantenimiento mensual
581	1	9	Mantenimiento mensual
582	9	4	Requiere activaci??n previa
583	2	3	Mantenimiento mensual
584	3	7	Incluido en la tarifa
585	8	9	Mantenimiento mensual
586	10	3	Disponible bajo petici??n
587	3	7	Mantenimiento mensual
588	1	3	Incluido en la tarifa
589	6	9	Mantenimiento mensual
590	2	10	Mantenimiento mensual
591	10	3	Incluido en la tarifa
592	9	3	Requiere activaci??n previa
593	9	5	Requiere activaci??n previa
594	2	5	Requiere activaci??n previa
595	4	10	Mantenimiento mensual
596	1	10	Mantenimiento mensual
597	2	6	Mantenimiento mensual
598	6	3	Disponible bajo petici??n
599	4	2	Disponible bajo petici??n
600	6	2	Incluido en la tarifa
601	5	1	Disponible bajo petici??n
602	3	2	Disponible bajo petici??n
603	2	1	Disponible bajo petici??n
604	1	10	Incluido en la tarifa
605	4	7	Incluido en la tarifa
606	8	6	Incluido en la tarifa
607	2	9	Disponible bajo petici??n
608	2	10	Requiere activaci??n previa
609	6	2	Requiere activaci??n previa
610	8	3	Mantenimiento mensual
611	3	8	Mantenimiento mensual
612	4	3	Mantenimiento mensual
613	10	9	Disponible bajo petici??n
614	5	2	Mantenimiento mensual
615	3	5	Requiere activaci??n previa
616	3	10	Requiere activaci??n previa
617	9	10	Incluido en la tarifa
618	8	3	Mantenimiento mensual
619	3	3	Mantenimiento mensual
620	8	6	Mantenimiento mensual
621	1	8	Requiere activaci??n previa
622	9	1	Mantenimiento mensual
623	2	6	Incluido en la tarifa
624	3	1	Incluido en la tarifa
625	8	1	Mantenimiento mensual
626	8	3	Disponible bajo petici??n
627	6	7	Requiere activaci??n previa
628	10	7	Incluido en la tarifa
629	4	9	Incluido en la tarifa
630	8	6	Incluido en la tarifa
631	6	10	Disponible bajo petici??n
632	5	5	Mantenimiento mensual
633	5	9	Incluido en la tarifa
634	7	2	Mantenimiento mensual
635	6	8	Incluido en la tarifa
636	9	1	Incluido en la tarifa
637	5	7	Mantenimiento mensual
638	10	4	Mantenimiento mensual
639	7	6	Incluido en la tarifa
640	4	6	Incluido en la tarifa
641	9	4	Requiere activaci??n previa
642	6	1	Incluido en la tarifa
643	4	6	Requiere activaci??n previa
644	9	3	Requiere activaci??n previa
645	4	10	Mantenimiento mensual
646	10	6	Mantenimiento mensual
647	6	6	Disponible bajo petici??n
648	5	5	Disponible bajo petici??n
649	10	1	Disponible bajo petici??n
650	8	7	Requiere activaci??n previa
651	4	10	Mantenimiento mensual
652	3	2	Disponible bajo petici??n
653	1	5	Incluido en la tarifa
654	1	2	Requiere activaci??n previa
655	5	2	Requiere activaci??n previa
656	9	9	Requiere activaci??n previa
657	3	4	Mantenimiento mensual
658	5	9	Mantenimiento mensual
659	2	2	Mantenimiento mensual
660	4	10	Disponible bajo petici??n
661	3	2	Incluido en la tarifa
662	2	1	Requiere activaci??n previa
663	10	8	Requiere activaci??n previa
664	4	9	Disponible bajo petici??n
665	7	8	Requiere activaci??n previa
666	10	1	Incluido en la tarifa
667	2	3	Incluido en la tarifa
668	5	1	Disponible bajo petici??n
669	7	10	Requiere activaci??n previa
670	4	8	Incluido en la tarifa
671	8	10	Requiere activaci??n previa
672	8	6	Disponible bajo petici??n
673	8	1	Mantenimiento mensual
674	6	7	Mantenimiento mensual
675	4	6	Disponible bajo petici??n
676	5	3	Incluido en la tarifa
677	7	2	Incluido en la tarifa
678	1	10	Disponible bajo petici??n
679	5	10	Requiere activaci??n previa
680	1	10	Incluido en la tarifa
681	9	4	Disponible bajo petici??n
682	8	4	Disponible bajo petici??n
683	3	10	Incluido en la tarifa
684	10	3	Requiere activaci??n previa
685	2	4	Mantenimiento mensual
686	6	4	Mantenimiento mensual
687	6	9	Incluido en la tarifa
688	6	2	Incluido en la tarifa
689	2	4	Requiere activaci??n previa
690	5	4	Incluido en la tarifa
691	6	3	Mantenimiento mensual
692	6	3	Incluido en la tarifa
693	1	5	Mantenimiento mensual
694	5	10	Incluido en la tarifa
695	9	5	Mantenimiento mensual
696	9	9	Requiere activaci??n previa
697	6	5	Mantenimiento mensual
698	6	6	Disponible bajo petici??n
699	6	9	Disponible bajo petici??n
700	1	1	Disponible bajo petici??n
701	7	6	Incluido en la tarifa
702	2	1	Requiere activaci??n previa
703	5	3	Requiere activaci??n previa
704	9	10	Incluido en la tarifa
705	4	1	Requiere activaci??n previa
706	10	3	Requiere activaci??n previa
707	1	6	Requiere activaci??n previa
708	6	2	Requiere activaci??n previa
709	8	1	Requiere activaci??n previa
710	7	2	Requiere activaci??n previa
711	7	3	Requiere activaci??n previa
712	6	9	Requiere activaci??n previa
713	4	8	Incluido en la tarifa
714	8	7	Mantenimiento mensual
715	4	7	Disponible bajo petici??n
716	8	3	Incluido en la tarifa
717	8	8	Mantenimiento mensual
718	1	1	Incluido en la tarifa
719	3	2	Requiere activaci??n previa
720	1	5	Incluido en la tarifa
721	9	10	Requiere activaci??n previa
722	1	2	Mantenimiento mensual
723	6	6	Requiere activaci??n previa
724	9	10	Requiere activaci??n previa
725	1	7	Incluido en la tarifa
726	4	7	Incluido en la tarifa
727	7	1	Disponible bajo petici??n
728	2	9	Incluido en la tarifa
729	7	7	Requiere activaci??n previa
730	3	10	Disponible bajo petici??n
731	2	3	Mantenimiento mensual
732	7	2	Mantenimiento mensual
733	10	2	Mantenimiento mensual
734	8	8	Incluido en la tarifa
735	1	7	Requiere activaci??n previa
736	10	1	Disponible bajo petici??n
737	10	9	Incluido en la tarifa
738	10	7	Incluido en la tarifa
739	1	5	Incluido en la tarifa
740	2	1	Mantenimiento mensual
741	3	1	Disponible bajo petici??n
742	10	7	Disponible bajo petici??n
743	10	6	Requiere activaci??n previa
744	1	7	Incluido en la tarifa
745	3	1	Requiere activaci??n previa
746	8	2	Mantenimiento mensual
747	8	8	Mantenimiento mensual
748	2	9	Disponible bajo petici??n
749	9	8	Requiere activaci??n previa
750	3	7	Requiere activaci??n previa
751	10	3	Incluido en la tarifa
752	1	10	Requiere activaci??n previa
753	8	8	Incluido en la tarifa
754	9	2	Mantenimiento mensual
755	1	10	Incluido en la tarifa
756	7	10	Disponible bajo petici??n
757	9	4	Requiere activaci??n previa
758	3	5	Disponible bajo petici??n
759	10	2	Requiere activaci??n previa
760	6	2	Requiere activaci??n previa
761	10	4	Requiere activaci??n previa
762	2	1	Requiere activaci??n previa
763	2	3	Incluido en la tarifa
764	4	1	Requiere activaci??n previa
765	4	3	Incluido en la tarifa
766	4	8	Mantenimiento mensual
767	10	6	Mantenimiento mensual
768	4	4	Requiere activaci??n previa
769	10	3	Mantenimiento mensual
770	6	5	Incluido en la tarifa
771	7	3	Requiere activaci??n previa
772	7	10	Requiere activaci??n previa
773	7	4	Incluido en la tarifa
774	2	2	Requiere activaci??n previa
775	8	1	Incluido en la tarifa
776	2	7	Requiere activaci??n previa
777	5	5	Requiere activaci??n previa
778	10	7	Mantenimiento mensual
779	6	10	Requiere activaci??n previa
780	7	6	Requiere activaci??n previa
781	3	9	Requiere activaci??n previa
782	9	2	Incluido en la tarifa
783	2	3	Disponible bajo petici??n
784	1	5	Incluido en la tarifa
785	9	10	Disponible bajo petici??n
786	10	8	Mantenimiento mensual
787	7	6	Requiere activaci??n previa
788	5	5	Incluido en la tarifa
789	1	6	Requiere activaci??n previa
790	4	6	Disponible bajo petici??n
791	6	5	Requiere activaci??n previa
792	2	4	Incluido en la tarifa
793	8	9	Incluido en la tarifa
794	6	2	Disponible bajo petici??n
795	6	7	Disponible bajo petici??n
796	1	4	Incluido en la tarifa
797	3	10	Requiere activaci??n previa
798	9	4	Disponible bajo petici??n
799	4	9	Requiere activaci??n previa
800	9	2	Incluido en la tarifa
801	5	2	Incluido en la tarifa
802	5	3	Incluido en la tarifa
803	10	6	Requiere activaci??n previa
804	7	10	Requiere activaci??n previa
805	1	3	Mantenimiento mensual
806	10	5	Disponible bajo petici??n
807	1	2	Disponible bajo petici??n
808	8	7	Disponible bajo petici??n
809	9	1	Requiere activaci??n previa
810	10	4	Incluido en la tarifa
811	4	1	Mantenimiento mensual
812	5	9	Mantenimiento mensual
813	10	9	Mantenimiento mensual
814	2	2	Requiere activaci??n previa
815	8	9	Incluido en la tarifa
816	5	2	Disponible bajo petici??n
817	6	9	Mantenimiento mensual
818	4	3	Mantenimiento mensual
819	5	3	Requiere activaci??n previa
820	8	10	Requiere activaci??n previa
821	2	9	Disponible bajo petici??n
822	9	8	Mantenimiento mensual
823	1	5	Disponible bajo petici??n
824	5	1	Incluido en la tarifa
825	9	10	Mantenimiento mensual
826	7	3	Requiere activaci??n previa
827	7	6	Disponible bajo petici??n
828	4	1	Requiere activaci??n previa
829	3	2	Mantenimiento mensual
830	3	10	Disponible bajo petici??n
831	10	1	Incluido en la tarifa
832	8	1	Mantenimiento mensual
833	3	7	Disponible bajo petici??n
834	8	6	Incluido en la tarifa
835	3	5	Mantenimiento mensual
836	3	6	Requiere activaci??n previa
837	8	2	Requiere activaci??n previa
838	3	9	Disponible bajo petici??n
839	5	4	Requiere activaci??n previa
840	1	4	Mantenimiento mensual
841	10	4	Disponible bajo petici??n
842	2	1	Requiere activaci??n previa
843	2	7	Disponible bajo petici??n
844	10	1	Requiere activaci??n previa
845	10	3	Requiere activaci??n previa
846	2	1	Incluido en la tarifa
847	6	10	Incluido en la tarifa
848	1	8	Incluido en la tarifa
849	2	7	Disponible bajo petici??n
850	10	2	Mantenimiento mensual
851	8	3	Requiere activaci??n previa
852	10	1	Disponible bajo petici??n
853	6	10	Incluido en la tarifa
854	2	6	Requiere activaci??n previa
855	3	8	Incluido en la tarifa
856	3	3	Incluido en la tarifa
857	6	6	Mantenimiento mensual
858	2	8	Mantenimiento mensual
859	7	9	Disponible bajo petici??n
860	1	10	Mantenimiento mensual
861	2	3	Disponible bajo petici??n
862	8	2	Requiere activaci??n previa
863	9	8	Incluido en la tarifa
864	2	2	Disponible bajo petici??n
865	2	10	Mantenimiento mensual
866	5	3	Requiere activaci??n previa
867	10	1	Mantenimiento mensual
868	2	6	Disponible bajo petici??n
869	9	6	Incluido en la tarifa
870	6	2	Mantenimiento mensual
871	6	9	Incluido en la tarifa
872	2	3	Mantenimiento mensual
873	8	8	Disponible bajo petici??n
874	6	3	Requiere activaci??n previa
875	5	3	Incluido en la tarifa
876	1	5	Requiere activaci??n previa
877	2	3	Incluido en la tarifa
878	3	7	Requiere activaci??n previa
879	7	10	Disponible bajo petici??n
880	4	4	Mantenimiento mensual
881	2	1	Disponible bajo petici??n
882	5	2	Requiere activaci??n previa
883	10	2	Disponible bajo petici??n
884	3	5	Mantenimiento mensual
885	7	1	Disponible bajo petici??n
886	5	4	Requiere activaci??n previa
887	2	8	Disponible bajo petici??n
888	7	8	Disponible bajo petici??n
889	7	2	Mantenimiento mensual
890	6	10	Disponible bajo petici??n
891	9	3	Mantenimiento mensual
892	10	8	Disponible bajo petici??n
893	1	3	Incluido en la tarifa
894	4	2	Requiere activaci??n previa
895	10	5	Requiere activaci??n previa
896	4	10	Disponible bajo petici??n
897	9	1	Requiere activaci??n previa
898	4	8	Mantenimiento mensual
899	5	8	Disponible bajo petici??n
900	10	9	Disponible bajo petici??n
901	1	9	Incluido en la tarifa
902	1	8	Mantenimiento mensual
903	2	6	Mantenimiento mensual
904	6	5	Requiere activaci??n previa
905	7	5	Mantenimiento mensual
906	9	10	Incluido en la tarifa
907	3	3	Mantenimiento mensual
908	9	3	Incluido en la tarifa
909	1	2	Incluido en la tarifa
910	1	1	Mantenimiento mensual
911	4	6	Incluido en la tarifa
912	6	4	Incluido en la tarifa
913	8	6	Incluido en la tarifa
914	10	3	Mantenimiento mensual
915	4	6	Requiere activaci??n previa
916	5	7	Requiere activaci??n previa
917	2	6	Disponible bajo petici??n
918	5	5	Requiere activaci??n previa
919	4	7	Requiere activaci??n previa
920	4	9	Disponible bajo petici??n
921	2	3	Requiere activaci??n previa
922	9	6	Mantenimiento mensual
923	10	9	Disponible bajo petici??n
924	6	7	Disponible bajo petici??n
925	4	8	Mantenimiento mensual
926	5	4	Requiere activaci??n previa
927	1	2	Mantenimiento mensual
928	1	2	Mantenimiento mensual
929	9	9	Mantenimiento mensual
930	9	1	Incluido en la tarifa
931	5	1	Mantenimiento mensual
932	8	7	Requiere activaci??n previa
933	4	3	Requiere activaci??n previa
934	7	9	Incluido en la tarifa
935	4	10	Disponible bajo petici??n
936	3	8	Mantenimiento mensual
937	6	8	Disponible bajo petici??n
938	2	10	Incluido en la tarifa
939	4	5	Incluido en la tarifa
940	6	1	Mantenimiento mensual
941	5	2	Disponible bajo petici??n
942	4	5	Disponible bajo petici??n
943	8	9	Mantenimiento mensual
944	1	4	Mantenimiento mensual
945	8	5	Requiere activaci??n previa
946	2	7	Incluido en la tarifa
947	4	1	Mantenimiento mensual
948	2	3	Incluido en la tarifa
949	6	9	Mantenimiento mensual
950	4	1	Incluido en la tarifa
951	9	3	Requiere activaci??n previa
952	6	4	Incluido en la tarifa
953	10	1	Disponible bajo petici??n
954	3	2	Mantenimiento mensual
955	1	1	Disponible bajo petici??n
956	6	7	Disponible bajo petici??n
957	10	2	Mantenimiento mensual
958	5	9	Requiere activaci??n previa
959	6	8	Disponible bajo petici??n
960	8	10	Disponible bajo petici??n
961	8	2	Incluido en la tarifa
962	7	5	Mantenimiento mensual
963	10	4	Incluido en la tarifa
964	3	8	Disponible bajo petici??n
965	5	3	Incluido en la tarifa
966	10	7	Mantenimiento mensual
967	3	2	Mantenimiento mensual
968	1	8	Incluido en la tarifa
969	3	7	Mantenimiento mensual
970	2	1	Requiere activaci??n previa
971	5	2	Disponible bajo petici??n
972	1	5	Mantenimiento mensual
973	8	4	Disponible bajo petici??n
974	7	7	Incluido en la tarifa
975	6	10	Disponible bajo petici??n
976	8	8	Mantenimiento mensual
\.


--
-- TOC entry 5344 (class 0 OID 31048)
-- Dependencies: 223
-- Data for Name: consumo_servicio; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.consumo_servicio (id_consumo_servicio, id_servicio, id_habitacion, id_estadia, hora_consumo) FROM stdin;
5495	10	196	1001	2025-10-26 02:16:44.019304
2	6	565	475	2026-10-08 17:21:19
3	9	59	708	2026-01-17 13:37:26
5496	2	196	1001	2025-10-26 18:18:53.967336
5497	3	196	1001	2025-10-27 19:38:46.755393
6	8	627	73	2025-03-30 14:49:10
8	2	190	228	2025-09-14 18:10:47
5498	1	809	1002	2025-04-20 06:14:25.014884
5499	6	809	1002	2025-04-18 12:49:24.135298
5500	4	809	1002	2025-04-19 07:19:30.126689
5501	8	570	1003	2025-02-28 17:17:48.956991
5502	7	570	1003	2025-03-01 00:59:33.410367
5503	9	570	1003	2025-03-01 00:10:38.315504
5504	6	198	1004	2025-03-08 23:47:46.359711
5505	1	198	1004	2025-03-09 04:55:40.765512
21	3	753	566	2025-03-30 08:06:28
5506	1	198	1004	2025-03-08 23:55:39.643795
23	8	951	268	2025-01-15 18:25:45
5507	4	547	1005	2025-06-02 16:09:02.277749
5508	8	547	1005	2025-06-01 04:32:21.843788
5509	9	547	1005	2025-05-30 15:20:31.632699
5510	10	729	1006	2025-05-25 20:01:55.924378
5511	7	729	1006	2025-05-25 06:52:18.15112
5512	8	729	1006	2025-05-24 03:09:42.551356
32	10	608	71	2026-06-21 07:46:13
5513	5	97	1007	2025-09-05 14:15:42.425577
5514	8	97	1007	2025-09-05 09:43:17.440615
5515	1	97	1007	2025-09-05 23:55:21.730414
5516	9	151	1008	2025-05-17 11:57:11.946825
5517	10	151	1008	2025-05-15 05:38:18.195966
5518	8	151	1008	2025-05-16 22:06:15.48726
5519	3	121	1009	2025-10-22 17:51:07.687601
5520	3	121	1009	2025-10-20 19:23:19.716221
5521	9	121	1009	2025-10-22 00:27:19.443179
5522	6	349	1010	2025-08-12 23:06:59.887012
5523	9	349	1010	2025-08-13 11:31:59.880908
5524	6	349	1010	2025-08-10 21:07:15.980085
57	3	688	516	2025-03-16 22:40:20
66	9	658	780	2025-10-02 17:53:43
68	1	969	43	2025-01-10 22:39:45
70	9	929	945	2026-10-15 12:12:06
71	1	189	430	2025-05-19 15:36:54
72	4	67	233	2026-09-04 03:04:44
74	1	111	989	2026-01-24 11:58:13
76	7	543	544	2025-12-13 16:58:48
84	1	360	233	2026-10-24 06:26:31
98	2	379	566	2025-05-01 02:33:00
101	2	660	163	2026-09-05 03:28:21
104	5	311	677	2025-12-07 21:39:33
110	4	254	295	2025-05-18 05:42:02
115	2	43	457	2026-09-02 01:52:30
117	7	684	71	2025-09-19 11:37:49
123	2	969	995	2025-03-23 20:10:31
142	7	387	385	2025-07-12 20:31:01
153	6	728	164	2026-04-10 10:39:41
155	5	834	223	2026-03-26 23:27:01
166	3	185	618	2025-10-11 10:34:49
171	4	580	618	2026-07-07 12:34:12
176	7	794	126	2026-11-04 02:43:50
183	4	777	317	2025-08-31 06:04:26
184	2	325	676	2025-03-13 00:19:05
186	9	728	126	2026-10-28 07:35:19
187	6	931	747	2025-06-24 02:06:11
191	10	891	469	2025-10-18 23:09:55
205	3	188	676	2026-11-05 02:40:00
208	3	774	587	2026-09-14 14:49:42
211	1	7	126	2025-09-14 13:46:45
219	7	889	434	2025-08-12 13:40:54
226	2	658	827	2026-10-23 04:00:13
229	2	829	65	2026-08-03 06:15:51
230	7	200	122	2026-08-05 14:42:05
232	8	911	449	2026-05-21 02:24:29
241	8	500	485	2025-06-04 21:11:39
254	8	929	458	2025-10-06 14:41:48
255	5	820	544	2025-06-07 01:22:20
264	7	219	243	2025-08-09 16:10:49
277	3	951	126	2025-01-17 10:53:37
278	7	604	223	2025-04-30 01:00:58
288	6	381	934	2026-10-10 20:51:50
292	9	887	794	2026-10-15 18:10:57
295	6	452	537	2025-06-25 23:29:23
300	5	878	60	2025-05-24 08:18:08
304	3	652	948	2025-12-08 10:12:28
306	2	849	755	2026-04-06 22:15:00
313	1	126	153	2025-06-22 20:03:24
324	1	221	221	2025-04-06 17:30:52
326	2	953	796	2026-12-24 16:49:42
340	5	811	214	2025-03-08 13:40:16
341	4	792	294	2026-07-24 14:34:32
347	6	922	891	2026-11-27 02:29:44
356	5	705	380	2026-11-22 05:24:53
366	2	491	912	2025-05-29 07:45:55
368	1	972	148	2026-04-07 13:22:27
385	6	572	546	2026-01-27 00:19:41
400	8	299	27	2025-09-27 04:21:57
405	5	185	458	2025-04-14 19:55:27
406	8	81	405	2026-02-16 22:52:29
409	6	660	350	2025-07-19 16:01:39
425	2	791	223	2025-01-04 15:16:06
430	4	683	223	2026-06-26 04:23:00
432	2	131	838	2026-02-20 17:59:25
435	4	690	899	2026-01-31 23:06:10
442	2	217	251	2026-04-20 11:16:01
455	8	44	284	2026-08-02 00:50:33
459	1	11	267	2025-02-01 23:25:38
460	8	166	124	2025-07-11 21:21:53
464	5	305	92	2025-11-02 03:14:28
471	3	17	321	2025-11-09 10:44:33
480	1	762	945	2025-05-02 15:58:18
483	2	434	790	2026-11-22 14:52:32
495	6	502	995	2025-12-23 06:01:32
501	3	169	38	2025-05-16 09:10:48
506	10	785	332	2026-11-21 09:55:03
510	4	709	251	2026-01-28 18:38:03
520	3	478	451	2026-06-28 01:45:02
527	1	597	546	2025-03-22 10:42:24
528	10	675	887	2026-01-07 14:51:51
532	10	699	9	2026-10-17 12:17:04
540	7	313	9	2026-07-10 21:39:28
546	3	164	678	2025-04-14 12:14:49
550	1	96	457	2025-12-21 01:48:33
567	4	925	516	2026-09-16 22:03:20
573	6	17	783	2026-11-19 06:44:21
576	8	461	780	2025-09-02 22:00:57
582	6	794	786	2025-07-29 00:16:15
600	6	455	75	2025-01-07 15:43:00
601	4	534	449	2025-10-02 22:39:46
621	1	467	948	2025-09-09 12:41:48
625	10	932	616	2026-09-01 19:42:22
626	6	517	318	2025-09-15 02:39:45
627	3	82	518	2026-08-16 19:41:37
628	1	588	789	2026-08-26 07:07:23
633	1	417	708	2026-03-23 23:14:15
640	1	282	945	2026-10-20 02:37:57
645	8	944	214	2025-07-02 07:00:23
646	2	95	16	2025-07-02 18:40:56
648	3	19	226	2026-10-10 23:50:40
649	4	49	454	2025-01-02 03:22:37
652	7	298	602	2026-02-07 01:26:42
662	1	138	854	2025-09-19 03:36:09
667	10	787	330	2026-04-23 16:20:32
670	1	587	317	2025-07-24 08:04:39
683	4	743	827	2026-03-08 09:58:17
684	9	495	490	2025-04-06 01:15:49
686	4	920	948	2025-03-06 17:36:57
694	4	18	522	2026-08-31 08:29:47
709	10	49	122	2025-01-17 09:07:59
727	8	499	566	2026-04-08 11:27:31
736	1	379	677	2025-04-21 15:47:13
738	4	321	637	2026-03-10 17:04:15
744	1	90	708	2025-09-17 13:25:36
753	7	516	370	2025-11-13 10:44:22
757	1	440	593	2026-02-10 07:01:18
768	4	157	747	2026-07-20 07:54:06
772	2	383	613	2026-11-04 04:51:09
786	3	640	38	2025-11-20 15:49:53
798	9	502	11	2026-05-21 00:32:50
811	1	798	71	2026-11-07 09:43:44
820	5	852	391	2025-05-29 15:50:57
821	9	199	490	2026-12-24 05:28:30
828	8	171	643	2025-10-10 10:48:13
838	6	325	434	2025-05-16 06:21:32
841	10	165	522	2025-03-05 21:25:03
848	10	867	334	2025-12-05 14:50:23
851	5	565	206	2026-07-20 15:31:59
852	8	504	449	2026-04-16 13:08:59
854	1	161	47	2026-02-21 15:27:58
857	7	259	27	2025-01-08 19:11:58
863	5	567	259	2026-12-29 00:11:54
871	4	922	537	2026-07-22 17:04:36
887	4	282	678	2026-05-28 16:27:32
893	3	662	534	2026-10-17 00:40:35
895	8	565	266	2026-08-11 00:08:47
897	7	468	887	2026-02-13 23:24:54
899	5	449	321	2025-09-02 21:28:48
913	6	935	790	2026-04-03 09:54:58
921	5	602	263	2026-11-02 09:12:23
924	9	535	677	2025-06-17 23:42:04
925	3	848	430	2026-05-21 03:42:44
926	7	237	47	2026-04-17 05:50:36
927	3	966	284	2026-08-05 13:02:02
930	9	449	341	2025-12-30 22:39:00
931	2	215	11	2025-08-22 17:49:05
934	7	262	285	2026-02-17 13:24:05
946	8	703	9	2026-07-23 15:56:17
958	3	491	326	2026-11-16 06:25:31
959	10	265	309	2025-09-12 22:50:09
971	1	158	566	2026-11-07 17:25:31
972	4	415	163	2026-11-12 04:10:14
975	1	316	153	2025-06-18 21:43:12
982	2	163	334	2026-08-09 12:23:11
984	9	24	375	2025-08-04 17:12:10
989	6	640	613	2026-04-16 12:16:40
995	4	90	243	2026-07-22 14:07:26
996	4	187	75	2025-06-16 14:12:58
997	1	885	786	2026-09-29 11:57:16
1007	6	699	934	2026-04-16 03:29:20.740247
1008	4	699	934	2026-04-19 05:37:19.525268
1009	2	699	934	2026-04-15 08:26:13.998318
1010	7	699	934	2026-04-16 16:20:27.953076
1011	1	699	934	2026-04-17 01:01:53.996607
1012	3	699	934	2026-04-14 18:30:09.965884
1025	6	342	780	2025-10-10 00:43:41.413159
1026	4	342	780	2025-10-09 17:15:32.583562
1027	2	342	780	2025-10-09 21:03:04.207622
1028	7	342	780	2025-10-09 16:34:06.028573
1029	1	342	780	2025-10-09 10:36:58.852861
1030	3	342	780	2025-10-09 22:31:59.912733
1049	6	688	544	2025-12-29 06:24:25.153387
1050	4	688	544	2025-12-27 20:21:25.205559
1051	2	688	544	2026-01-07 02:40:40.362914
1052	7	688	544	2026-01-06 09:13:53.061708
1053	1	688	544	2026-01-01 18:08:08.898865
1054	3	688	544	2026-01-05 08:01:17.143363
1079	6	727	284	2025-12-19 05:00:14.391656
1080	4	727	284	2025-12-20 07:19:37.089263
1081	2	727	284	2025-12-18 23:23:08.784751
1082	7	727	284	2025-12-19 02:14:26.564818
1083	1	727	284	2025-12-17 00:29:10.375034
1084	3	727	284	2025-12-20 20:20:12.215896
1085	6	379	318	2025-08-27 17:34:51.284375
1086	4	379	318	2025-09-08 11:56:45.065581
1087	2	379	318	2025-08-30 19:24:24.811387
1088	7	379	318	2025-09-02 17:52:36.355922
1089	1	379	318	2025-09-10 05:43:24.944712
1090	3	379	318	2025-08-31 11:14:11.095469
1139	6	595	708	2025-04-23 05:25:26.834311
1140	4	595	708	2025-04-16 20:59:02.970049
1141	2	595	708	2025-04-27 13:21:16.224376
1142	7	595	708	2025-04-26 03:21:55.496008
1143	1	595	708	2025-04-19 13:45:28.527435
1144	3	595	708	2025-04-19 01:06:32.41347
1163	6	303	887	2025-08-12 00:36:56.375698
1164	4	303	887	2025-08-11 01:46:25.489149
1165	2	303	887	2025-08-12 12:28:26.710691
1166	7	303	887	2025-08-11 10:46:31.37312
1167	1	303	887	2025-08-10 21:22:17.744886
1168	3	303	887	2025-08-11 02:46:44.212109
1223	6	244	827	2025-11-03 08:02:53.808858
1224	4	244	827	2025-11-03 19:12:17.970381
1225	2	244	827	2025-10-30 20:38:15.260902
1226	7	244	827	2025-10-25 16:19:31.085242
1227	1	244	827	2025-11-02 20:27:14.27968
1228	3	244	827	2025-10-28 06:57:20.999835
1253	6	814	581	2025-03-01 13:58:26.941251
1254	4	814	581	2025-03-02 14:07:32.805229
1255	2	814	581	2025-03-01 11:30:18.04935
1256	7	814	581	2025-03-03 08:38:46.741462
1257	1	814	581	2025-03-04 07:11:14.199626
1258	3	814	581	2025-02-25 01:00:23.868306
1259	6	903	783	2025-09-04 21:25:52.958588
1260	4	903	783	2025-09-04 13:46:09.819253
1261	2	903	783	2025-09-03 16:45:27.38622
1262	7	903	783	2025-09-02 12:26:04.553681
1263	1	903	783	2025-09-04 20:17:56.709052
1264	3	903	783	2025-09-07 09:38:35.948427
1307	6	699	740	2026-04-23 06:15:00.0245
1308	4	699	740	2026-04-26 03:40:50.054017
1309	2	699	740	2026-04-27 02:48:33.318648
1310	7	699	740	2026-04-25 05:46:21.838332
1311	1	699	740	2026-04-30 18:29:55.229141
1312	3	699	740	2026-04-25 03:22:45.141032
1361	6	576	321	2025-06-14 17:17:07.257984
1362	4	576	321	2025-06-17 04:25:58.917132
1363	2	576	321	2025-06-16 02:40:52.021826
1364	7	576	321	2025-06-20 08:31:49.92734
1365	1	576	321	2025-06-20 15:07:55.984537
1366	3	576	321	2025-06-21 12:19:53.434392
1367	6	222	321	2025-06-17 19:07:01.327915
1368	4	222	321	2025-06-17 21:03:16.85074
1369	2	222	321	2025-06-15 21:19:39.866045
1370	7	222	321	2025-06-20 01:12:36.214184
1371	1	222	321	2025-06-13 06:36:52.470861
1372	3	222	321	2025-06-17 02:27:42.943269
1415	6	463	96	2025-05-19 03:16:48.296433
1416	4	463	96	2025-05-16 14:36:41.681725
1417	2	463	96	2025-05-11 10:05:25.188603
1418	7	463	96	2025-05-15 10:56:28.230733
1419	1	463	96	2025-05-11 07:22:11.03201
1420	3	463	96	2025-05-15 06:41:47.290562
1421	6	595	341	2025-04-09 13:15:57.153174
1422	4	595	341	2025-04-06 00:00:12.620686
1423	2	595	341	2025-04-06 10:33:34.536561
1424	7	595	341	2025-04-09 23:10:26.459643
1425	1	595	341	2025-04-06 11:18:35.339897
1426	3	595	341	2025-04-09 14:09:27.265321
1451	6	877	168	2026-05-26 23:20:43.447863
1452	4	877	168	2026-05-27 03:02:47.436247
1453	2	877	168	2026-05-26 21:26:08.944939
1454	7	877	168	2026-05-25 22:18:59.468347
1455	1	877	168	2026-05-27 05:29:27.167604
1456	3	877	168	2026-05-27 18:56:25.616501
1475	6	583	283	2025-08-02 21:36:20.74338
1476	4	583	283	2025-08-02 04:23:32.04903
1477	2	583	283	2025-08-01 12:16:07.535884
1478	7	583	283	2025-07-27 04:26:52.102874
1479	1	583	283	2025-07-31 04:18:32.760572
1480	3	583	283	2025-07-21 20:33:04.559423
1481	6	494	887	2025-08-11 13:12:08.831737
1482	4	494	887	2025-08-11 10:47:36.719055
1483	2	494	887	2025-08-11 17:01:58.012252
1484	7	494	887	2025-08-10 19:02:18.850355
1485	1	494	887	2025-08-10 23:44:38.184259
1486	3	494	887	2025-08-12 00:11:36.557484
1499	6	645	545	2026-05-29 00:30:38.623795
1500	4	645	545	2026-05-29 04:29:03.708564
1501	2	645	545	2026-05-28 21:12:13.993607
1502	7	645	545	2026-05-29 02:10:48.909266
1503	1	645	545	2026-05-29 01:05:10.602913
1504	3	645	545	2026-05-28 19:28:00.349216
1583	6	784	957	2026-02-05 07:28:05.750454
1584	4	784	957	2026-02-12 06:45:47.79144
1585	2	784	957	2026-02-04 23:55:39.181571
1586	7	784	957	2026-02-09 17:30:20.043001
1587	1	784	957	2026-02-10 22:34:38.500819
1588	3	784	957	2026-02-03 11:32:24.105013
1769	6	401	786	2025-01-28 04:48:46.125589
1770	4	401	786	2025-01-21 22:39:12.952442
1771	2	401	786	2025-01-19 10:20:21.791684
1772	7	401	786	2025-01-24 17:24:56.071997
1773	1	401	786	2025-01-22 20:04:32.110182
1774	3	401	786	2025-01-21 22:53:14.777438
1781	6	916	776	2025-12-29 03:44:50.812956
1782	4	916	776	2025-12-29 11:52:30.079606
1783	2	916	776	2025-12-28 01:28:53.058653
1784	7	916	776	2025-12-28 20:24:50.376581
1785	1	916	776	2025-12-29 11:58:53.728277
1786	3	916	776	2025-12-27 15:31:17.552334
1859	6	242	454	2026-02-11 05:49:05.159918
1860	4	242	454	2026-02-09 03:09:10.281868
1861	2	242	454	2026-02-11 18:13:04.010772
1862	7	242	454	2026-02-11 07:42:24.672592
1863	1	242	454	2026-02-12 20:04:55.52515
1864	3	242	454	2026-02-07 19:39:07.091889
1883	6	652	283	2025-07-20 23:35:25.933801
1884	4	652	283	2025-07-21 04:15:40.400497
1885	2	652	283	2025-07-28 00:39:37.515108
1886	7	652	283	2025-08-02 16:00:26.746878
1887	1	652	283	2025-07-31 02:51:36.834859
1888	3	652	283	2025-07-29 15:59:10.717741
1895	6	333	934	2026-04-14 15:29:02.699109
1896	4	333	934	2026-04-14 00:34:22.140623
1897	2	333	934	2026-04-14 15:52:37.012354
1898	7	333	934	2026-04-20 01:01:03.297333
1899	1	333	934	2026-04-15 11:36:43.655597
1900	3	333	934	2026-04-17 21:05:50.623704
1913	6	446	16	2026-04-27 04:20:09.638659
1914	4	446	16	2026-05-06 14:09:01.162784
1915	2	446	16	2026-05-08 01:05:43.454744
1916	7	446	16	2026-04-29 01:33:55.139931
1917	1	446	16	2026-05-09 02:37:10.007249
1918	3	446	16	2026-04-27 16:28:26.685611
1937	6	864	148	2025-11-16 23:29:36.927931
1938	4	864	148	2025-11-16 06:13:19.873426
1939	2	864	148	2025-11-17 10:17:01.621623
1940	7	864	148	2025-11-18 08:01:59.829254
1941	1	864	148	2025-11-17 01:05:49.290986
1942	3	864	148	2025-11-18 23:04:25.595523
1991	6	366	451	2026-03-14 00:12:35.190715
1992	4	366	451	2026-03-16 11:30:14.123486
1993	2	366	451	2026-03-16 00:51:03.019721
1994	7	366	451	2026-03-14 10:33:41.523213
1995	1	366	451	2026-03-14 22:01:46.583738
1996	3	366	451	2026-03-09 20:07:58.848044
2009	6	681	405	2026-02-26 17:57:47.582896
2010	4	681	405	2026-02-26 08:27:17.18236
2011	2	681	405	2026-02-27 01:16:11.877977
2012	7	681	405	2026-02-26 08:27:30.264096
2013	1	681	405	2026-02-26 23:36:01.08514
2014	3	681	405	2026-02-26 15:01:28.346503
2039	6	112	618	2025-10-10 10:24:02.699192
2040	4	112	618	2025-10-05 22:17:30.764006
2041	2	112	618	2025-10-17 02:11:28.15545
2042	7	112	618	2025-10-15 19:59:11.279288
2043	1	112	618	2025-10-11 14:48:57.235657
2044	3	112	618	2025-10-12 23:21:17.482117
2063	6	773	281	2025-05-01 23:14:09.055584
2064	4	773	281	2025-05-01 00:27:53.107291
2065	2	773	281	2025-04-25 08:53:07.363329
2066	7	773	281	2025-04-28 23:45:47.029215
2067	1	773	281	2025-05-03 00:55:04.916649
2068	3	773	281	2025-04-30 10:58:44.521912
2087	6	340	539	2026-04-03 03:20:59.082288
2088	4	340	539	2026-04-11 08:50:46.410046
2089	2	340	539	2026-04-03 04:46:32.501731
2090	7	340	539	2026-04-07 00:28:57.42721
2091	1	340	539	2026-04-03 09:37:24.019062
2092	3	340	539	2026-04-06 10:16:33.927653
2153	6	799	16	2026-05-09 18:46:59.923702
2154	4	799	16	2026-05-06 01:14:10.216294
2155	2	799	16	2026-05-10 23:08:45.769177
2156	7	799	16	2026-05-09 02:54:12.802481
2157	1	799	16	2026-05-10 03:47:16.413583
2158	3	799	16	2026-05-02 16:07:06.486373
2171	6	307	134	2025-04-01 05:05:32.476263
2172	4	307	134	2025-04-01 02:23:55.74897
2173	2	307	134	2025-03-31 15:49:06.028575
2174	7	307	134	2025-03-31 15:31:18.541539
2175	1	307	134	2025-04-02 00:09:52.827427
2176	3	307	134	2025-04-02 21:12:39.774914
2207	6	437	927	2026-03-03 10:04:09.819296
2208	4	437	927	2026-03-02 17:30:46.505834
2209	2	437	927	2026-03-01 23:08:00.169002
2210	7	437	927	2026-03-02 03:12:16.933987
2211	1	437	927	2026-03-05 02:06:32.595531
2212	3	437	927	2026-03-04 16:43:26.382338
2267	6	813	430	2025-12-29 22:50:56.421842
2268	4	813	430	2025-12-25 11:51:52.371982
2269	2	813	430	2026-01-03 15:26:43.562268
2270	7	813	430	2025-12-25 09:40:29.615591
2271	1	813	430	2025-12-27 04:30:55.426006
2272	3	813	430	2025-12-27 00:36:10.712945
2339	6	233	430	2025-12-26 05:36:51.41781
2340	4	233	430	2025-12-28 22:52:28.896096
2341	2	233	430	2026-01-02 12:56:55.657076
2342	7	233	430	2025-12-24 23:05:44.59211
2343	1	233	430	2025-12-26 10:58:54.336559
2344	3	233	430	2026-01-01 01:15:34.245358
2435	6	45	827	2025-10-28 00:40:50.457769
2436	4	45	827	2025-11-05 04:19:53.652879
2437	2	45	827	2025-11-02 12:16:49.230463
2438	7	45	827	2025-11-01 06:29:30.611433
2439	1	45	827	2025-11-02 23:12:51.516874
2440	3	45	827	2025-11-02 17:09:21.908032
2441	6	428	851	2025-07-12 08:55:14.408644
2442	4	428	851	2025-07-15 03:33:09.872416
2443	2	428	851	2025-07-11 08:56:36.480156
2444	7	428	851	2025-07-09 14:31:10.001444
2445	1	428	851	2025-07-10 10:52:54.05576
2446	3	428	851	2025-07-08 14:46:49.78716
2447	6	896	630	2025-07-26 07:36:45.915076
2448	4	896	630	2025-07-28 02:40:23.14449
2449	2	896	630	2025-07-28 17:20:53.648295
2450	7	896	630	2025-07-27 21:54:08.467278
2451	1	896	630	2025-07-31 20:51:28.807516
2452	3	896	630	2025-07-26 09:31:04.12574
2459	6	70	96	2025-05-10 08:25:21.498463
2460	4	70	96	2025-05-14 02:34:06.467299
2461	2	70	96	2025-05-13 12:55:22.916287
2462	7	70	96	2025-05-13 16:59:14.353295
2463	1	70	96	2025-05-12 21:20:44.412609
2464	3	70	96	2025-05-10 21:53:30.481755
2471	6	131	168	2026-05-27 10:32:51.37553
2472	4	131	168	2026-05-25 07:14:09.924547
2473	2	131	168	2026-05-25 12:05:10.685596
2474	7	131	168	2026-05-25 06:46:42.897076
2475	1	131	168	2026-05-26 08:44:38.409457
2476	3	131	168	2026-05-25 11:42:39.361052
2483	6	831	963	2026-03-04 09:58:41.51142
2484	4	831	963	2026-03-05 16:36:06.152857
2485	2	831	963	2026-03-04 22:59:55.786617
2486	7	831	963	2026-03-04 07:59:06.810105
2487	1	831	963	2026-03-03 13:18:31.323381
2488	3	831	963	2026-03-04 07:24:17.953834
2513	6	211	221	2025-12-11 10:14:35.26597
2514	4	211	221	2025-12-15 04:18:13.240066
2515	2	211	221	2025-12-13 02:41:57.442086
2516	7	211	221	2025-12-07 23:34:35.638494
2517	1	211	221	2025-12-18 02:21:48.36936
2518	3	211	221	2025-12-09 17:50:35.25957
2519	6	296	321	2025-06-21 10:53:20.514364
2520	4	296	321	2025-06-19 09:58:34.596928
2521	2	296	321	2025-06-20 03:32:32.79661
2522	7	296	321	2025-06-21 08:58:57.378698
2523	1	296	321	2025-06-13 07:22:22.852981
2524	3	296	321	2025-06-21 08:09:52.625658
2531	6	896	668	2025-03-28 20:14:44.349073
2532	4	896	668	2025-04-05 00:05:35.77155
2533	2	896	668	2025-03-30 18:01:39.002094
2534	7	896	668	2025-03-26 12:59:13.077427
2535	1	896	668	2025-03-29 08:24:05.258724
2536	3	896	668	2025-04-01 01:51:31.997396
2543	6	426	243	2025-12-31 15:47:09.292602
2544	4	426	243	2026-01-02 22:18:25.405488
2545	2	426	243	2026-01-01 23:38:53.388936
2546	7	426	243	2026-01-01 02:51:00.936853
2547	1	426	243	2026-01-03 09:24:47.597279
2548	3	426	243	2026-01-01 04:50:50.603561
2549	6	111	602	2026-04-27 04:53:52.622175
2550	4	111	602	2026-04-19 13:50:07.921664
2551	2	111	602	2026-04-26 12:08:28.15121
2552	7	111	602	2026-04-20 12:09:02.735759
2553	1	111	602	2026-04-20 12:26:37.40528
2554	3	111	602	2026-04-18 18:43:29.276612
2573	6	647	124	2026-03-19 18:39:58.855878
2574	4	647	124	2026-03-20 07:17:01.372163
2575	2	647	124	2026-03-18 10:49:32.821225
2576	7	647	124	2026-03-18 10:11:21.757442
2577	1	647	124	2026-03-19 07:11:19.324714
2578	3	647	124	2026-03-18 03:03:39.728841
2585	6	673	490	2025-10-22 03:13:01.375704
2586	4	673	490	2025-10-23 17:49:41.053589
2587	2	673	490	2025-10-22 13:38:32.385598
2588	7	673	490	2025-10-23 10:30:58.371479
2589	1	673	490	2025-10-22 05:50:55.87628
2590	3	673	490	2025-10-22 19:29:11.08605
2609	6	480	763	2026-04-02 21:15:37.569597
2610	4	480	763	2026-04-03 13:04:26.488456
2611	2	480	763	2026-03-30 18:45:39.125839
2612	7	480	763	2026-03-29 12:39:00.684468
2613	1	480	763	2026-03-29 13:07:19.714809
2614	3	480	763	2026-03-30 15:52:12.977913
2615	6	147	266	2025-05-18 04:44:14.463084
2616	4	147	266	2025-05-25 06:21:49.019489
2617	2	147	266	2025-05-23 17:44:22.434127
2618	7	147	266	2025-05-23 10:39:13.145938
2619	1	147	266	2025-05-15 23:32:01.498995
2620	3	147	266	2025-05-19 09:02:54.924609
2645	6	752	637	2025-05-30 09:14:43.439813
2646	4	752	637	2025-05-30 14:25:33.827783
2647	2	752	637	2025-05-30 11:34:25.888477
2648	7	752	637	2025-05-30 07:20:11.291311
2649	1	752	637	2025-05-30 10:03:21.966772
2650	3	752	637	2025-05-30 06:10:33.918856
2651	6	673	534	2026-01-13 02:45:18.647881
2652	4	673	534	2026-01-14 10:19:22.506375
2653	2	673	534	2026-01-13 05:07:09.527709
2654	7	673	534	2026-01-15 02:14:28.503155
2655	1	673	534	2026-01-13 19:56:44.810876
2656	3	673	534	2026-01-18 17:58:25.849019
2675	6	836	228	2025-10-10 21:05:26.021639
2676	4	836	228	2025-10-05 01:56:51.427774
2677	2	836	228	2025-10-03 10:10:07.262189
2678	7	836	228	2025-10-10 11:32:53.156502
2679	1	836	228	2025-10-09 09:06:35.564107
2680	3	836	228	2025-10-08 10:42:34.086341
2741	6	933	963	2026-03-05 04:19:58.20184
2742	4	933	963	2026-03-03 17:37:19.131644
2743	2	933	963	2026-03-04 20:27:32.42511
2744	7	933	963	2026-03-05 18:07:57.746311
2745	1	933	963	2026-03-04 10:56:57.069134
2746	3	933	963	2026-03-03 17:20:45.248258
2783	6	165	907	2025-05-29 21:18:37.130555
2784	4	165	907	2025-06-04 20:18:12.531768
2785	2	165	907	2025-05-30 18:59:42.859325
2786	7	165	907	2025-06-01 23:38:46.23327
2787	1	165	907	2025-05-26 03:07:50.833441
2788	3	165	907	2025-06-05 01:25:50.721702
2813	6	435	228	2025-10-06 01:29:55.765299
2814	4	435	228	2025-10-01 17:47:32.876641
2815	2	435	228	2025-10-05 13:51:35.21259
2816	7	435	228	2025-09-30 23:36:31.961555
2817	1	435	228	2025-09-28 10:50:36.692178
2818	3	435	228	2025-10-02 22:08:27.159506
2819	6	246	764	2026-03-04 22:27:49.581099
2820	4	246	764	2026-03-01 10:54:15.085091
2821	2	246	764	2026-03-05 01:27:35.418845
2822	7	246	764	2026-03-02 18:03:12.550397
2823	1	246	764	2026-03-05 15:02:28.063498
2824	3	246	764	2026-02-28 17:05:46.378003
2825	6	361	468	2025-11-17 05:49:02.083518
2826	4	361	468	2025-11-11 23:47:43.167181
2827	2	361	468	2025-11-21 16:47:34.686143
2828	7	361	468	2025-11-19 23:58:14.381326
2829	1	361	468	2025-11-12 07:08:51.946177
2830	3	361	468	2025-11-23 23:41:36.341593
2831	6	33	121	2025-10-10 07:55:54.557151
2832	4	33	121	2025-10-14 05:37:21.490243
2833	2	33	121	2025-10-12 02:46:15.670824
2834	7	33	121	2025-10-11 03:01:27.699013
2835	1	33	121	2025-10-10 03:14:24.584092
2836	3	33	121	2025-10-10 10:56:34.132837
2849	6	670	124	2026-03-20 02:33:35.849869
2850	4	670	124	2026-03-19 08:06:28.065174
2851	2	670	124	2026-03-18 10:53:00.227135
2852	7	670	124	2026-03-19 16:46:49.681517
2853	1	670	124	2026-03-18 15:27:54.593329
2854	3	670	124	2026-03-18 01:13:00.549817
2927	6	110	281	2025-04-23 15:12:26.662214
2928	4	110	281	2025-04-28 09:12:02.708752
2929	2	110	281	2025-04-29 23:09:09.759729
2930	7	110	281	2025-04-25 12:40:46.293985
2931	1	110	281	2025-04-22 13:55:38.157894
2932	3	110	281	2025-04-27 18:11:27.998002
2939	6	203	405	2026-02-26 06:35:39.700933
2940	4	203	405	2026-02-26 17:05:57.658299
2941	2	203	405	2026-02-27 00:41:25.792079
2942	7	203	405	2026-02-26 13:11:18.269204
2943	1	203	405	2026-02-26 20:42:31.608139
2944	3	203	405	2026-02-26 11:26:32.688344
2987	6	429	566	2026-04-14 23:53:16.412372
2988	4	429	566	2026-04-16 06:28:45.3694
2989	2	429	566	2026-04-15 02:38:15.358004
2990	7	429	566	2026-04-18 05:12:43.197074
2991	1	429	566	2026-04-16 16:58:40.406654
2992	3	429	566	2026-04-18 01:25:28.280447
3005	6	11	73	2025-06-13 06:54:58.507578
3006	4	11	73	2025-06-07 09:31:07.898117
3007	2	11	73	2025-06-07 00:52:22.90637
3008	7	11	73	2025-06-14 16:41:05.370881
3009	1	11	73	2025-06-12 20:57:36.819719
3010	3	11	73	2025-06-08 06:34:14.171163
3011	6	85	671	2026-05-15 13:58:30.242546
3012	4	85	671	2026-05-19 13:55:37.416059
3013	2	85	671	2026-05-21 05:35:54.617292
3014	7	85	671	2026-05-15 13:45:45.820713
3015	1	85	671	2026-05-19 05:55:33.957085
3016	3	85	671	2026-05-20 18:12:43.594529
3059	6	229	71	2026-05-09 01:01:44.407824
3060	4	229	71	2026-05-09 15:24:48.931912
3061	2	229	71	2026-05-09 01:11:40.768744
3062	7	229	71	2026-05-11 06:09:11.792747
3063	1	229	71	2026-05-09 13:15:08.264645
3064	3	229	71	2026-05-09 17:52:40.103999
3071	6	390	827	2025-11-02 16:59:31.576017
3072	4	390	827	2025-11-01 23:46:47.762749
3073	2	390	827	2025-10-24 05:30:12.945854
3074	7	390	827	2025-11-04 05:16:44.823396
3075	1	390	827	2025-11-02 20:09:58.126051
3076	3	390	827	2025-10-26 14:44:57.606253
3077	6	256	945	2025-12-26 15:30:56.607679
3078	4	256	945	2025-12-29 06:05:51.15047
3079	2	256	945	2025-12-26 15:17:51.193507
3080	7	256	945	2025-12-27 18:52:11.354473
3081	1	256	945	2025-12-24 22:22:55.190783
3082	3	256	945	2025-12-25 07:15:00.313953
3095	6	954	96	2025-05-13 22:02:24.193285
3096	4	954	96	2025-05-11 14:29:52.658045
3097	2	954	96	2025-05-12 21:56:50.72507
3098	7	954	96	2025-05-08 23:50:11.807752
3099	1	954	96	2025-05-09 13:41:20.391518
3100	3	954	96	2025-05-08 15:32:45.342399
3107	6	626	322	2025-10-29 12:28:45.121571
3108	4	626	322	2025-10-29 18:25:18.943319
3109	2	626	322	2025-10-28 14:05:55.197696
3110	7	626	322	2025-10-31 12:03:50.199283
3111	1	626	322	2025-10-30 04:48:36.66463
3112	3	626	322	2025-10-25 21:58:21.280222
3113	6	947	71	2026-05-11 00:59:27.760631
3114	4	947	71	2026-05-09 02:08:10.230238
3115	2	947	71	2026-05-09 19:12:45.25657
3116	7	947	71	2026-05-09 07:10:38.721422
3117	1	947	71	2026-05-08 19:20:45.097654
3118	3	947	71	2026-05-10 18:29:23.994778
3143	6	380	228	2025-10-04 14:19:30.482021
3144	4	380	228	2025-10-10 03:46:11.768225
3145	2	380	228	2025-10-09 09:26:18.79278
3146	7	380	228	2025-10-05 22:45:35.698468
3147	1	380	228	2025-10-09 02:45:27.487223
3148	3	380	228	2025-10-09 07:28:25.24372
3173	6	559	490	2025-10-22 14:06:21.319664
3174	4	559	490	2025-10-21 10:45:01.509859
3175	2	559	490	2025-10-23 00:49:35.762701
3176	7	559	490	2025-10-21 15:38:11.515492
3177	1	559	490	2025-10-23 21:43:25.784788
3178	3	559	490	2025-10-23 16:23:40.442178
3191	6	485	350	2026-02-03 08:59:55.885745
3192	4	485	350	2026-02-05 08:29:03.546402
3193	2	485	350	2026-02-04 10:12:18.527448
3194	7	485	350	2026-02-04 16:51:45.06464
3195	1	485	350	2026-02-02 19:03:26.578391
3196	3	485	350	2026-02-02 14:43:15.567087
3227	6	553	321	2025-06-12 17:20:11.269562
3228	4	553	321	2025-06-12 19:31:21.791069
3229	2	553	321	2025-06-20 05:16:20.783622
3230	7	553	321	2025-06-21 16:04:38.451656
3231	1	553	321	2025-06-20 10:12:16.63758
3232	3	553	321	2025-06-14 01:35:36.894199
3251	6	724	468	2025-11-22 02:22:45.865403
3252	4	724	468	2025-11-10 13:52:51.082533
3253	2	724	468	2025-11-20 05:28:07.481483
3254	7	724	468	2025-11-10 16:32:12.131308
3255	1	724	468	2025-11-23 12:56:55.989699
3256	3	724	468	2025-11-23 07:36:16.409701
3263	6	331	796	2025-02-21 00:36:51.599986
3264	4	331	796	2025-02-28 23:37:31.01045
3265	2	331	796	2025-02-17 13:03:04.740372
3266	7	331	796	2025-02-15 09:55:37.967575
3267	1	331	796	2025-02-20 03:09:22.24531
3268	3	331	796	2025-02-14 04:23:04.464052
3389	6	898	684	2026-01-31 18:37:38.605706
3390	4	898	684	2026-01-27 19:07:18.370037
3391	2	898	684	2026-01-30 08:30:32.792228
3392	7	898	684	2026-02-04 12:48:13.149841
3393	1	898	684	2026-02-07 09:51:30.187779
3394	3	898	684	2026-02-05 12:15:13.484519
3419	6	773	854	2025-10-08 20:50:21.783029
3420	4	773	854	2025-10-02 18:17:50.164656
3421	2	773	854	2025-10-08 09:52:52.15789
3422	7	773	854	2025-10-07 16:31:27.689157
3423	1	773	854	2025-10-11 02:11:03.007314
3424	3	773	854	2025-10-08 12:28:43.938273
3455	6	368	810	2026-02-08 13:06:06.61828
3456	4	368	810	2026-02-09 17:36:58.762561
3457	2	368	810	2026-02-12 00:16:04.132717
3458	7	368	810	2026-02-08 02:17:04.458129
3459	1	368	810	2026-02-11 13:34:17.032083
3460	3	368	810	2026-02-08 11:33:33.515685
3521	6	628	945	2025-12-24 20:10:21.19364
3522	4	628	945	2025-12-24 09:29:31.179713
3523	2	628	945	2025-12-26 18:10:07.342604
3524	7	628	945	2025-12-24 00:27:09.686693
3525	1	628	945	2025-12-24 06:21:40.95788
3526	3	628	945	2025-12-28 06:26:12.802648
3533	6	452	122	2025-11-02 00:06:08.698866
3534	4	452	122	2025-10-24 14:59:23.198285
3535	2	452	122	2025-10-21 11:32:06.786155
3536	7	452	122	2025-10-21 15:01:38.396652
3537	1	452	122	2025-10-25 08:48:19.817014
3538	3	452	122	2025-10-30 19:19:16.553222
3551	6	397	71	2026-05-08 10:16:43.821418
3552	4	397	71	2026-05-09 06:45:31.354707
3553	2	397	71	2026-05-11 02:40:07.651995
3554	7	397	71	2026-05-09 05:42:58.261854
3555	1	397	71	2026-05-10 07:19:13.772118
3556	3	397	71	2026-05-09 10:35:15.226314
3581	6	178	281	2025-04-30 01:09:44.267793
3582	4	178	281	2025-04-27 10:06:28.886307
3583	2	178	281	2025-05-02 05:37:34.124524
3584	7	178	281	2025-04-22 07:20:33.503695
3585	1	178	281	2025-05-02 13:40:09.660409
3586	3	178	281	2025-05-01 23:19:41.672104
3605	6	23	764	2026-03-01 20:03:33.952804
3606	4	23	764	2026-03-08 18:03:13.037691
3607	2	23	764	2026-03-04 16:31:48.116423
3608	7	23	764	2026-03-04 18:40:36.30665
3609	1	23	764	2026-03-06 11:20:56.410734
3610	3	23	764	2026-03-07 01:44:45.707695
3623	6	640	794	2025-08-05 05:57:21.847228
3624	4	640	794	2025-08-06 23:27:20.302
3625	2	640	794	2025-08-09 08:31:48.214649
3626	7	640	794	2025-08-04 14:32:59.860597
3627	1	640	794	2025-07-31 04:32:03.275539
3628	3	640	794	2025-08-08 22:58:39.860068
3737	6	646	475	2026-01-25 08:15:25.741878
3738	4	646	475	2026-01-24 17:33:30.394255
3739	2	646	475	2026-01-24 22:41:38.667178
3740	7	646	475	2026-01-26 21:36:23.846144
3741	1	646	475	2026-01-27 04:52:43.803405
3742	3	646	475	2026-01-26 13:37:19.537311
3743	6	439	488	2025-01-29 22:20:52.984645
3744	4	439	488	2025-01-27 06:55:09.1535
3745	2	439	488	2025-01-31 09:39:01.244684
3746	7	439	488	2025-01-30 11:43:40.688619
3747	1	439	488	2025-01-28 16:04:09.421777
3748	3	439	488	2025-01-28 22:15:45.70933
3761	6	535	385	2025-11-16 00:50:02.073895
3762	4	535	385	2025-11-14 11:14:41.469945
3763	2	535	385	2025-11-12 22:52:39.813023
3764	7	535	385	2025-11-11 01:04:57.498893
3765	1	535	385	2025-11-13 23:28:59.010248
3766	3	535	385	2025-11-15 06:10:31.030568
3779	6	435	318	2025-09-05 08:45:27.807562
3780	4	435	318	2025-08-31 01:36:47.455568
3781	2	435	318	2025-09-09 07:55:52.929203
3782	7	435	318	2025-09-06 04:04:34.707698
3783	1	435	318	2025-09-08 18:03:30.988582
3784	3	435	318	2025-09-04 08:37:04.85176
3803	6	154	637	2025-05-30 00:16:12.38631
3804	4	154	637	2025-05-30 17:54:53.490874
3805	2	154	637	2025-05-30 15:23:33.394686
3806	7	154	637	2025-05-30 11:43:33.800672
3807	1	154	637	2025-05-30 18:44:55.245798
3808	3	154	637	2025-05-30 08:19:18.200818
3815	6	64	537	2025-11-02 04:16:38.331139
3816	4	64	537	2025-10-26 18:29:34.279248
3817	2	64	537	2025-10-26 18:05:33.816626
3818	7	64	537	2025-10-29 07:30:29.49231
3819	1	64	537	2025-10-31 18:04:57.688166
3820	3	64	537	2025-11-04 17:23:09.011893
3917	6	521	488	2025-01-28 14:46:24.522621
3918	4	521	488	2025-01-27 15:58:11.71483
3919	2	521	488	2025-01-31 02:52:24.510362
3920	7	521	488	2025-01-30 03:17:47.039594
3921	1	521	488	2025-01-29 01:16:27.478703
3922	3	521	488	2025-01-27 20:40:06.656382
3941	6	853	643	2026-01-23 01:18:04.427247
3942	4	853	643	2026-01-26 09:50:40.803705
3943	2	853	643	2026-01-23 18:42:24.846783
3944	7	853	643	2026-01-22 01:17:41.570828
3945	1	853	643	2026-01-26 10:00:32.332629
3946	3	853	643	2026-01-21 20:22:14.890005
3965	6	836	637	2025-05-30 20:11:56.157748
3966	4	836	637	2025-05-30 05:12:51.16955
3967	2	836	637	2025-05-30 11:11:28.001919
3968	7	836	637	2025-05-30 05:25:05.968347
3969	1	836	637	2025-05-30 09:38:07.104236
3970	3	836	637	2025-05-30 04:41:29.222576
3977	6	639	243	2026-01-01 14:14:26.732988
3978	4	639	243	2026-01-01 07:52:43.504617
3979	2	639	243	2025-12-31 12:56:29.223021
3980	7	639	243	2026-01-02 01:53:49.610224
3981	1	639	243	2026-01-03 00:09:00.515079
3982	3	639	243	2026-01-01 05:57:02.454614
3983	6	753	539	2026-04-10 17:32:20.164127
3984	4	753	539	2026-04-04 07:14:06.84505
3985	2	753	539	2026-04-04 23:38:16.115835
3986	7	753	539	2026-04-02 19:47:31.326755
3987	1	753	539	2026-04-12 03:54:29.326349
3988	3	753	539	2026-04-05 05:51:22.734499
3989	6	490	454	2026-02-07 07:58:21.258836
3990	4	490	454	2026-02-14 07:57:41.590835
3991	2	490	454	2026-02-11 10:19:15.794543
3992	7	490	454	2026-02-11 11:09:31.789846
3993	1	490	454	2026-02-10 20:23:10.951839
3994	3	490	454	2026-02-09 23:23:43.179949
4043	6	655	807	2025-08-13 18:09:50.984345
4044	4	655	807	2025-08-11 23:21:34.540023
4045	2	655	807	2025-08-12 08:59:39.397811
4046	7	655	807	2025-08-12 00:14:42.167392
4047	1	655	807	2025-08-12 02:24:31.916268
4048	3	655	807	2025-08-13 00:54:18.080167
4049	6	456	764	2026-03-05 14:35:42.154783
4050	4	456	764	2026-03-05 08:53:20.302463
4051	2	456	764	2026-03-01 08:22:36.172863
4052	7	456	764	2026-03-07 13:13:10.116419
4053	1	456	764	2026-03-06 02:29:57.966987
4054	3	456	764	2026-03-04 13:40:21.76709
4067	6	314	317	2025-07-16 11:31:48.697758
4068	4	314	317	2025-07-16 07:21:56.953752
4069	2	314	317	2025-07-14 16:08:44.33526
4070	7	314	317	2025-07-10 15:39:46.912687
4071	1	314	317	2025-07-09 23:11:12.464478
4072	3	314	317	2025-07-12 05:42:18.187749
4103	6	960	518	2026-02-26 03:02:47.625693
4104	4	960	518	2026-03-05 09:15:19.293401
4105	2	960	518	2026-03-06 06:13:00.093767
4106	7	960	518	2026-03-03 01:29:27.045011
4107	1	960	518	2026-03-05 16:32:30.478634
4108	3	960	518	2026-02-27 12:57:40.510508
4109	6	409	457	2025-03-14 09:41:17.886671
4110	4	409	457	2025-03-19 03:43:12.592471
4111	2	409	457	2025-03-19 13:14:17.910925
4112	7	409	457	2025-03-06 23:10:43.157174
4113	1	409	457	2025-03-12 02:22:58.316189
4114	3	409	457	2025-03-06 20:38:46.868169
4121	6	728	755	2025-03-13 21:42:14.866735
4122	4	728	755	2025-03-11 02:18:18.495502
4123	2	728	755	2025-03-13 18:21:54.416993
4124	7	728	755	2025-03-15 15:17:45.062455
4125	1	728	755	2025-03-16 10:21:47.093179
4126	3	728	755	2025-03-12 19:59:31.478472
4187	6	973	449	2025-07-03 02:16:14.290242
4188	4	973	449	2025-07-05 15:32:35.914438
4189	2	973	449	2025-07-06 09:09:04.262567
4190	7	973	449	2025-07-06 04:58:50.096137
4191	1	973	449	2025-07-06 02:07:57.950967
4192	3	973	449	2025-07-05 16:32:23.522881
4199	6	282	60	2025-02-01 13:35:05.25272
4200	4	282	60	2025-02-02 10:04:48.22584
4201	2	282	60	2025-02-03 06:08:25.651936
4202	7	282	60	2025-02-01 04:24:22.522902
4203	1	282	60	2025-01-30 17:40:21.249423
4204	3	282	60	2025-01-29 02:29:24.258926
4217	6	229	790	2025-02-02 03:32:23.405209
4218	4	229	790	2025-02-03 08:23:27.195354
4219	2	229	790	2025-01-26 17:13:31.880702
4220	7	229	790	2025-02-01 02:31:37.582423
4221	1	229	790	2025-01-25 20:42:07.376218
4222	3	229	790	2025-01-26 13:58:04.221366
4223	6	520	616	2025-07-27 19:04:16.12559
4224	4	520	616	2025-07-26 13:17:49.56951
4225	2	520	616	2025-07-26 13:32:52.76026
4226	7	520	616	2025-07-26 13:15:00.642385
4227	1	520	616	2025-07-27 09:14:16.684241
4228	3	520	616	2025-07-25 12:15:55.96785
4307	6	299	322	2025-10-30 13:16:53.650736
4308	4	299	322	2025-10-28 06:03:18.703909
4309	2	299	322	2025-10-26 06:31:56.304806
4310	7	299	322	2025-10-30 19:10:09.706441
4311	1	299	322	2025-10-28 15:31:22.399923
4312	3	299	322	2025-10-25 06:53:03.829263
4313	6	396	796	2025-02-19 17:28:20.881283
4314	4	396	796	2025-02-16 20:00:06.089575
4315	2	396	796	2025-02-18 03:29:38.571205
4316	7	396	796	2025-02-20 18:03:11.500789
4317	1	396	796	2025-02-20 20:03:53.350526
4318	3	396	796	2025-02-17 23:47:39.819906
4319	6	820	458	2025-07-18 08:42:36.481949
4320	4	820	458	2025-07-09 06:55:18.079767
4321	2	820	458	2025-07-14 16:26:39.890673
4322	7	820	458	2025-07-13 12:11:34.767212
4323	1	820	458	2025-07-18 10:19:49.974509
4324	3	820	458	2025-07-13 09:51:11.242955
4343	6	694	289	2026-03-22 12:12:54.632731
4344	4	694	289	2026-03-21 14:01:41.756612
4345	2	694	289	2026-03-23 12:19:51.789108
4346	7	694	289	2026-03-23 17:32:41.428214
4347	1	694	289	2026-03-22 05:26:30.226349
4348	3	694	289	2026-03-19 03:15:47.517814
4391	6	906	71	2026-05-09 01:47:56.210328
4392	4	906	71	2026-05-08 23:22:10.5257
4393	2	906	71	2026-05-10 05:29:58.241522
4394	7	906	71	2026-05-09 13:31:56.905095
4395	1	906	71	2026-05-08 19:03:51.355796
4396	3	906	71	2026-05-09 15:37:33.87012
4415	6	1	581	2025-02-23 00:14:47.758018
4416	4	1	581	2025-02-27 08:42:50.061554
4417	2	1	581	2025-02-26 07:02:36.165904
4418	7	1	581	2025-02-24 08:11:08.645443
4419	1	1	581	2025-02-23 19:59:36.061309
4420	3	1	581	2025-03-04 16:46:28.615876
4421	6	915	852	2026-02-19 09:17:57.16588
4422	4	915	852	2026-02-19 00:39:29.317256
4423	2	915	852	2026-02-18 23:06:47.319942
4424	7	915	852	2026-02-18 23:35:12.288778
4425	1	915	852	2026-02-18 21:25:57.533423
4426	3	915	852	2026-02-18 16:51:24.013836
4427	6	248	233	2025-12-24 10:51:17.020596
4428	4	248	233	2025-12-21 11:41:03.872994
4429	2	248	233	2025-12-24 18:21:01.903534
4430	7	248	233	2025-12-25 16:39:59.542448
4431	1	248	233	2025-12-22 11:14:34.712633
4432	3	248	233	2025-12-25 10:16:06.135205
4469	6	852	616	2025-07-27 03:39:32.855001
4470	4	852	616	2025-07-26 13:46:56.286341
4471	2	852	616	2025-07-26 13:03:27.014166
4472	7	852	616	2025-07-26 12:55:04.90021
4473	1	852	616	2025-07-26 10:19:21.234428
4474	3	852	616	2025-07-26 19:49:08.976985
4475	6	536	226	2026-01-23 05:37:05.626211
4476	4	536	226	2026-01-22 14:38:03.83253
4477	2	536	226	2026-01-27 01:38:59.391032
4478	7	536	226	2026-01-29 12:27:03.520918
4479	1	536	226	2026-01-31 05:59:32.592944
4480	3	536	226	2026-01-31 12:14:01.22242
4493	6	817	907	2025-06-04 17:15:43.475351
4494	4	817	907	2025-06-07 00:25:27.713164
4495	2	817	907	2025-06-02 18:07:08.595932
4496	7	817	907	2025-06-07 07:52:25.582813
4497	1	817	907	2025-05-26 02:21:52.327492
4498	3	817	907	2025-05-27 17:42:00.742581
4535	6	518	767	2026-03-23 21:28:43.79605
4536	4	518	767	2026-03-22 04:47:22.23111
4537	2	518	767	2026-03-25 03:50:42.939474
4538	7	518	767	2026-03-24 00:49:45.451913
4539	1	518	767	2026-03-21 23:34:16.915837
4540	3	518	767	2026-03-23 13:01:17.30443
4559	6	532	323	2025-12-15 22:16:45.771991
4560	4	532	323	2025-12-22 19:37:15.723841
4561	2	532	323	2025-12-16 19:12:24.296912
4562	7	532	323	2025-12-21 05:32:11.659668
4563	1	532	323	2025-12-24 19:23:20.766958
4564	3	532	323	2025-12-26 11:12:37.103174
4565	6	806	294	2025-01-17 03:22:29.963419
4566	4	806	294	2025-01-19 09:47:21.202732
4567	2	806	294	2025-01-17 13:35:18.703488
4568	7	806	294	2025-01-20 19:37:21.265198
4569	1	806	294	2025-01-20 20:18:26.222005
4570	3	806	294	2025-01-19 11:19:31.92126
4607	6	181	780	2025-10-09 14:31:08.860419
4608	4	181	780	2025-10-10 03:12:28.048938
4609	2	181	780	2025-10-09 17:30:10.621618
4610	7	181	780	2025-10-10 01:17:12.12072
4611	1	181	780	2025-10-09 16:03:10.862803
4612	3	181	780	2025-10-09 10:11:50.672537
4613	6	367	140	2026-04-28 07:02:18.032678
4614	4	367	140	2026-05-03 23:03:02.289436
4615	2	367	140	2026-04-30 17:01:40.794995
4616	7	367	140	2026-04-29 20:24:54.083057
4617	1	367	140	2026-04-29 06:22:13.995833
4618	3	367	140	2026-04-29 01:40:59.499454
4643	6	536	134	2025-03-27 13:10:25.034939
4644	4	536	134	2025-03-25 16:13:26.935529
4645	2	536	134	2025-03-31 19:32:32.704588
4646	7	536	134	2025-03-24 15:38:50.395823
4647	1	536	134	2025-04-02 20:45:09.295216
4648	3	536	134	2025-03-23 15:54:45.015256
4655	6	741	16	2026-05-07 22:42:32.873736
4656	4	741	16	2026-05-09 02:29:48.312087
4657	2	741	16	2026-05-01 07:01:47.859801
4658	7	741	16	2026-05-04 10:32:29.631024
4659	1	741	16	2026-05-10 20:01:51.802527
4660	3	741	16	2026-05-09 07:11:24.790846
4709	6	816	140	2026-04-30 00:59:25.945625
4710	4	816	140	2026-05-03 03:48:53.320129
4711	2	816	140	2026-05-02 14:35:26.674324
4712	7	816	140	2026-04-29 15:21:13.553125
4713	1	816	140	2026-05-02 04:42:38.438481
4714	3	816	140	2026-05-01 01:35:42.612301
4763	6	935	121	2025-10-11 05:36:33.924063
4764	4	935	121	2025-10-13 09:25:28.143467
4765	2	935	121	2025-10-10 05:58:34.200014
4766	7	935	121	2025-10-07 21:42:19.030257
4767	1	935	121	2025-10-12 10:06:07.058844
4768	3	935	121	2025-10-11 17:40:03.968326
4769	6	561	214	2025-10-04 14:26:38.151474
4770	4	561	214	2025-10-05 21:45:28.394885
4771	2	561	214	2025-10-05 17:01:40.224287
4772	7	561	214	2025-10-05 09:20:04.736015
4773	1	561	214	2025-10-06 09:11:43.944452
4774	3	561	214	2025-10-03 21:30:48.107672
4775	6	162	786	2025-01-16 16:27:41.99593
4776	4	162	786	2025-01-23 15:08:46.61652
4777	2	162	786	2025-01-26 19:02:12.714529
4778	7	162	786	2025-01-22 19:24:47.734219
4779	1	162	786	2025-01-28 07:19:44.184628
4780	3	162	786	2025-01-26 23:18:49.267326
4781	6	78	851	2025-07-13 00:21:36.237655
4782	4	78	851	2025-07-15 02:52:47.362972
4783	2	78	851	2025-07-09 08:23:56.59711
4784	7	78	851	2025-07-13 02:25:42.985525
4785	1	78	851	2025-07-13 12:42:33.117209
4786	3	78	851	2025-07-15 20:42:09.644775
4817	6	464	447	2025-09-11 23:49:45.201103
4818	4	464	447	2025-09-12 14:04:33.467576
4819	2	464	447	2025-09-12 07:15:14.09781
4820	7	464	447	2025-09-12 12:35:17.03058
4821	1	464	447	2025-09-11 21:07:15.872419
4822	3	464	447	2025-09-11 23:48:08.537881
4829	6	288	891	2026-04-13 12:16:17.61069
4830	4	288	891	2026-04-07 05:41:25.697601
4831	2	288	891	2026-04-14 16:20:15.224102
4832	7	288	891	2026-04-05 06:27:27.336884
4833	1	288	891	2026-04-09 05:58:26.968571
4834	3	288	891	2026-04-08 19:22:40.044475
4865	6	419	796	2025-02-17 22:37:11.64382
4866	4	419	796	2025-02-19 15:08:35.318947
4867	2	419	796	2025-02-15 21:28:00.688917
4868	7	419	796	2025-02-17 05:59:39.096828
4869	1	419	796	2025-02-21 21:29:12.982718
4870	3	419	796	2025-02-16 19:47:12.800447
4871	6	332	458	2025-07-11 11:28:59.296523
4872	4	332	458	2025-07-11 20:03:51.643316
4873	2	332	458	2025-07-10 02:56:10.454914
4874	7	332	458	2025-07-17 22:41:25.375099
4875	1	332	458	2025-07-17 10:26:48.604305
4876	3	332	458	2025-07-13 13:22:47.5347
4907	6	490	544	2026-01-04 00:30:34.473266
4908	4	490	544	2026-01-03 11:30:06.411671
4909	2	490	544	2026-01-07 05:02:00.951788
4910	7	490	544	2026-01-02 22:32:58.349145
4911	1	490	544	2025-12-29 00:38:38.778248
4912	3	490	544	2026-01-05 00:25:32.009033
4931	6	418	838	2025-06-27 19:04:47.560939
4932	4	418	838	2025-06-26 14:51:07.300605
4933	2	418	838	2025-06-26 18:06:08.923607
4934	7	418	838	2025-06-28 15:36:22.799749
4935	1	418	838	2025-06-25 23:35:47.541471
4936	3	418	838	2025-06-27 00:42:19.033466
5009	6	488	790	2025-01-26 02:53:01.607179
5010	4	488	790	2025-02-06 18:44:44.284887
5011	2	488	790	2025-01-28 11:57:45.733641
5012	7	488	790	2025-01-28 12:04:04.661787
5013	1	488	790	2025-02-05 13:06:35.802913
5014	3	488	790	2025-02-07 00:06:12.102341
5033	6	202	767	2026-03-24 18:19:37.382193
5034	4	202	767	2026-03-24 09:13:02.079718
5035	2	202	767	2026-03-22 17:22:03.360047
5036	7	202	767	2026-03-24 14:20:18.325422
5037	1	202	767	2026-03-25 10:53:30.028559
5038	3	202	767	2026-03-24 14:20:43.890382
5063	6	419	544	2026-01-03 05:13:07.605195
5064	4	419	544	2026-01-02 15:55:46.509978
5065	2	419	544	2025-12-30 02:54:58.134508
5066	7	419	544	2025-12-31 01:09:31.277389
5067	1	419	544	2026-01-03 03:35:46.888639
5068	3	419	544	2026-01-01 19:45:59.828539
5087	6	613	581	2025-02-27 15:30:30.374743
5088	4	613	581	2025-02-22 09:49:43.886932
5089	2	613	581	2025-02-26 21:35:06.701805
5090	7	613	581	2025-02-24 06:47:12.380836
5091	1	613	581	2025-03-04 08:21:44.284658
5092	3	613	581	2025-03-03 01:08:52.710866
5105	6	301	404	2025-11-07 01:06:04.465967
5106	4	301	404	2025-11-07 16:36:23.590878
5107	2	301	404	2025-11-09 02:22:04.665598
5108	7	301	404	2025-11-06 08:19:00.002235
5109	1	301	404	2025-11-06 01:17:21.211528
5110	3	301	404	2025-11-07 13:24:56.926445
5111	6	93	318	2025-08-27 10:09:13.972084
5112	4	93	318	2025-09-09 04:36:40.570645
5113	2	93	318	2025-09-09 05:54:06.461876
5114	7	93	318	2025-08-28 21:59:56.358504
5115	1	93	318	2025-09-06 11:36:08.251777
5116	3	93	318	2025-09-02 02:35:29.201417
5171	6	783	827	2025-10-23 10:31:21.960186
5172	4	783	827	2025-11-02 10:25:29.513019
5173	2	783	827	2025-10-22 14:17:33.487097
5174	7	783	827	2025-10-23 20:56:53.301935
5175	1	783	827	2025-10-28 01:38:29.062445
5176	3	783	827	2025-11-03 13:39:26.996399
5219	6	17	452	2025-04-04 10:41:21.453883
5220	4	17	452	2025-04-03 11:10:32.926528
5221	2	17	452	2025-04-04 10:04:37.304599
5222	7	17	452	2025-04-02 15:50:08.351634
5223	1	17	452	2025-04-03 10:56:57.164643
5224	3	17	452	2025-04-03 16:15:02.844464
5231	6	57	613	2025-11-12 18:36:07.114821
5232	4	57	613	2025-11-11 17:53:41.80216
5233	2	57	613	2025-11-13 12:38:52.42318
5234	7	57	613	2025-11-12 13:59:36.230031
5235	1	57	613	2025-11-09 00:05:09.669748
5236	3	57	613	2025-11-12 09:20:32.753395
5237	6	57	613	2025-11-12 08:25:54.678717
5238	4	57	613	2025-11-10 12:39:53.162254
5239	2	57	613	2025-11-11 02:32:37.927076
5240	7	57	613	2025-11-09 05:19:21.071287
5241	1	57	613	2025-11-10 15:05:44.193151
5242	3	57	613	2025-11-12 12:45:10.479076
5273	6	38	809	2025-03-20 11:14:37.896632
5274	4	38	809	2025-03-24 14:21:53.517192
5275	2	38	809	2025-03-19 21:27:48.079884
5276	7	38	809	2025-03-23 03:25:36.850838
5277	1	38	809	2025-03-25 08:02:38.252209
5278	3	38	809	2025-03-20 07:01:15.217977
5279	6	49	370	2025-08-10 00:14:52.955168
5280	4	49	370	2025-08-17 09:00:40.950455
5281	2	49	370	2025-08-13 11:41:00.840087
5282	7	49	370	2025-08-19 04:47:53.047269
5283	1	49	370	2025-08-21 07:56:45.113462
5284	3	49	370	2025-08-20 03:18:23.107323
5285	6	73	979	2025-02-03 23:56:29.871744
5286	4	73	979	2025-01-28 12:51:17.378682
5287	2	73	979	2025-01-29 03:42:08.164952
5288	7	73	979	2025-01-29 09:54:22.447945
5289	1	73	979	2025-01-23 06:32:02.794671
5290	3	73	979	2025-01-30 08:52:58.328364
5291	6	73	979	2025-02-03 02:22:52.761891
5292	4	73	979	2025-01-28 02:58:30.308895
5293	2	73	979	2025-01-30 18:11:14.259267
5294	7	73	979	2025-01-28 03:06:49.627555
5295	1	73	979	2025-01-23 17:40:25.774406
5296	3	73	979	2025-02-02 06:57:26.222027
5297	6	81	593	2025-09-24 07:40:37.769346
5298	4	81	593	2025-09-26 03:11:38.06948
5299	2	81	593	2025-09-29 12:27:16.821778
5300	7	81	593	2025-09-21 07:22:04.306634
5301	1	81	593	2025-09-27 00:41:14.163162
5302	3	81	593	2025-09-27 21:13:16.92395
5309	6	120	522	2025-02-04 20:19:00.853562
5310	4	120	522	2025-02-03 13:07:55.833741
5311	2	120	522	2025-02-03 23:05:51.438084
5312	7	120	522	2025-02-07 19:40:01.108799
5313	1	120	522	2025-02-07 21:21:00.245689
5314	3	120	522	2025-01-31 16:52:35.464169
5315	6	151	153	2025-02-20 08:10:52.958191
5316	4	151	153	2025-02-17 23:59:17.579491
5317	2	151	153	2025-02-19 03:08:02.053113
5318	7	151	153	2025-02-10 23:20:40.951426
5319	1	151	153	2025-02-12 17:01:28.901415
5320	3	151	153	2025-02-15 14:16:41.555626
5321	6	13	206	2025-03-21 13:32:44.255613
5322	4	13	206	2025-03-23 15:32:20.517699
5323	2	13	206	2025-03-25 19:43:15.695395
5324	7	13	206	2025-03-25 18:33:36.213594
5325	1	13	206	2025-03-21 18:46:26.839054
5326	3	13	206	2025-03-24 00:02:35.958413
5333	6	180	991	2025-08-02 20:12:08.430962
5334	4	180	991	2025-08-02 15:35:47.803508
5335	2	180	991	2025-08-04 07:44:16.391699
5336	7	180	991	2025-08-03 07:44:47.752132
5337	1	180	991	2025-07-31 21:10:51.228615
5338	3	180	991	2025-08-04 05:20:50.264654
5399	6	78	267	2025-04-30 01:22:11.762322
5400	4	78	267	2025-05-01 19:55:21.762799
5401	2	78	267	2025-04-29 12:18:48.556509
5402	7	78	267	2025-04-28 20:58:38.297274
5403	1	78	267	2025-04-28 20:23:26.075457
5404	3	78	267	2025-05-04 16:24:34.42007
5453	6	260	469	2026-05-12 13:37:31.670711
5454	4	260	469	2026-05-11 10:19:13.899218
5455	2	260	469	2026-05-16 11:55:24.523333
5456	7	260	469	2026-05-13 03:19:06.836038
5457	1	260	469	2026-05-17 14:31:01.528354
5458	3	260	469	2026-05-16 13:08:22.229846
5471	6	303	948	2025-09-24 00:31:15.217357
5472	4	303	948	2025-09-24 03:05:51.755656
5473	2	303	948	2025-09-22 15:52:51.739187
5474	7	303	948	2025-09-24 07:25:52.063367
5475	1	303	948	2025-09-22 12:45:08.87832
5476	3	303	948	2025-09-23 01:25:56.061393
5477	6	303	948	2025-09-23 15:19:53.811112
5478	4	303	948	2025-09-22 08:44:46.702183
5479	2	303	948	2025-09-23 04:27:36.551556
5480	7	303	948	2025-09-23 17:32:47.806211
5481	1	303	948	2025-09-23 16:25:36.213366
5482	3	303	948	2025-09-23 16:09:18.983727
\.


--
-- TOC entry 5351 (class 0 OID 31123)
-- Dependencies: 231
-- Data for Name: descuento; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.descuento (id_descuento, porcentaje_descuento, cant_dia_hospedado) FROM stdin;
1	5.00	3
2	10.00	5
3	15.00	7
4	20.00	10
5	2.50	2
6	8.00	4
7	12.50	6
8	18.00	8
9	25.00	14
10	30.00	30
\.


--
-- TOC entry 5353 (class 0 OID 31131)
-- Dependencies: 233
-- Data for Name: detalle_factura; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.detalle_factura (id_detalle_factura, id_factura, id_servicio, id_habitacion, id_descuento, id_aumento_costo, concepto, precio_unitario, cantidad, subtotal, monto_descuento, monto_aumento, precio_total) FROM stdin;
1	1	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	1	116.86	0.00	0.00	116.86
2	2	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
3	3	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
4	4	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
5	5	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
6	6	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
7	7	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	13	1519.18	0.00	0.00	1519.18
8	8	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
9	9	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	2	233.72	0.00	0.00	233.72
10	10	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	10	1168.60	0.00	0.00	1168.60
11	11	\N	282	\N	\N	Estad├¡a de habitaci├│n	748.15	10	7481.50	0.00	0.00	7481.50
12	12	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
13	13	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
14	14	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	2	233.72	0.00	0.00	233.72
15	15	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
16	16	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	1	116.86	0.00	0.00	116.86
17	17	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	9	1051.74	0.00	0.00	1051.74
18	18	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	13	1519.18	0.00	0.00	1519.18
19	19	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
20	20	\N	151	\N	\N	Estad├¡a de habitaci├│n	110.54	14	1547.56	0.00	0.00	1547.56
21	21	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
22	22	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
23	23	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	14	1636.04	0.00	0.00	1636.04
24	24	\N	13	\N	\N	Estad├¡a de habitaci├│n	646.25	5	3231.25	0.00	0.00	3231.25
25	25	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
26	26	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
27	27	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	6	701.16	0.00	0.00	701.16
28	28	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
29	29	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
30	30	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	14	1636.04	0.00	0.00	1636.04
31	31	\N	78	\N	\N	Estad├¡a de habitaci├│n	176.29	10	1762.90	0.00	0.00	1762.90
32	32	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
33	33	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
34	34	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
35	35	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
36	36	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	14	1636.04	0.00	0.00	1636.04
37	37	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
38	38	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
39	39	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
40	40	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
41	41	\N	49	\N	\N	Estad├¡a de habitaci├│n	451.40	12	5416.80	0.00	0.00	5416.80
42	42	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	13	1519.18	0.00	0.00	1519.18
43	43	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	13	1519.18	0.00	0.00	1519.18
44	44	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	9	1051.74	0.00	0.00	1051.74
45	45	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	9	1051.74	0.00	0.00	1051.74
46	46	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
47	47	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
48	48	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
49	49	\N	17	\N	\N	Estad├¡a de habitaci├│n	439.08	2	878.16	0.00	0.00	878.16
50	50	\N	260	\N	\N	Estad├¡a de habitaci├│n	431.26	9	3881.34	0.00	0.00	3881.34
51	51	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	5	584.30	0.00	0.00	584.30
52	52	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
53	53	\N	120	\N	\N	Estad├¡a de habitaci├│n	155.80	10	1558.00	0.00	0.00	1558.00
54	54	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
55	55	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	10	1168.60	0.00	0.00	1168.60
56	56	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
57	57	\N	81	\N	\N	Estad├¡a de habitaci├│n	439.03	11	4829.33	0.00	0.00	4829.33
58	58	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	1	116.86	0.00	0.00	116.86
59	59	\N	57	\N	\N	Estad├¡a de habitaci├│n	683.50	5	3417.50	0.00	0.00	3417.50
60	59	\N	57	\N	\N	Estad├¡a de habitaci├│n	683.50	5	3417.50	0.00	0.00	3417.50
61	60	\N	112	\N	\N	Estad├¡a de habitaci├│n	210.33	13	2734.29	0.00	0.00	2734.29
62	61	\N	896	\N	\N	Estad├¡a de habitaci├│n	699.26	8	5594.08	0.00	0.00	5594.08
63	62	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	5	584.30	0.00	0.00	584.30
64	63	\N	853	\N	\N	Estad├¡a de habitaci├│n	261.76	9	2355.84	0.00	0.00	2355.84
65	64	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
66	65	\N	85	\N	\N	Estad├¡a de habitaci├│n	204.31	8	1634.48	0.00	0.00	1634.48
67	66	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	12	1402.32	0.00	0.00	1402.32
68	67	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	13	1519.18	0.00	0.00	1519.18
69	68	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	7	818.02	0.00	0.00	818.02
70	69	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
71	70	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	9	1051.74	0.00	0.00	1051.74
72	71	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	3	350.58	0.00	0.00	350.58
73	72	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
74	73	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	10	1168.60	0.00	0.00	1168.60
75	74	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
76	75	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	6	701.16	0.00	0.00	701.16
77	76	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
78	77	\N	38	\N	\N	Estad├¡a de habitaci├│n	229.98	15	3449.70	0.00	0.00	3449.70
79	78	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
80	79	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
81	80	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	4	467.44	0.00	0.00	467.44
82	81	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	8	934.88	0.00	0.00	934.88
83	82	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	5	584.30	0.00	0.00	584.30
84	83	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	7	818.02	0.00	0.00	818.02
85	84	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	5	584.30	0.00	0.00	584.30
86	85	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
87	86	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	5	584.30	0.00	0.00	584.30
88	87	\N	303	\N	\N	Estad├¡a de habitaci├│n	707.69	3	2123.07	0.00	0.00	2123.07
89	87	\N	303	\N	\N	Estad├¡a de habitaci├│n	707.69	3	2123.07	0.00	0.00	2123.07
90	88	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	10	1168.60	0.00	0.00	1168.60
91	89	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
92	90	\N	73	\N	\N	Estad├¡a de habitaci├│n	532.31	13	6920.03	0.00	0.00	6920.03
93	90	\N	73	\N	\N	Estad├¡a de habitaci├│n	532.31	13	6920.03	0.00	0.00	6920.03
94	91	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	7	818.02	0.00	0.00	818.02
95	92	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	14	1636.04	0.00	0.00	1636.04
96	93	\N	180	\N	\N	Estad├¡a de habitaci├│n	580.66	4	2322.64	0.00	0.00	2322.64
97	94	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	7	818.02	0.00	0.00	818.02
98	95	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	11	1285.46	0.00	0.00	1285.46
99	96	\N	333	\N	\N	Estad├¡a de habitaci├│n	589.81	8	4718.48	0.00	0.00	4718.48
100	96	\N	699	\N	\N	Estad├¡a de habitaci├│n	351.55	8	2812.40	0.00	0.00	2812.40
101	97	\N	181	\N	\N	Estad├¡a de habitaci├│n	655.55	1	655.55	0.00	0.00	655.55
102	97	\N	342	\N	\N	Estad├¡a de habitaci├│n	740.68	1	740.68	0.00	0.00	740.68
103	98	\N	419	\N	\N	Estad├¡a de habitaci├│n	366.54	11	4031.94	0.00	0.00	4031.94
104	98	\N	490	\N	\N	Estad├¡a de habitaci├│n	246.47	11	2711.17	0.00	0.00	2711.17
105	98	\N	688	\N	\N	Estad├¡a de habitaci├│n	520.26	11	5722.86	0.00	0.00	5722.86
106	99	\N	727	\N	\N	Estad├¡a de habitaci├│n	198.62	5	993.10	0.00	0.00	993.10
107	100	\N	93	\N	\N	Estad├¡a de habitaci├│n	717.83	15	10767.45	0.00	0.00	10767.45
108	100	\N	435	\N	\N	Estad├¡a de habitaci├│n	120.67	15	1810.05	0.00	0.00	1810.05
109	100	\N	379	\N	\N	Estad├¡a de habitaci├│n	566.82	15	8502.30	0.00	0.00	8502.30
110	101	\N	595	\N	\N	Estad├¡a de habitaci├│n	609.16	13	7919.08	0.00	0.00	7919.08
111	102	\N	494	\N	\N	Estad├¡a de habitaci├│n	739.72	2	1479.44	0.00	0.00	1479.44
112	102	\N	303	\N	\N	Estad├¡a de habitaci├│n	707.69	2	1415.38	0.00	0.00	1415.38
113	103	\N	783	\N	\N	Estad├¡a de habitaci├│n	707.31	14	9902.34	0.00	0.00	9902.34
114	103	\N	390	\N	\N	Estad├¡a de habitaci├│n	398.74	14	5582.36	0.00	0.00	5582.36
115	103	\N	45	\N	\N	Estad├¡a de habitaci├│n	732.84	14	10259.76	0.00	0.00	10259.76
116	103	\N	244	\N	\N	Estad├¡a de habitaci├│n	563.19	14	7884.66	0.00	0.00	7884.66
117	104	\N	613	\N	\N	Estad├¡a de habitaci├│n	554.50	11	6099.50	0.00	0.00	6099.50
118	104	\N	1	\N	\N	Estad├¡a de habitaci├│n	79.74	11	877.14	0.00	0.00	877.14
119	104	\N	814	\N	\N	Estad├¡a de habitaci├│n	583.10	11	6414.10	0.00	0.00	6414.10
120	105	\N	903	\N	\N	Estad├¡a de habitaci├│n	588.47	6	3530.82	0.00	0.00	3530.82
121	106	\N	699	\N	\N	Estad├¡a de habitaci├│n	351.55	10	3515.50	0.00	0.00	3515.50
122	107	\N	954	\N	\N	Estad├¡a de habitaci├│n	616.98	11	6786.78	0.00	0.00	6786.78
123	107	\N	70	\N	\N	Estad├¡a de habitaci├│n	170.26	11	1872.86	0.00	0.00	1872.86
124	107	\N	463	\N	\N	Estad├¡a de habitaci├│n	665.51	11	7320.61	0.00	0.00	7320.61
125	108	\N	595	\N	\N	Estad├¡a de habitaci├│n	609.16	5	3045.80	0.00	0.00	3045.80
126	109	\N	131	\N	\N	Estad├¡a de habitaci├│n	529.45	3	1588.35	0.00	0.00	1588.35
127	109	\N	877	\N	\N	Estad├¡a de habitaci├│n	250.72	3	752.16	0.00	0.00	752.16
128	110	\N	645	\N	\N	Estad├¡a de habitaci├│n	705.98	1	705.98	0.00	0.00	705.98
129	111	\N	784	\N	\N	Estad├¡a de habitaci├│n	472.57	13	6143.41	0.00	0.00	6143.41
130	112	\N	162	\N	\N	Estad├¡a de habitaci├│n	668.63	13	8692.19	0.00	0.00	8692.19
131	112	\N	401	\N	\N	Estad├¡a de habitaci├│n	448.34	13	5828.42	0.00	0.00	5828.42
132	113	\N	916	\N	\N	Estad├¡a de habitaci├│n	145.35	2	290.70	0.00	0.00	290.70
133	114	\N	490	\N	\N	Estad├¡a de habitaci├│n	246.47	8	1971.76	0.00	0.00	1971.76
134	114	\N	242	\N	\N	Estad├¡a de habitaci├│n	401.76	8	3214.08	0.00	0.00	3214.08
135	115	\N	652	\N	\N	Estad├¡a de habitaci├│n	138.34	14	1936.76	0.00	0.00	1936.76
136	115	\N	583	\N	\N	Estad├¡a de habitaci├│n	636.49	14	8910.86	0.00	0.00	8910.86
137	116	\N	864	\N	\N	Estad├¡a de habitaci├│n	583.95	4	2335.80	0.00	0.00	2335.80
138	117	\N	366	\N	\N	Estad├¡a de habitaci├│n	692.51	7	4847.57	0.00	0.00	4847.57
139	118	\N	203	\N	\N	Estad├¡a de habitaci├│n	232.34	1	232.34	0.00	0.00	232.34
140	118	\N	681	\N	\N	Estad├¡a de habitaci├│n	145.90	1	145.90	0.00	0.00	145.90
141	119	\N	178	\N	\N	Estad├¡a de habitaci├│n	353.55	14	4949.70	0.00	0.00	4949.70
142	119	\N	110	\N	\N	Estad├¡a de habitaci├│n	288.54	14	4039.56	0.00	0.00	4039.56
143	119	\N	773	\N	\N	Estad├¡a de habitaci├│n	397.23	14	5561.22	0.00	0.00	5561.22
144	120	\N	753	\N	\N	Estad├¡a de habitaci├│n	215.89	10	2158.90	0.00	0.00	2158.90
145	120	\N	340	\N	\N	Estad├¡a de habitaci├│n	257.22	10	2572.20	0.00	0.00	2572.20
146	121	\N	741	\N	\N	Estad├¡a de habitaci├│n	529.31	15	7939.65	0.00	0.00	7939.65
147	121	\N	799	\N	\N	Estad├¡a de habitaci├│n	536.00	15	8040.00	0.00	0.00	8040.00
148	121	\N	446	\N	\N	Estad├¡a de habitaci├│n	644.51	15	9667.65	0.00	0.00	9667.65
149	122	\N	536	\N	\N	Estad├¡a de habitaci├│n	676.69	14	9473.66	0.00	0.00	9473.66
150	122	\N	307	\N	\N	Estad├¡a de habitaci├│n	386.39	14	5409.46	0.00	0.00	5409.46
151	123	\N	437	\N	\N	Estad├¡a de habitaci├│n	147.59	4	590.36	0.00	0.00	590.36
152	124	\N	233	\N	\N	Estad├¡a de habitaci├│n	686.64	13	8926.32	0.00	0.00	8926.32
153	124	\N	813	\N	\N	Estad├¡a de habitaci├│n	650.21	13	8452.73	0.00	0.00	8452.73
154	125	\N	78	\N	\N	Estad├¡a de habitaci├│n	176.29	8	1410.32	0.00	0.00	1410.32
155	125	\N	428	\N	\N	Estad├¡a de habitaci├│n	530.51	8	4244.08	0.00	0.00	4244.08
156	126	\N	211	\N	\N	Estad├¡a de habitaci├│n	98.00	11	1078.00	0.00	0.00	1078.00
157	127	\N	553	\N	\N	Estad├¡a de habitaci├│n	538.07	9	4842.63	0.00	0.00	4842.63
158	127	\N	296	\N	\N	Estad├¡a de habitaci├│n	209.02	9	1881.18	0.00	0.00	1881.18
159	127	\N	222	\N	\N	Estad├¡a de habitaci├│n	365.52	9	3289.68	0.00	0.00	3289.68
160	127	\N	576	\N	\N	Estad├¡a de habitaci├│n	723.00	9	6507.00	0.00	0.00	6507.00
161	128	\N	896	\N	\N	Estad├¡a de habitaci├│n	699.26	13	9090.38	0.00	0.00	9090.38
162	129	\N	639	\N	\N	Estad├¡a de habitaci├│n	327.57	3	982.71	0.00	0.00	982.71
163	129	\N	426	\N	\N	Estad├¡a de habitaci├│n	271.44	3	814.32	0.00	0.00	814.32
164	130	\N	111	\N	\N	Estad├¡a de habitaci├│n	234.07	12	2808.84	0.00	0.00	2808.84
165	131	\N	670	\N	\N	Estad├¡a de habitaci├│n	143.71	3	431.13	0.00	0.00	431.13
166	131	\N	647	\N	\N	Estad├¡a de habitaci├│n	403.25	3	1209.75	0.00	0.00	1209.75
167	132	\N	559	\N	\N	Estad├¡a de habitaci├│n	252.82	4	1011.28	0.00	0.00	1011.28
168	132	\N	673	\N	\N	Estad├¡a de habitaci├│n	254.28	4	1017.12	0.00	0.00	1017.12
169	133	\N	480	\N	\N	Estad├¡a de habitaci├│n	514.60	8	4116.80	0.00	0.00	4116.80
170	134	\N	147	\N	\N	Estad├¡a de habitaci├│n	281.19	13	3655.47	0.00	0.00	3655.47
171	135	\N	836	\N	\N	Estad├¡a de habitaci├│n	529.56	1	529.56	0.00	0.00	529.56
172	135	\N	154	\N	\N	Estad├¡a de habitaci├│n	178.37	1	178.37	0.00	0.00	178.37
173	135	\N	752	\N	\N	Estad├¡a de habitaci├│n	201.36	1	201.36	0.00	0.00	201.36
174	136	\N	673	\N	\N	Estad├¡a de habitaci├│n	254.28	7	1779.96	0.00	0.00	1779.96
175	137	\N	933	\N	\N	Estad├¡a de habitaci├│n	485.18	3	1455.54	0.00	0.00	1455.54
176	137	\N	831	\N	\N	Estad├¡a de habitaci├│n	749.82	3	2249.46	0.00	0.00	2249.46
177	138	\N	817	\N	\N	Estad├¡a de habitaci├│n	91.00	15	1365.00	0.00	0.00	1365.00
178	138	\N	165	\N	\N	Estad├¡a de habitaci├│n	144.18	15	2162.70	0.00	0.00	2162.70
179	139	\N	380	\N	\N	Estad├¡a de habitaci├│n	190.39	13	2475.07	0.00	0.00	2475.07
180	139	\N	435	\N	\N	Estad├¡a de habitaci├│n	120.67	13	1568.71	0.00	0.00	1568.71
181	139	\N	836	\N	\N	Estad├¡a de habitaci├│n	529.56	13	6884.28	0.00	0.00	6884.28
182	140	\N	456	\N	\N	Estad├¡a de habitaci├│n	744.84	9	6703.56	0.00	0.00	6703.56
183	140	\N	23	\N	\N	Estad├¡a de habitaci├│n	394.30	9	3548.70	0.00	0.00	3548.70
184	140	\N	246	\N	\N	Estad├¡a de habitaci├│n	351.19	9	3160.71	0.00	0.00	3160.71
185	141	\N	935	\N	\N	Estad├¡a de habitaci├│n	740.62	12	8887.44	0.00	0.00	8887.44
186	141	\N	33	\N	\N	Estad├¡a de habitaci├│n	273.74	12	3284.88	0.00	0.00	3284.88
187	142	\N	429	\N	\N	Estad├¡a de habitaci├│n	575.66	8	4605.28	0.00	0.00	4605.28
188	143	\N	11	\N	\N	Estad├¡a de habitaci├│n	658.48	10	6584.80	0.00	0.00	6584.80
189	144	\N	628	\N	\N	Estad├¡a de habitaci├│n	75.26	6	451.56	0.00	0.00	451.56
190	144	\N	256	\N	\N	Estad├¡a de habitaci├│n	536.08	6	3216.48	0.00	0.00	3216.48
191	145	\N	299	\N	\N	Estad├¡a de habitaci├│n	723.50	7	5064.50	0.00	0.00	5064.50
192	145	\N	626	\N	\N	Estad├¡a de habitaci├│n	746.09	7	5222.63	0.00	0.00	5222.63
193	146	\N	906	\N	\N	Estad├¡a de habitaci├│n	88.00	3	264.00	0.00	0.00	264.00
194	146	\N	397	\N	\N	Estad├¡a de habitaci├│n	116.01	3	348.03	0.00	0.00	348.03
195	146	\N	947	\N	\N	Estad├¡a de habitaci├│n	92.74	3	278.22	0.00	0.00	278.22
196	146	\N	229	\N	\N	Estad├¡a de habitaci├│n	118.17	3	354.51	0.00	0.00	354.51
197	147	\N	485	\N	\N	Estad├¡a de habitaci├│n	88.73	3	266.19	0.00	0.00	266.19
198	148	\N	724	\N	\N	Estad├¡a de habitaci├│n	552.42	15	8286.30	0.00	0.00	8286.30
199	148	\N	361	\N	\N	Estad├¡a de habitaci├│n	487.63	15	7314.45	0.00	0.00	7314.45
200	149	\N	419	\N	\N	Estad├¡a de habitaci├│n	366.54	15	5498.10	0.00	0.00	5498.10
201	149	\N	396	\N	\N	Estad├¡a de habitaci├│n	560.39	15	8405.85	0.00	0.00	8405.85
202	149	\N	331	\N	\N	Estad├¡a de habitaci├│n	116.86	15	1752.90	0.00	0.00	1752.90
203	150	\N	898	\N	\N	Estad├¡a de habitaci├│n	314.31	15	4714.65	0.00	0.00	4714.65
204	151	\N	773	\N	\N	Estad├¡a de habitaci├│n	397.23	10	3972.30	0.00	0.00	3972.30
205	152	\N	368	\N	\N	Estad├¡a de habitaci├│n	682.15	5	3410.75	0.00	0.00	3410.75
206	153	\N	452	\N	\N	Estad├¡a de habitaci├│n	447.73	15	6715.95	0.00	0.00	6715.95
207	154	\N	640	\N	\N	Estad├¡a de habitaci├│n	714.98	15	10724.70	0.00	0.00	10724.70
208	155	\N	646	\N	\N	Estad├¡a de habitaci├│n	441.45	3	1324.35	0.00	0.00	1324.35
209	156	\N	521	\N	\N	Estad├¡a de habitaci├│n	489.48	7	3426.36	0.00	0.00	3426.36
210	156	\N	439	\N	\N	Estad├¡a de habitaci├│n	489.17	7	3424.19	0.00	0.00	3424.19
211	157	\N	535	\N	\N	Estad├¡a de habitaci├│n	734.51	11	8079.61	0.00	0.00	8079.61
212	158	\N	64	\N	\N	Estad├¡a de habitaci├│n	384.40	10	3844.00	0.00	0.00	3844.00
213	159	\N	655	\N	\N	Estad├¡a de habitaci├│n	566.78	2	1133.56	0.00	0.00	1133.56
214	160	\N	314	\N	\N	Estad├¡a de habitaci├│n	82.38	7	576.66	0.00	0.00	576.66
215	161	\N	960	\N	\N	Estad├¡a de habitaci├│n	616.71	11	6783.81	0.00	0.00	6783.81
216	162	\N	409	\N	\N	Estad├¡a de habitaci├│n	655.47	15	9832.05	0.00	0.00	9832.05
217	163	\N	728	\N	\N	Estad├¡a de habitaci├│n	518.03	9	4662.27	0.00	0.00	4662.27
218	164	\N	973	\N	\N	Estad├¡a de habitaci├│n	111.26	4	445.04	0.00	0.00	445.04
219	165	\N	488	\N	\N	Estad├¡a de habitaci├│n	532.94	14	7461.16	0.00	0.00	7461.16
220	165	\N	229	\N	\N	Estad├¡a de habitaci├│n	118.17	14	1654.38	0.00	0.00	1654.38
221	166	\N	852	\N	\N	Estad├¡a de habitaci├│n	408.84	3	1226.52	0.00	0.00	1226.52
222	166	\N	520	\N	\N	Estad├¡a de habitaci├│n	169.63	3	508.89	0.00	0.00	508.89
223	167	\N	694	\N	\N	Estad├¡a de habitaci├│n	172.26	12	2067.12	0.00	0.00	2067.12
224	168	\N	915	\N	\N	Estad├¡a de habitaci├│n	628.76	1	628.76	0.00	0.00	628.76
225	169	\N	248	\N	\N	Estad├¡a de habitaci├│n	137.99	5	689.95	0.00	0.00	689.95
226	170	\N	536	\N	\N	Estad├¡a de habitaci├│n	676.69	12	8120.28	0.00	0.00	8120.28
227	171	\N	202	\N	\N	Estad├¡a de habitaci├│n	548.44	4	2193.76	0.00	0.00	2193.76
228	171	\N	518	\N	\N	Estad├¡a de habitaci├│n	400.95	4	1603.80	0.00	0.00	1603.80
229	172	\N	532	\N	\N	Estad├¡a de habitaci├│n	67.00	11	737.00	0.00	0.00	737.00
230	173	\N	806	\N	\N	Estad├¡a de habitaci├│n	117.18	4	468.72	0.00	0.00	468.72
231	174	\N	816	\N	\N	Estad├¡a de habitaci├│n	237.26	6	1423.56	0.00	0.00	1423.56
232	174	\N	367	\N	\N	Estad├¡a de habitaci├│n	476.20	6	2857.20	0.00	0.00	2857.20
233	175	\N	561	\N	\N	Estad├¡a de habitaci├│n	473.37	3	1420.11	0.00	0.00	1420.11
234	176	\N	464	\N	\N	Estad├¡a de habitaci├│n	600.28	1	600.28	0.00	0.00	600.28
235	177	\N	288	\N	\N	Estad├¡a de habitaci├│n	86.00	10	860.00	0.00	0.00	860.00
236	178	\N	332	\N	\N	Estad├¡a de habitaci├│n	470.38	13	6114.94	0.00	0.00	6114.94
237	178	\N	820	\N	\N	Estad├¡a de habitaci├│n	148.49	13	1930.37	0.00	0.00	1930.37
238	179	\N	418	\N	\N	Estad├¡a de habitaci├│n	700.87	3	2102.61	0.00	0.00	2102.61
239	180	\N	301	\N	\N	Estad├¡a de habitaci├│n	508.72	5	2543.60	0.00	0.00	2543.60
240	155	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
241	101	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
242	143	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
243	139	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
244	142	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
245	32	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
246	146	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
247	52	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
248	97	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
249	9	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
250	144	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
251	124	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
252	169	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
253	92	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
254	98	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
255	169	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
256	142	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
257	21	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
258	67	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
259	35	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
260	162	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
261	146	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
262	95	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
263	157	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
264	22	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
265	25	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
266	60	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
267	60	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
268	18	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
269	160	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
270	66	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
271	18	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
272	74	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
273	50	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
274	66	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
275	56	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
276	18	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
277	47	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
278	103	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
279	12	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
280	153	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
281	164	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
282	51	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
283	178	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
284	98	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
285	129	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
286	18	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
287	25	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
288	96	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
289	154	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
290	158	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
291	11	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
292	87	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
293	163	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
294	20	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
295	126	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
296	149	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
297	175	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
298	173	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
299	177	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
300	44	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
301	85	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
302	116	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
303	55	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
304	5	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
305	178	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
306	118	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
307	147	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
308	25	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
309	25	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
310	179	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
311	83	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
312	28	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
313	99	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
314	31	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
315	131	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
316	14	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
317	127	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
318	144	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
319	165	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
320	95	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
321	8	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
322	39	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
323	28	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
324	117	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
325	55	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
326	102	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
327	1	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
328	1	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
329	68	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
330	162	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
331	52	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
332	105	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
333	97	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
334	112	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
335	13	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
336	164	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
337	87	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
338	166	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
339	100	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
340	161	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
341	76	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
342	101	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
343	144	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
344	175	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
345	121	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
346	170	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
347	114	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
348	130	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
349	151	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
350	38	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
351	160	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
352	103	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
353	132	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
354	87	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
355	53	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
356	153	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
357	142	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
358	67	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
359	135	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
360	101	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
361	41	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
362	57	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
363	74	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
364	59	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
365	8	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
366	2	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
367	146	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
368	46	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
369	132	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
370	63	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
371	47	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
372	53	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
373	40	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
374	24	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
375	164	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
376	10	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
377	5	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
378	29	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
379	158	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
380	68	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
381	136	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
382	134	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
383	102	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
384	127	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
385	165	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
386	30	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
387	67	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
388	124	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
389	10	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
390	99	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
391	108	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
392	2	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
393	33	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
394	1	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
395	37	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
396	36	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
397	142	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
398	21	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
399	20	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
400	40	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
401	43	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
402	59	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
403	129	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
404	13	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
405	112	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
406	96	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
407	96	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
408	96	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
409	96	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
410	96	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
411	96	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
412	97	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
413	97	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
414	97	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
415	97	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
416	97	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
417	97	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
418	98	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
419	98	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
420	98	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
421	98	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
422	98	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
423	98	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
424	99	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
425	99	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
426	99	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
427	99	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
428	99	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
429	99	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
430	100	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
431	100	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
432	100	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
433	100	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
434	100	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
435	100	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
436	101	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
437	101	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
438	101	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
439	101	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
440	101	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
441	101	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
442	102	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
443	102	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
444	102	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
445	102	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
446	102	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
447	102	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
448	103	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
449	103	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
450	103	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
451	103	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
452	103	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
453	103	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
454	104	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
455	104	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
456	104	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
457	104	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
458	104	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
459	104	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
460	105	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
461	105	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
462	105	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
463	105	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
464	105	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
465	105	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
466	106	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
467	106	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
468	106	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
469	106	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
470	106	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
471	106	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
472	127	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
473	127	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
474	127	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
475	127	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
476	127	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
477	127	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
478	127	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
479	127	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
480	127	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
481	127	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
482	127	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
483	127	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
484	107	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
485	107	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
486	107	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
487	107	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
488	107	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
489	107	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
490	108	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
491	108	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
492	108	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
493	108	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
494	108	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
495	108	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
496	109	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
497	109	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
498	109	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
499	109	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
500	109	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
501	109	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
502	115	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
503	115	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
504	115	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
505	115	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
506	115	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
507	115	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
508	102	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
509	102	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
510	102	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
511	102	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
512	102	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
513	102	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
514	110	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
515	110	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
516	110	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
517	110	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
518	110	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
519	110	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
520	111	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
521	111	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
522	111	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
523	111	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
524	111	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
525	111	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
526	112	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
527	112	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
528	112	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
529	112	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
530	112	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
531	112	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
532	113	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
533	113	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
534	113	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
535	113	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
536	113	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
537	113	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
538	114	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
539	114	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
540	114	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
541	114	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
542	114	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
543	114	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
544	115	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
545	115	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
546	115	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
547	115	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
548	115	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
549	115	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
550	96	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
551	96	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
552	96	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
553	96	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
554	96	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
555	96	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
556	121	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
557	121	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
558	121	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
559	121	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
560	121	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
561	121	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
562	116	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
563	116	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
564	116	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
565	116	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
566	116	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
567	116	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
568	117	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
569	117	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
570	117	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
571	117	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
572	117	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
573	117	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
574	118	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
575	118	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
576	118	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
577	118	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
578	118	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
579	118	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
580	60	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
581	60	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
582	60	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
583	60	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
584	60	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
585	60	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
586	119	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
587	119	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
588	119	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
589	119	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
590	119	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
591	119	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
592	120	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
593	120	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
594	120	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
595	120	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
596	120	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
597	120	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
598	121	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
599	121	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
600	121	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
601	121	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
602	121	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
603	121	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
604	122	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
605	122	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
606	122	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
607	122	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
608	122	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
609	122	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
610	123	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
611	123	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
612	123	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
613	123	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
614	123	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
615	123	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
616	124	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
617	124	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
618	124	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
619	124	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
620	124	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
621	124	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
622	124	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
623	124	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
624	124	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
625	124	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
626	124	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
627	124	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
628	103	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
629	103	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
630	103	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
631	103	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
632	103	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
633	103	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
634	125	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
635	125	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
636	125	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
637	125	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
638	125	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
639	125	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
640	61	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
641	61	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
642	61	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
643	61	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
644	61	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
645	61	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
646	107	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
647	107	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
648	107	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
649	107	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
650	107	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
651	107	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
652	109	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
653	109	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
654	109	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
655	109	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
656	109	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
657	109	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
658	137	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
659	137	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
660	137	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
661	137	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
662	137	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
663	137	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
664	126	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
665	126	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
666	126	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
667	126	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
668	126	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
669	126	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
670	127	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
671	127	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
672	127	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
673	127	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
674	127	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
675	127	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
676	128	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
677	128	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
678	128	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
679	128	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
680	128	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
681	128	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
682	129	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
683	129	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
684	129	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
685	129	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
686	129	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
687	129	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
688	130	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
689	130	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
690	130	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
691	130	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
692	130	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
693	130	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
694	131	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
695	131	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
696	131	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
697	131	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
698	131	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
699	131	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
700	132	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
701	132	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
702	132	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
703	132	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
704	132	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
705	132	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
706	133	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
707	133	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
708	133	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
709	133	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
710	133	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
711	133	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
712	134	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
713	134	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
714	134	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
715	134	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
716	134	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
717	134	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
718	135	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
719	135	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
720	135	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
721	135	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
722	135	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
723	135	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
724	136	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
725	136	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
726	136	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
727	136	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
728	136	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
729	136	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
730	139	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
731	139	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
732	139	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
733	139	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
734	139	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
735	139	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
736	137	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
737	137	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
738	137	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
739	137	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
740	137	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
741	137	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
742	138	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
743	138	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
744	138	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
745	138	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
746	138	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
747	138	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
748	139	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
749	139	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
750	139	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
751	139	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
752	139	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
753	139	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
754	140	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
755	140	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
756	140	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
757	140	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
758	140	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
759	140	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
760	148	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
761	148	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
762	148	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
763	148	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
764	148	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
765	148	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
766	141	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
767	141	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
768	141	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
769	141	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
770	141	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
771	141	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
772	131	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
773	131	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
774	131	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
775	131	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
776	131	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
777	131	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
778	119	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
779	119	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
780	119	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
781	119	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
782	119	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
783	119	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
784	118	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
785	118	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
786	118	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
787	118	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
788	118	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
789	118	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
790	142	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
791	142	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
792	142	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
793	142	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
794	142	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
795	142	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
796	143	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
797	143	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
798	143	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
799	143	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
800	143	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
801	143	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
802	65	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
803	65	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
804	65	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
805	65	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
806	65	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
807	65	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
808	146	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
809	146	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
810	146	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
811	146	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
812	146	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
813	146	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
814	103	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
815	103	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
816	103	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
817	103	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
818	103	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
819	103	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
820	144	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
821	144	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
822	144	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
823	144	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
824	144	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
825	144	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
826	107	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
827	107	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
828	107	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
829	107	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
830	107	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
831	107	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
832	145	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
833	145	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
834	145	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
835	145	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
836	145	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
837	145	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
838	146	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
839	146	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
840	146	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
841	146	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
842	146	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
843	146	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
844	139	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
845	139	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
846	139	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
847	139	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
848	139	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
849	139	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
850	132	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
851	132	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
852	132	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
853	132	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
854	132	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
855	132	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
856	147	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
857	147	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
858	147	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
859	147	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
860	147	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
861	147	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
862	127	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
863	127	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
864	127	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
865	127	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
866	127	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
867	127	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
868	148	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
869	148	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
870	148	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
871	148	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
872	148	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
873	148	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
874	149	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
875	149	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
876	149	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
877	149	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
878	149	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
879	149	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
880	150	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
881	150	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
882	150	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
883	150	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
884	150	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
885	150	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
886	151	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
887	151	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
888	151	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
889	151	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
890	151	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
891	151	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
892	152	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
893	152	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
894	152	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
895	152	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
896	152	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
897	152	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
898	144	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
899	144	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
900	144	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
901	144	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
902	144	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
903	144	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
904	153	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
905	153	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
906	153	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
907	153	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
908	153	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
909	153	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
910	146	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
911	146	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
912	146	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
913	146	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
914	146	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
915	146	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
916	119	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
917	119	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
918	119	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
919	119	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
920	119	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
921	119	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
922	140	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
923	140	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
924	140	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
925	140	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
926	140	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
927	140	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
928	154	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
929	154	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
930	154	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
931	154	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
932	154	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
933	154	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
934	155	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
935	155	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
936	155	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
937	155	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
938	155	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
939	155	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
940	156	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
941	156	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
942	156	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
943	156	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
944	156	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
945	156	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
946	157	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
947	157	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
948	157	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
949	157	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
950	157	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
951	157	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
952	100	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
953	100	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
954	100	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
955	100	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
956	100	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
957	100	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
958	135	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
959	135	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
960	135	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
961	135	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
962	135	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
963	135	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
964	158	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
965	158	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
966	158	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
967	158	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
968	158	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
969	158	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
970	156	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
971	156	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
972	156	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
973	156	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
974	156	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
975	156	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
976	63	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
977	63	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
978	63	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
979	63	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
980	63	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
981	63	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
982	135	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
983	135	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
984	135	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
985	135	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
986	135	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
987	135	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
988	129	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
989	129	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
990	129	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
991	129	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
992	129	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
993	129	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
994	120	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
995	120	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
996	120	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
997	120	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
998	120	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
999	120	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1000	114	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1001	114	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1002	114	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1003	114	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1004	114	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1005	114	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1006	159	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1007	159	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1008	159	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1009	159	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1010	159	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1011	159	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1012	140	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1013	140	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1014	140	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1015	140	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1016	140	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1017	140	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1018	160	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1019	160	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1020	160	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1021	160	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1022	160	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1023	160	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1024	161	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1025	161	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1026	161	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1027	161	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1028	161	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1029	161	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1030	162	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1031	162	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1032	162	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1033	162	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1034	162	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1035	162	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1036	163	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1037	163	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1038	163	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1039	163	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1040	163	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1041	163	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1042	164	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1043	164	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1044	164	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1045	164	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1046	164	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1047	164	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1048	11	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1049	11	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1050	11	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1051	11	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1052	11	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1053	11	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1054	165	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1055	165	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1056	165	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1057	165	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1058	165	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1059	165	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1060	166	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1061	166	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1062	166	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1063	166	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1064	166	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1065	166	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1066	145	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1067	145	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1068	145	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1069	145	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1070	145	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1071	145	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1072	149	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1073	149	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1074	149	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1075	149	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1076	149	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1077	149	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1078	178	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1079	178	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1080	178	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1081	178	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1082	178	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1083	178	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1084	167	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1085	167	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1086	167	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1087	167	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1088	167	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1089	167	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1090	146	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1091	146	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1092	146	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1093	146	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1094	146	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1095	146	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1096	104	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1097	104	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1098	104	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1099	104	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1100	104	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1101	104	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1102	168	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1103	168	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1104	168	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1105	168	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1106	168	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1107	168	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1108	169	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1109	169	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1110	169	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1111	169	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1112	169	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1113	169	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1114	166	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1115	166	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1116	166	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1117	166	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1118	166	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1119	166	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1120	170	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1121	170	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1122	170	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1123	170	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1124	170	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1125	170	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1126	138	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1127	138	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1128	138	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1129	138	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1130	138	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1131	138	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1132	171	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1133	171	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1134	171	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1135	171	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1136	171	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1137	171	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1138	172	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1139	172	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1140	172	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1141	172	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1142	172	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1143	172	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1144	173	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1145	173	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1146	173	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1147	173	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1148	173	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1149	173	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1150	97	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1151	97	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1152	97	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1153	97	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1154	97	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1155	97	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1156	174	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1157	174	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1158	174	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1159	174	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1160	174	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1161	174	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1162	122	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1163	122	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1164	122	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1165	122	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1166	122	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1167	122	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1168	121	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1169	121	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1170	121	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1171	121	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1172	121	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1173	121	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1174	174	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1175	174	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1176	174	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1177	174	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1178	174	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1179	174	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1180	141	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1181	141	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1182	141	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1183	141	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1184	141	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1185	141	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1186	175	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1187	175	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1188	175	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1189	175	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1190	175	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1191	175	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1192	112	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1193	112	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1194	112	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1195	112	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1196	112	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1197	112	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1198	125	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1199	125	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1200	125	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1201	125	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1202	125	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1203	125	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1204	176	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1205	176	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1206	176	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1207	176	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1208	176	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1209	176	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1210	177	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1211	177	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1212	177	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1213	177	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1214	177	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1215	177	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1216	149	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1217	149	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1218	149	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1219	149	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1220	149	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1221	149	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1222	178	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1223	178	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1224	178	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1225	178	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1226	178	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1227	178	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1228	98	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1229	98	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1230	98	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1231	98	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1232	98	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1233	98	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1234	179	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1235	179	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1236	179	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1237	179	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1238	179	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1239	179	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1240	165	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1241	165	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1242	165	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1243	165	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1244	165	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1245	165	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1246	171	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1247	171	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1248	171	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1249	171	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1250	171	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1251	171	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1252	98	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1253	98	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1254	98	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1255	98	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1256	98	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1257	98	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1258	104	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1259	104	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1260	104	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1261	104	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1262	104	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1263	104	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1264	180	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1265	180	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1266	180	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1267	180	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1268	180	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1269	180	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1270	100	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1271	100	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1272	100	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1273	100	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1274	100	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1275	100	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1276	103	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1277	103	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1278	103	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1279	103	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1280	103	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1281	103	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1282	49	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1283	49	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1284	49	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1285	49	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1286	49	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1287	49	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1288	59	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1289	59	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1290	59	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1291	59	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1292	59	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1293	59	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1294	59	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1295	59	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1296	59	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1297	59	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1298	59	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1299	59	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1300	77	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1301	77	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1302	77	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1303	77	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1304	77	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1305	77	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1306	41	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1307	41	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1308	41	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1309	41	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1310	41	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1311	41	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1312	90	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1313	90	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1314	90	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1315	90	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1316	90	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1317	90	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1318	90	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1319	90	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1320	90	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1321	90	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1322	90	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1323	90	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1324	57	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1325	57	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1326	57	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1327	57	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1328	57	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1329	57	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1330	53	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1331	53	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1332	53	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1333	53	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1334	53	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1335	53	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1336	20	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1337	20	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1338	20	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1339	20	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1340	20	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1341	20	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1342	24	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1343	24	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1344	24	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1345	24	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1346	24	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1347	24	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1348	93	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1349	93	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1350	93	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1351	93	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1352	93	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1353	93	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1354	31	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1355	31	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1356	31	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1357	31	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1358	31	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1359	31	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1360	50	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1361	50	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1362	50	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1363	50	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1364	50	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1365	50	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1366	87	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1367	87	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1368	87	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1369	87	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1370	87	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1371	87	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1372	87	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1373	87	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1374	87	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1375	87	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1376	87	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1377	87	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1378	181	\N	196	\N	\N	Estad├¡a de habitaci├│n	568.09	4	2272.36	0.00	0.00	2272.36
1379	181	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
1380	181	2	\N	\N	\N	Masaje Relajante 60 min	45.00	1	45.00	0.00	0.00	45.00
1381	181	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1382	182	\N	809	\N	\N	Estad├¡a de habitaci├│n	377.14	4	1508.56	0.00	0.00	1508.56
1383	182	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1384	182	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1385	182	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1386	183	\N	570	\N	\N	Estad├¡a de habitaci├│n	224.96	4	899.84	0.00	0.00	899.84
1387	183	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
1388	183	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1389	183	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
1390	184	\N	198	\N	\N	Estad├¡a de habitaci├│n	473.03	2	946.06	0.00	0.00	946.06
1391	184	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1392	184	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1393	184	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1394	185	\N	547	\N	\N	Estad├¡a de habitaci├│n	612.81	6	3676.86	0.00	0.00	3676.86
1395	185	4	\N	\N	\N	Servicio a la Habitaci??n	10.00	1	10.00	0.00	0.00	10.00
1396	185	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
1397	185	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
1398	186	\N	729	\N	\N	Estad├¡a de habitaci├│n	696.78	2	1393.56	0.00	0.00	1393.56
1399	186	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
1400	186	7	\N	\N	\N	Alquiler de Bicicleta	12.00	1	12.00	0.00	0.00	12.00
1401	186	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
1402	187	\N	97	\N	\N	Estad├¡a de habitaci├│n	316.30	4	1265.20	0.00	0.00	1265.20
1403	187	5	\N	\N	\N	Tour Guiado Volcanes	60.00	1	60.00	0.00	0.00	60.00
1404	187	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
1405	187	1	\N	\N	\N	Desayuno Buffet	15.00	1	15.00	0.00	0.00	15.00
1406	188	\N	151	\N	\N	Estad├¡a de habitaci├│n	110.54	3	331.62	0.00	0.00	331.62
1407	188	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
1408	188	10	\N	\N	\N	Estacionamiento Valet	32.00	1	32.00	0.00	0.00	32.00
1409	188	8	\N	\N	\N	Clase de Surf Privada	25.00	1	25.00	0.00	0.00	25.00
1410	189	\N	121	\N	\N	Estad├¡a de habitaci├│n	694.55	5	3472.75	0.00	0.00	3472.75
1411	189	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1412	189	3	\N	\N	\N	Transporte Aeropuerto	35.00	1	35.00	0.00	0.00	35.00
1413	189	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
1414	190	\N	349	\N	\N	Estad├¡a de habitaci├│n	146.04	5	730.20	0.00	0.00	730.20
1415	190	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
1416	190	9	\N	\N	\N	Cena Rom??ntica en Playa	80.00	1	80.00	0.00	0.00	80.00
1417	190	6	\N	\N	\N	Lavander??a (por libra)	41.00	1	41.00	0.00	0.00	41.00
\.


--
-- TOC entry 5346 (class 0 OID 31058)
-- Dependencies: 225
-- Data for Name: detalle_reservacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.detalle_reservacion (id_detalle_reservacion, id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida) FROM stdin;
1	680	649	7	2026-02-12	2026-02-14
3	511	234	8	2025-12-31	2026-01-04
4	934	699	3	2025-07-27	2025-07-30
5	367	635	7	2025-07-30	2025-08-06
6	426	672	2	2025-02-17	2025-02-20
7	269	50	2	2025-04-14	2025-04-21
8	460	719	9	2025-10-13	2025-10-20
9	994	366	7	2025-10-13	2025-10-17
10	308	496	1	2025-02-25	2025-02-27
11	780	342	3	2025-09-23	2025-09-26
12	952	681	3	2025-09-01	2025-09-07
13	967	428	1	2025-08-11	2025-08-16
14	702	803	4	2026-04-05	2026-04-10
16	544	688	4	2026-02-17	2026-02-18
17	577	946	1	2026-02-16	2026-02-23
18	953	647	3	2025-02-03	2025-02-06
19	915	804	9	2026-04-17	2026-04-21
20	137	241	7	2025-10-26	2025-10-27
21	149	384	3	2026-07-01	2026-07-02
22	123	504	9	2026-07-06	2026-07-13
23	715	109	7	2025-02-16	2025-02-20
24	284	727	9	2026-04-26	2026-05-03
25	318	379	9	2026-02-03	2026-02-04
26	132	636	3	2025-10-27	2025-11-01
27	597	77	6	2026-05-02	2026-05-08
28	91	249	5	2026-12-07	2026-12-14
29	235	808	6	2025-07-24	2025-07-29
30	88	926	7	2025-03-13	2025-03-17
32	384	514	7	2025-02-25	2025-03-02
33	700	181	3	2025-07-01	2025-07-02
34	305	166	4	2026-04-25	2026-05-02
35	937	821	6	2025-07-11	2025-07-14
36	137	324	7	2025-11-30	2025-12-01
37	465	64	5	2025-09-17	2025-09-21
38	248	900	8	2025-10-10	2025-10-14
39	586	380	2	2025-08-15	2025-08-19
40	708	595	6	2025-02-13	2025-02-20
41	986	695	2	2026-06-25	2026-06-27
42	646	80	9	2026-09-25	2026-10-01
43	793	902	1	2025-09-20	2025-09-24
44	887	303	3	2026-04-09	2026-04-10
45	276	454	6	2025-11-30	2025-12-02
46	389	374	1	2025-08-10	2025-08-13
47	260	385	4	2025-03-24	2025-03-29
48	261	786	10	2025-05-25	2025-05-26
49	762	653	5	2025-03-12	2025-03-18
50	12	712	7	2026-08-07	2026-08-10
51	410	44	6	2026-12-06	2026-12-11
53	183	884	3	2026-03-22	2026-03-27
54	84	611	6	2025-12-23	2025-12-25
55	19	513	3	2026-09-02	2026-09-06
56	61	466	10	2026-02-10	2026-02-16
57	446	850	10	2026-03-28	2026-04-03
58	209	507	8	2025-03-22	2025-03-26
59	85	815	5	2025-06-13	2025-06-18
60	754	199	3	2026-08-19	2026-08-22
61	84	558	3	2025-03-27	2025-04-01
62	976	456	5	2026-08-19	2026-08-25
63	675	953	10	2026-12-28	2027-01-03
64	827	244	3	2025-06-05	2025-06-09
65	695	28	2	2026-02-09	2026-02-15
66	744	583	6	2025-08-23	2025-08-26
67	76	833	6	2026-04-11	2026-04-15
68	889	941	10	2025-06-14	2025-06-15
69	581	814	10	2025-12-26	2025-12-28
70	783	903	10	2025-03-04	2025-03-06
71	759	404	10	2026-08-12	2026-08-16
72	885	462	8	2026-09-06	2026-09-09
73	212	143	3	2025-06-19	2025-06-26
74	884	29	3	2025-11-13	2025-11-17
75	167	69	7	2026-02-03	2026-02-08
76	237	873	7	2026-04-26	2026-04-27
77	641	546	1	2025-10-23	2025-10-29
78	884	867	10	2025-06-29	2025-06-30
79	740	699	7	2025-08-02	2025-08-07
80	462	247	7	2025-02-24	2025-02-25
81	425	399	4	2025-10-08	2025-10-12
82	524	155	6	2025-06-26	2025-07-03
84	937	975	4	2026-01-29	2026-02-05
85	793	723	10	2026-07-04	2026-07-11
86	137	629	3	2025-12-28	2026-01-04
88	484	876	6	2025-03-01	2025-03-07
89	846	650	8	2025-07-07	2025-07-10
90	917	744	10	2026-11-13	2026-11-14
91	366	761	10	2026-02-27	2026-03-03
93	321	576	1	2026-11-06	2026-11-12
94	321	222	2	2026-10-14	2026-10-20
95	156	155	4	2026-05-09	2026-05-11
96	180	944	1	2026-11-04	2026-11-09
97	682	558	3	2026-09-24	2026-09-28
98	803	621	9	2025-11-10	2025-11-13
99	848	617	7	2025-11-03	2025-11-10
100	328	447	3	2025-03-29	2025-03-30
101	977	517	4	2026-01-26	2026-01-29
102	588	506	9	2026-05-02	2026-05-07
103	96	463	9	2026-01-14	2026-01-20
104	341	595	4	2025-04-27	2025-04-29
105	811	467	8	2025-06-30	2025-07-06
106	114	323	7	2025-06-08	2025-06-13
107	507	624	3	2026-09-28	2026-09-30
108	628	207	1	2026-07-22	2026-07-26
109	579	898	3	2025-02-23	2025-02-28
110	168	877	7	2025-11-27	2025-12-01
111	921	524	3	2026-03-24	2026-03-26
112	220	52	3	2025-10-22	2025-10-24
113	93	226	6	2026-07-26	2026-07-30
114	598	586	4	2025-11-15	2025-11-16
115	283	583	6	2026-11-22	2026-11-29
116	898	173	4	2026-07-08	2026-07-14
117	887	494	6	2025-08-13	2025-08-20
118	256	135	2	2025-10-09	2025-10-16
119	446	1	4	2025-11-26	2025-11-30
120	545	645	6	2026-04-18	2026-04-19
121	904	316	7	2026-06-29	2026-07-01
122	815	647	3	2025-01-04	2025-01-05
123	101	546	8	2026-08-18	2026-08-22
124	78	14	5	2025-09-17	2025-09-22
125	965	758	3	2025-08-27	2025-09-01
126	532	307	6	2025-01-27	2025-01-29
127	947	430	5	2025-12-03	2025-12-08
128	584	891	5	2026-03-31	2026-04-05
129	571	793	9	2026-06-17	2026-06-18
130	502	764	8	2026-11-30	2026-12-06
131	707	56	1	2026-09-28	2026-10-01
132	863	82	1	2025-11-16	2025-11-17
133	636	578	4	2026-08-14	2026-08-17
135	583	877	6	2025-05-08	2025-05-15
136	189	243	2	2025-11-28	2025-12-01
137	692	357	7	2026-10-27	2026-10-28
138	345	500	9	2025-07-15	2025-07-20
139	270	302	6	2026-10-02	2026-10-09
140	305	409	1	2026-04-06	2026-04-13
141	416	307	5	2025-05-06	2025-05-12
142	957	784	8	2025-02-21	2025-02-28
143	499	811	5	2025-04-10	2025-04-13
144	41	264	10	2026-11-05	2026-11-07
145	832	109	7	2026-04-21	2026-04-27
146	154	837	6	2025-09-02	2025-09-03
147	855	94	2	2026-09-02	2026-09-04
148	915	596	5	2026-03-20	2026-03-25
149	3	246	3	2025-11-09	2025-11-15
150	339	416	9	2026-03-29	2026-03-31
151	403	201	8	2025-03-11	2025-03-17
152	239	271	2	2025-06-07	2025-06-12
153	669	79	7	2026-06-11	2026-06-15
154	867	221	4	2025-07-14	2025-07-21
155	982	414	8	2025-02-04	2025-02-05
156	529	628	9	2025-09-06	2025-09-09
157	517	473	9	2025-07-29	2025-08-05
158	700	960	4	2025-09-19	2025-09-25
159	862	602	2	2026-01-01	2026-01-02
160	31	787	9	2025-11-21	2025-11-23
161	856	331	5	2026-08-11	2026-08-16
162	666	88	7	2025-02-01	2025-02-02
163	513	930	10	2025-01-23	2025-01-30
164	186	313	2	2026-01-22	2026-01-24
165	176	390	9	2025-10-04	2025-10-08
166	760	227	9	2025-08-25	2025-08-28
167	15	548	1	2026-03-16	2026-03-19
168	470	915	6	2026-07-05	2026-07-07
169	435	182	9	2025-06-20	2025-06-24
170	513	31	1	2026-12-25	2026-12-30
171	849	299	5	2026-07-26	2026-07-29
172	693	712	3	2026-07-08	2026-07-15
173	982	82	7	2025-01-08	2025-01-15
174	784	708	9	2026-03-18	2026-03-21
175	885	547	9	2026-04-20	2026-04-23
177	741	38	10	2025-09-06	2025-09-09
178	415	895	9	2025-05-11	2025-05-15
179	828	547	6	2025-05-23	2025-05-27
180	519	168	8	2026-08-11	2026-08-13
181	178	336	3	2026-10-03	2026-10-08
183	106	243	5	2026-02-12	2026-02-17
184	278	700	5	2025-03-27	2025-04-02
185	155	166	9	2026-07-08	2026-07-14
186	491	623	8	2025-07-29	2025-08-04
187	903	884	3	2025-12-21	2025-12-26
188	786	401	5	2025-02-22	2025-02-26
189	693	455	5	2026-03-27	2026-03-29
190	776	916	9	2025-04-10	2025-04-15
191	152	697	5	2025-05-01	2025-05-02
192	63	508	3	2025-04-10	2025-04-16
193	110	492	5	2025-06-30	2025-07-02
194	510	432	3	2025-09-11	2025-09-12
197	21	138	10	2026-02-13	2026-02-19
198	774	777	9	2026-01-30	2026-02-03
199	817	359	3	2025-06-19	2025-06-21
200	970	222	1	2025-06-08	2025-06-10
201	466	643	6	2025-06-07	2025-06-13
202	627	937	10	2025-06-13	2025-06-17
203	474	188	6	2025-03-26	2025-03-28
204	64	826	9	2026-10-18	2026-10-20
205	407	414	8	2025-02-25	2025-02-28
206	576	777	7	2025-12-01	2025-12-04
207	681	480	8	2026-03-30	2026-04-02
208	919	593	2	2026-03-16	2026-03-17
209	342	806	3	2025-08-13	2025-08-15
210	250	572	9	2026-03-10	2026-03-15
211	366	482	10	2025-06-03	2025-06-04
212	454	242	6	2025-01-29	2025-02-04
213	689	171	8	2026-07-23	2026-07-30
214	535	558	2	2026-09-22	2026-09-29
215	260	850	3	2025-07-25	2025-07-31
216	283	652	3	2025-07-15	2025-07-17
217	653	386	8	2025-11-04	2025-11-10
218	800	30	10	2026-03-27	2026-03-31
219	934	333	7	2026-11-05	2026-11-11
220	288	754	9	2026-06-25	2026-07-01
221	513	248	1	2026-02-03	2026-02-05
222	795	435	8	2026-02-26	2026-03-05
223	594	267	4	2026-07-29	2026-08-05
224	91	32	1	2026-06-25	2026-06-26
225	16	446	6	2026-09-11	2026-09-17
226	368	375	2	2026-05-22	2026-05-29
227	462	86	1	2025-06-15	2025-06-22
228	2	517	2	2025-10-13	2025-10-17
229	148	864	10	2025-03-10	2025-03-15
230	734	73	5	2025-05-09	2025-05-14
231	895	749	4	2026-02-17	2026-02-20
232	562	815	9	2026-04-18	2026-04-22
233	403	114	10	2026-07-02	2026-07-04
234	955	749	8	2026-07-27	2026-08-01
236	716	745	8	2025-08-19	2025-08-23
237	695	378	5	2026-12-06	2026-12-11
238	396	555	8	2026-02-03	2026-02-04
239	981	232	7	2025-03-14	2025-03-19
241	553	107	4	2026-09-22	2026-09-26
242	310	440	10	2026-11-22	2026-11-24
243	254	790	1	2025-08-18	2025-08-19
244	640	113	4	2026-02-04	2026-02-06
245	451	366	8	2026-03-18	2026-03-24
246	348	160	1	2026-03-24	2026-03-30
247	304	214	8	2025-06-30	2025-07-05
248	958	807	10	2026-04-06	2026-04-08
249	405	681	6	2026-05-02	2026-05-04
250	597	602	3	2025-10-13	2025-10-18
251	39	781	6	2026-12-26	2027-01-01
252	508	24	3	2025-01-23	2025-01-25
253	987	823	9	2025-11-01	2025-11-08
254	520	569	5	2025-08-10	2025-08-13
255	78	25	9	2026-04-30	2026-05-07
256	618	112	8	2026-12-06	2026-12-10
257	536	864	2	2025-10-18	2025-10-24
258	736	257	3	2026-08-30	2026-09-02
259	128	606	5	2025-05-30	2025-06-02
260	281	773	6	2026-02-02	2026-02-08
261	793	293	6	2025-10-25	2025-10-28
262	541	415	5	2025-08-05	2025-08-12
263	354	957	8	2026-03-07	2026-03-08
264	539	340	4	2025-06-01	2025-06-02
265	901	81	2	2025-07-20	2025-07-25
266	507	569	10	2026-06-14	2026-06-19
267	271	553	1	2026-02-02	2026-02-05
268	939	112	2	2026-07-12	2026-07-13
269	532	522	10	2025-02-22	2025-02-25
270	574	921	3	2026-01-25	2026-01-28
271	816	643	1	2026-06-18	2026-06-20
272	66	378	9	2025-09-28	2025-10-02
273	594	203	5	2026-05-31	2026-06-01
274	736	487	2	2026-04-19	2026-04-21
275	937	671	5	2025-06-17	2025-06-24
276	16	799	2	2026-02-27	2026-03-04
277	300	683	1	2026-04-07	2026-04-09
278	336	914	10	2026-12-20	2026-12-27
279	134	307	5	2025-02-01	2025-02-06
280	821	493	7	2026-02-09	2026-02-11
281	279	681	7	2026-12-12	2026-12-17
282	26	2	7	2026-05-19	2026-05-22
283	727	74	9	2026-02-12	2026-02-19
284	837	157	3	2026-01-20	2026-01-27
285	662	723	1	2025-11-10	2025-11-16
286	927	437	8	2025-01-14	2025-01-15
287	232	541	9	2026-06-20	2026-06-27
289	641	258	2	2025-10-24	2025-10-27
290	547	634	8	2025-09-26	2025-09-29
291	100	154	9	2026-11-07	2026-11-13
292	499	39	10	2026-07-03	2026-07-06
293	94	82	6	2025-11-25	2025-11-26
294	667	497	4	2025-03-01	2025-03-08
295	966	831	7	2026-07-31	2026-08-04
296	198	838	6	2025-10-07	2025-10-10
297	739	363	6	2026-10-10	2026-10-14
298	430	813	6	2025-10-01	2025-10-07
299	909	131	3	2025-07-12	2025-07-14
300	7	940	9	2025-02-24	2025-02-27
301	470	125	4	2026-05-22	2026-05-24
302	562	470	3	2026-02-28	2026-03-04
303	853	747	8	2026-07-24	2026-07-31
304	231	824	7	2025-05-15	2025-05-22
305	297	803	4	2026-01-12	2026-01-15
306	409	971	4	2026-07-20	2026-07-21
307	695	894	10	2025-02-18	2025-02-24
308	541	933	6	2026-12-29	2026-12-30
309	512	704	3	2026-08-14	2026-08-18
310	273	215	10	2025-01-17	2025-01-19
311	962	70	1	2025-07-05	2025-07-08
312	35	437	2	2025-04-11	2025-04-18
313	517	240	4	2026-02-14	2026-02-17
314	430	233	2	2025-09-12	2025-09-19
315	103	236	7	2026-07-05	2026-07-08
316	512	69	2	2026-06-29	2026-07-04
317	941	896	5	2025-01-01	2025-01-08
318	361	655	5	2025-02-15	2025-02-18
320	147	846	7	2025-12-04	2025-12-08
321	499	122	5	2025-12-21	2025-12-28
322	460	701	10	2026-05-31	2026-06-06
323	858	776	6	2025-09-24	2025-09-28
324	212	196	5	2026-11-27	2026-12-02
325	597	515	5	2025-12-14	2025-12-20
326	553	295	4	2025-01-19	2025-01-22
327	62	437	2	2026-02-22	2026-02-27
328	250	662	9	2026-07-20	2026-07-25
329	288	393	10	2025-05-03	2025-05-04
330	982	259	7	2026-12-11	2026-12-14
331	735	721	7	2025-02-05	2025-02-10
332	231	964	9	2026-08-08	2026-08-09
333	8	936	2	2026-12-17	2026-12-20
334	100	242	7	2025-06-27	2025-07-02
335	128	939	3	2025-11-26	2025-11-28
337	709	91	9	2025-04-28	2025-05-04
338	827	45	7	2026-09-10	2026-09-14
339	851	428	4	2025-07-12	2025-07-18
340	500	883	4	2025-02-04	2025-02-07
341	665	449	7	2026-10-12	2026-10-14
342	630	896	10	2026-09-13	2026-09-19
343	576	951	3	2026-07-07	2026-07-13
344	96	70	9	2025-04-05	2025-04-11
345	571	644	1	2025-08-24	2025-08-31
346	484	932	9	2025-09-08	2025-09-14
347	168	131	9	2025-11-07	2025-11-09
348	55	258	2	2025-09-06	2025-09-11
349	963	831	2	2026-07-18	2026-07-22
350	642	244	9	2026-12-27	2027-01-02
351	402	370	9	2025-11-30	2025-12-02
352	752	653	5	2026-09-23	2026-09-27
353	532	877	2	2026-09-17	2026-09-21
354	606	236	9	2026-03-17	2026-03-24
355	221	211	5	2026-04-30	2026-05-04
356	321	296	6	2025-04-09	2025-04-12
357	914	509	1	2026-11-14	2026-11-19
358	668	896	7	2025-01-16	2025-01-18
359	919	880	2	2025-06-05	2025-06-10
360	785	370	2	2026-10-22	2026-10-25
361	243	426	7	2026-01-25	2026-02-01
362	602	111	8	2025-06-27	2025-07-01
363	707	673	2	2025-01-12	2025-01-13
364	586	661	3	2026-08-23	2026-08-26
365	472	282	5	2025-08-28	2025-09-01
366	825	190	10	2026-03-12	2026-03-14
367	377	612	10	2025-03-01	2025-03-06
368	845	335	6	2025-09-03	2025-09-09
369	124	647	10	2025-02-16	2025-02-20
370	5	655	8	2026-11-23	2026-11-29
371	699	32	1	2025-09-21	2025-09-22
372	88	791	1	2025-02-06	2025-02-10
373	490	673	6	2025-01-29	2025-02-05
375	351	704	7	2025-05-08	2025-05-09
376	174	103	5	2026-01-01	2026-01-02
377	286	295	10	2026-06-12	2026-06-13
378	763	480	6	2025-12-20	2025-12-25
379	815	533	8	2026-03-13	2026-03-17
380	947	599	2	2026-08-29	2026-08-31
381	266	147	8	2025-08-19	2025-08-25
382	116	953	9	2025-09-07	2025-09-11
384	21	571	4	2025-03-11	2025-03-12
385	798	320	7	2025-01-06	2025-01-12
386	383	435	9	2025-01-18	2025-01-24
387	958	863	3	2025-01-20	2025-01-24
388	637	752	4	2026-02-23	2026-03-01
390	534	673	10	2025-09-07	2025-09-12
391	822	220	6	2026-02-23	2026-03-01
392	500	457	3	2025-08-30	2025-09-05
393	638	95	5	2025-10-30	2025-11-06
394	442	626	10	2025-03-12	2025-03-14
395	80	562	10	2025-08-19	2025-08-20
396	228	836	10	2026-08-20	2026-08-26
397	36	610	9	2025-04-15	2025-04-18
398	440	498	10	2025-09-27	2025-10-03
400	191	265	6	2025-05-15	2025-05-20
401	169	274	10	2025-02-24	2025-03-01
402	220	578	8	2025-03-17	2025-03-22
403	773	583	8	2026-09-08	2026-09-11
404	949	894	2	2025-02-20	2025-02-22
405	127	40	10	2026-11-07	2026-11-13
406	936	372	9	2025-11-11	2025-11-13
407	557	325	1	2026-03-04	2026-03-05
408	106	146	10	2025-12-13	2025-12-15
409	856	471	10	2026-01-17	2026-01-21
410	964	958	5	2026-02-23	2026-02-28
411	403	543	5	2026-05-26	2026-05-28
412	951	485	8	2026-11-28	2026-12-03
413	59	42	8	2025-08-06	2025-08-12
414	160	540	7	2025-12-13	2025-12-19
415	963	933	8	2026-05-02	2026-05-07
416	641	730	8	2025-01-08	2025-01-10
417	651	314	3	2025-07-28	2025-07-31
418	409	839	10	2026-05-16	2026-05-19
419	573	676	2	2025-02-13	2025-02-16
420	966	14	8	2025-05-05	2025-05-07
422	884	831	10	2026-07-03	2026-07-07
423	907	165	4	2025-10-05	2025-10-10
424	533	912	10	2026-08-08	2026-08-09
425	739	497	8	2025-12-21	2025-12-26
426	392	347	10	2025-07-14	2025-07-18
427	951	553	3	2025-08-21	2025-08-25
428	162	727	2	2025-06-11	2025-06-16
429	228	435	1	2025-03-11	2025-03-13
430	764	246	6	2025-08-10	2025-08-11
431	468	361	4	2026-06-06	2026-06-09
432	121	33	7	2025-12-23	2025-12-29
433	550	819	7	2025-09-24	2025-09-28
434	691	6	9	2026-02-06	2026-02-09
435	965	284	6	2026-11-21	2026-11-22
436	754	932	10	2025-11-08	2025-11-15
437	124	670	9	2026-09-18	2026-09-21
438	406	368	9	2026-12-03	2026-12-07
439	696	17	5	2025-11-23	2025-11-25
440	18	630	10	2026-10-13	2026-10-17
441	697	107	7	2026-07-03	2026-07-07
442	557	207	5	2025-07-04	2025-07-09
443	696	455	4	2026-09-11	2026-09-12
444	765	858	6	2025-09-17	2025-09-24
445	26	425	10	2026-05-04	2026-05-11
446	200	776	6	2025-10-24	2025-10-30
447	502	834	1	2026-07-16	2026-07-20
448	300	166	10	2025-12-28	2026-01-02
449	63	197	5	2026-05-22	2026-05-29
450	655	260	1	2026-03-29	2026-04-04
451	711	65	1	2026-02-04	2026-02-06
452	220	110	4	2025-10-04	2025-10-06
453	305	239	7	2025-09-23	2025-09-27
454	281	110	4	2025-01-29	2025-01-30
455	278	517	1	2025-01-12	2025-01-13
456	405	203	5	2026-12-28	2027-01-04
457	254	607	5	2026-02-15	2026-02-21
458	819	866	4	2026-10-09	2026-10-12
459	922	297	5	2025-02-15	2025-02-21
460	952	744	5	2026-10-10	2026-10-17
461	939	696	10	2026-01-01	2026-01-07
462	579	227	1	2026-02-09	2026-02-13
463	856	171	1	2026-04-25	2026-05-02
464	51	903	9	2026-04-18	2026-04-25
465	793	633	3	2026-04-28	2026-05-02
466	324	112	9	2025-10-01	2025-10-08
467	566	429	1	2025-11-24	2025-11-26
468	101	682	3	2026-07-23	2026-07-24
469	450	430	9	2026-02-08	2026-02-14
470	73	11	7	2025-01-27	2025-01-28
471	671	85	1	2026-07-31	2026-08-07
472	981	207	1	2026-09-07	2026-09-13
473	420	754	10	2025-01-21	2025-01-24
475	158	687	8	2026-08-15	2026-08-17
476	139	292	6	2025-04-08	2025-04-09
477	445	595	4	2025-06-13	2025-06-19
478	904	566	3	2026-07-27	2026-08-01
479	563	167	10	2025-11-12	2025-11-14
480	636	116	9	2026-04-06	2026-04-08
481	922	46	2	2025-05-06	2025-05-10
482	166	398	3	2025-12-29	2026-01-03
483	436	902	4	2025-06-23	2025-06-27
484	392	267	7	2026-02-27	2026-03-06
485	471	213	3	2025-08-22	2025-08-24
486	743	475	3	2025-06-22	2025-06-29
487	503	229	5	2026-01-26	2026-01-30
488	151	24	1	2025-06-29	2025-07-04
489	319	467	9	2025-11-27	2025-12-04
490	71	229	4	2026-06-29	2026-07-05
491	655	817	2	2025-08-14	2025-08-16
492	841	808	4	2026-02-07	2026-02-12
493	827	390	10	2026-04-12	2026-04-17
494	945	256	8	2025-11-13	2025-11-20
495	719	790	7	2025-06-22	2025-06-29
496	180	642	9	2026-06-29	2026-06-30
497	96	954	10	2026-11-14	2026-11-15
498	190	19	6	2026-07-27	2026-07-28
499	322	626	10	2025-11-26	2025-12-03
500	71	947	1	2025-06-07	2025-06-12
501	327	902	7	2025-10-03	2025-10-07
502	532	225	5	2025-07-11	2025-07-18
503	376	901	4	2025-12-24	2025-12-26
504	930	439	10	2025-09-23	2025-09-29
505	31	965	5	2025-07-31	2025-08-05
506	682	219	1	2026-01-01	2026-01-04
507	228	380	9	2026-11-27	2026-12-02
508	143	640	1	2025-12-26	2025-12-29
509	832	422	8	2025-10-13	2025-10-18
510	66	146	7	2026-07-02	2026-07-05
511	626	879	6	2026-11-16	2026-11-21
512	959	79	7	2025-04-11	2025-04-13
513	176	467	10	2026-03-09	2026-03-14
514	279	288	6	2026-01-13	2026-01-16
516	930	292	4	2025-08-05	2025-08-10
517	490	559	3	2026-02-19	2026-02-23
518	365	189	8	2025-01-06	2025-01-12
519	234	835	4	2026-01-21	2026-01-23
520	757	392	2	2025-02-04	2025-02-05
521	621	860	7	2026-12-12	2026-12-18
522	64	872	5	2026-05-11	2026-05-17
523	350	485	9	2025-01-31	2025-02-02
524	791	627	5	2025-10-27	2025-11-02
525	542	568	10	2026-08-18	2026-08-21
526	436	55	6	2026-04-19	2026-04-25
527	396	519	9	2026-03-03	2026-03-06
528	390	919	1	2026-09-10	2026-09-16
529	876	299	8	2026-02-08	2026-02-13
530	558	899	2	2026-03-19	2026-03-20
531	410	607	1	2026-11-23	2026-11-28
532	211	139	10	2025-05-03	2025-05-08
533	62	81	8	2025-07-01	2025-07-05
534	277	505	3	2025-07-21	2025-07-27
535	321	553	10	2026-12-17	2026-12-19
536	865	945	1	2025-07-13	2025-07-16
537	150	806	8	2026-02-17	2026-02-20
538	721	510	7	2025-08-08	2025-08-13
539	728	617	5	2025-10-05	2025-10-06
540	468	724	3	2025-06-05	2025-06-11
541	739	184	3	2025-12-15	2025-12-18
542	796	331	7	2025-02-20	2025-02-24
543	459	272	2	2026-12-28	2027-01-03
544	84	759	4	2025-11-24	2025-11-30
545	837	154	2	2025-11-30	2025-12-07
546	696	473	6	2026-01-21	2026-01-23
547	403	624	10	2026-07-26	2026-07-27
548	509	376	6	2025-06-14	2025-06-21
549	951	684	5	2025-12-10	2025-12-11
550	264	494	7	2025-02-20	2025-02-23
551	10	51	9	2025-11-13	2025-11-16
552	858	89	1	2025-03-18	2025-03-24
553	939	456	1	2025-10-01	2025-10-05
554	80	473	7	2025-11-18	2025-11-20
555	481	558	4	2025-10-06	2025-10-09
556	150	208	10	2025-08-01	2025-08-07
557	647	807	9	2025-04-28	2025-05-05
558	555	441	6	2026-02-25	2026-03-01
559	785	595	10	2026-01-16	2026-01-19
560	814	159	4	2025-05-04	2025-05-05
561	398	754	1	2025-08-19	2025-08-26
562	648	294	5	2026-07-20	2026-07-24
563	936	299	3	2025-07-18	2025-07-21
564	117	576	2	2026-10-31	2026-11-02
565	752	892	9	2025-10-14	2025-10-20
566	513	304	2	2025-08-31	2025-09-03
567	931	281	5	2025-11-02	2025-11-05
568	376	836	1	2025-04-13	2025-04-19
569	883	179	3	2025-10-08	2025-10-12
570	684	898	7	2025-03-17	2025-03-21
571	179	841	10	2025-04-12	2025-04-19
572	905	16	9	2025-10-07	2025-10-12
573	881	457	10	2026-05-26	2026-05-27
574	110	834	9	2026-04-02	2026-04-08
575	734	947	3	2026-09-21	2026-09-25
576	854	773	4	2025-09-13	2025-09-18
577	328	145	1	2026-03-19	2026-03-25
578	477	85	2	2025-02-01	2025-02-02
579	429	515	5	2025-12-01	2025-12-02
580	773	193	3	2026-08-13	2026-08-19
581	161	217	4	2026-03-09	2026-03-16
582	662	615	1	2026-07-17	2026-07-23
583	368	843	2	2025-08-13	2025-08-17
584	810	368	9	2025-07-15	2025-07-18
585	35	169	2	2025-03-30	2025-04-06
586	45	143	5	2025-09-28	2025-10-04
587	859	321	2	2025-02-16	2025-02-20
588	155	836	2	2025-04-15	2025-04-17
589	597	188	2	2025-05-27	2025-06-03
590	828	559	10	2025-05-29	2025-06-01
591	642	327	6	2026-01-04	2026-01-11
592	269	324	8	2026-04-13	2026-04-16
593	946	528	5	2026-06-27	2026-07-01
594	499	62	4	2026-02-20	2026-02-27
595	724	832	9	2026-03-09	2026-03-15
596	170	125	7	2026-08-01	2026-08-02
598	203	145	2	2026-11-25	2026-11-26
599	945	628	7	2025-03-03	2025-03-10
600	707	341	4	2026-10-31	2026-11-07
601	97	639	6	2026-04-30	2026-05-05
603	122	452	5	2026-05-04	2026-05-09
604	958	24	3	2025-10-29	2025-11-04
605	863	596	1	2025-03-07	2025-03-13
607	71	397	9	2025-10-21	2025-10-23
608	906	860	7	2025-03-21	2025-03-23
609	220	423	6	2025-08-07	2025-08-12
610	8	396	2	2026-04-03	2026-04-08
611	376	683	4	2026-08-05	2026-08-11
612	281	178	6	2026-05-13	2026-05-16
613	647	840	1	2025-08-25	2025-08-30
614	802	337	6	2025-04-17	2025-04-23
615	280	711	5	2025-09-15	2025-09-18
616	764	23	5	2025-08-12	2025-08-13
617	421	696	5	2025-02-11	2025-02-16
618	650	941	7	2025-08-09	2025-08-14
619	794	640	4	2026-03-14	2026-03-18
621	200	906	2	2026-07-16	2026-07-18
622	78	761	8	2025-10-29	2025-11-04
623	272	128	4	2026-04-05	2026-04-06
624	197	711	2	2026-03-05	2026-03-10
625	412	231	7	2026-09-25	2026-09-29
626	94	420	6	2025-02-18	2025-02-23
627	502	534	1	2025-08-18	2025-08-22
628	22	67	5	2026-05-07	2026-05-12
629	363	634	9	2026-08-14	2026-08-19
630	254	898	6	2026-08-04	2026-08-06
631	784	816	2	2026-04-11	2026-04-17
633	823	111	8	2026-04-23	2026-04-24
634	149	933	6	2026-02-02	2026-02-05
635	41	452	10	2025-07-31	2025-08-04
636	759	86	9	2026-02-02	2026-02-07
637	44	39	6	2026-01-07	2026-01-13
638	583	518	3	2025-05-31	2025-06-07
639	509	814	3	2026-08-28	2026-08-29
640	81	560	9	2026-12-15	2026-12-21
641	966	464	7	2026-01-06	2026-01-11
642	882	957	1	2026-07-12	2026-07-14
643	111	969	1	2025-06-29	2025-06-30
644	352	702	7	2026-08-28	2026-08-29
645	297	326	10	2026-02-27	2026-03-03
646	254	724	1	2025-09-21	2025-09-25
647	89	470	8	2025-01-08	2025-01-12
648	475	646	9	2025-05-14	2025-05-15
650	788	358	3	2025-01-08	2025-01-15
651	488	439	2	2025-07-06	2025-07-08
652	239	194	3	2025-03-02	2025-03-07
653	506	840	1	2026-07-30	2026-08-03
654	881	158	7	2026-03-14	2026-03-16
655	816	626	8	2025-09-01	2025-09-04
656	385	535	7	2025-04-01	2025-04-07
657	151	825	10	2025-03-27	2025-03-28
658	438	756	3	2025-09-18	2025-09-24
659	719	562	5	2026-08-30	2026-09-04
660	681	94	1	2026-11-26	2026-11-27
661	318	435	9	2026-08-19	2026-08-24
662	715	456	10	2026-10-10	2026-10-14
663	739	578	6	2025-11-09	2025-11-16
665	754	633	1	2026-12-17	2026-12-18
666	510	642	7	2026-10-01	2026-10-08
667	130	379	4	2026-09-17	2026-09-24
668	637	154	8	2026-06-16	2026-06-21
670	49	417	9	2025-06-28	2025-07-05
671	537	64	5	2025-11-25	2025-12-01
672	996	502	5	2025-03-08	2025-03-10
673	775	872	1	2025-11-22	2025-11-27
674	480	264	2	2025-03-15	2025-03-20
675	62	857	8	2025-12-15	2025-12-19
676	704	348	7	2025-08-06	2025-08-13
677	286	324	4	2026-02-13	2026-02-18
678	896	617	10	2025-03-19	2025-03-24
679	941	817	3	2026-06-15	2026-06-21
680	520	22	10	2026-01-15	2026-01-18
681	212	857	3	2025-08-06	2025-08-08
682	612	475	2	2025-12-06	2025-12-13
683	588	900	4	2025-09-19	2025-09-20
684	538	803	1	2026-08-12	2026-08-13
685	560	261	5	2026-01-03	2026-01-05
686	201	70	2	2026-05-22	2026-05-23
687	905	844	6	2026-07-04	2026-07-10
688	998	176	6	2025-02-26	2025-03-04
689	333	780	9	2025-03-05	2025-03-06
690	488	521	7	2025-05-27	2025-06-02
691	399	778	10	2026-02-05	2026-02-06
692	858	798	5	2025-03-29	2025-04-01
693	713	176	2	2026-07-02	2026-07-06
694	22	775	6	2026-02-11	2026-02-12
695	709	481	3	2025-05-07	2025-05-12
697	643	853	10	2026-12-06	2026-12-07
698	1	271	7	2025-08-22	2025-08-27
699	870	650	5	2026-01-27	2026-01-30
701	412	28	3	2025-08-10	2025-08-13
702	637	836	2	2025-10-16	2025-10-17
703	422	642	9	2025-10-31	2025-11-01
704	243	639	2	2026-01-12	2026-01-14
705	539	753	6	2025-06-05	2025-06-11
706	454	490	7	2026-01-19	2026-01-26
707	255	960	5	2025-07-19	2025-07-21
708	702	143	6	2026-04-06	2026-04-08
709	525	329	1	2026-03-16	2026-03-18
710	495	695	8	2026-01-17	2026-01-20
711	237	431	3	2025-09-22	2025-09-28
712	924	512	1	2026-04-30	2026-05-04
713	936	343	5	2025-01-31	2025-02-07
714	253	247	7	2026-03-30	2026-04-04
715	977	914	5	2025-02-20	2025-02-25
716	820	387	8	2026-02-26	2026-03-02
717	519	862	3	2025-10-24	2025-10-28
718	807	655	1	2026-04-29	2026-05-06
719	166	774	4	2026-09-01	2026-09-05
720	764	456	3	2025-11-24	2025-11-28
721	154	812	1	2025-05-25	2025-05-30
722	842	561	4	2025-11-01	2025-11-06
723	724	167	8	2025-09-17	2025-09-20
724	656	404	9	2025-07-29	2025-07-31
725	379	695	9	2026-03-02	2026-03-06
726	62	555	2	2026-03-20	2026-03-26
727	317	314	6	2025-11-27	2025-12-01
728	896	539	5	2026-04-27	2026-04-30
729	825	365	5	2026-09-09	2026-09-10
730	186	295	6	2025-09-21	2025-09-27
731	560	152	7	2026-08-21	2026-08-25
732	599	182	2	2025-05-02	2025-05-05
733	518	960	7	2025-02-16	2025-02-21
734	457	409	1	2025-07-09	2025-07-10
735	276	721	6	2026-11-12	2026-11-13
736	482	593	2	2025-06-18	2025-06-21
737	755	728	1	2025-12-31	2026-01-06
738	396	588	10	2026-12-30	2027-01-03
739	817	807	7	2025-05-16	2025-05-22
740	6	686	6	2026-11-15	2026-11-21
741	392	305	4	2025-01-08	2025-01-12
742	419	707	6	2025-05-12	2025-05-18
743	574	732	6	2026-10-03	2026-10-07
744	525	24	10	2025-03-28	2025-04-03
745	658	647	5	2026-05-02	2026-05-08
746	35	277	8	2025-09-14	2025-09-16
747	32	907	2	2026-08-07	2026-08-11
749	354	455	6	2025-11-07	2025-11-09
750	449	973	9	2025-10-27	2025-10-31
752	366	784	5	2025-04-27	2025-05-01
753	60	282	3	2026-11-21	2026-11-28
754	597	782	9	2026-11-07	2026-11-12
755	217	566	1	2026-02-04	2026-02-05
756	790	229	10	2026-03-29	2026-04-01
757	616	520	6	2025-02-01	2025-02-08
758	688	285	8	2026-04-06	2026-04-08
759	714	653	7	2026-09-17	2026-09-20
760	953	328	10	2026-03-08	2026-03-10
761	235	218	10	2025-01-13	2025-01-19
762	141	972	4	2025-05-08	2025-05-14
763	471	661	3	2025-10-30	2025-11-05
764	510	510	7	2026-12-29	2027-01-02
766	768	413	9	2026-05-05	2026-05-12
767	491	113	9	2026-01-13	2026-01-18
768	40	60	5	2025-11-08	2025-11-13
769	261	673	1	2025-04-29	2025-05-06
770	713	32	10	2026-11-27	2026-11-30
771	821	726	9	2026-04-24	2026-04-25
772	600	491	10	2025-08-11	2025-08-13
773	699	892	1	2026-02-18	2026-02-24
774	507	755	10	2026-11-27	2026-11-28
775	532	856	4	2025-05-22	2025-05-29
776	200	213	6	2025-08-01	2025-08-05
777	322	299	9	2025-01-15	2025-01-22
778	796	396	2	2026-03-26	2026-04-02
779	393	664	4	2026-07-14	2026-07-19
780	290	949	7	2025-11-01	2025-11-03
781	458	820	7	2026-09-10	2026-09-13
782	450	375	8	2026-06-07	2026-06-10
783	817	506	10	2026-04-13	2026-04-17
784	933	692	9	2025-05-29	2025-05-30
785	916	843	5	2026-10-11	2026-10-12
786	396	176	4	2025-06-01	2025-06-08
787	289	694	7	2026-05-01	2026-05-06
788	255	299	2	2026-12-12	2026-12-16
789	861	130	8	2025-04-06	2025-04-13
790	429	766	2	2026-10-05	2026-10-09
791	83	785	4	2025-04-15	2025-04-16
792	224	7	5	2025-07-10	2025-07-17
793	586	559	3	2025-08-16	2025-08-22
794	72	385	5	2025-10-01	2025-10-07
795	23	745	3	2025-11-20	2025-11-22
796	215	71	8	2025-11-30	2025-12-06
797	799	582	5	2025-09-24	2025-09-29
798	752	224	1	2026-11-09	2026-11-10
800	958	234	2	2025-09-22	2025-09-28
801	71	906	3	2026-11-08	2026-11-15
802	774	556	6	2025-09-26	2025-09-28
803	652	576	8	2026-05-14	2026-05-15
804	805	716	8	2026-08-16	2026-08-21
805	367	567	9	2026-10-05	2026-10-12
806	581	1	7	2026-02-22	2026-02-27
808	852	915	5	2026-04-07	2026-04-09
810	955	514	10	2025-01-21	2025-01-25
811	233	248	8	2025-04-02	2025-04-09
812	357	515	2	2026-06-01	2026-06-04
813	600	61	4	2025-08-31	2025-09-07
814	519	782	3	2026-02-16	2026-02-22
815	801	367	1	2026-12-21	2026-12-26
816	39	134	9	2025-08-02	2025-08-08
817	686	512	2	2026-10-04	2026-10-07
818	6	571	4	2025-04-30	2025-05-04
819	117	955	1	2026-09-20	2026-09-24
820	573	465	4	2025-12-07	2025-12-08
821	149	571	10	2025-03-02	2025-03-08
822	616	852	2	2025-01-02	2025-01-09
823	226	536	7	2026-04-30	2026-05-03
824	101	522	5	2026-02-11	2026-02-17
825	83	464	4	2026-01-26	2026-01-27
826	907	817	4	2026-01-05	2026-01-11
827	898	546	5	2026-12-05	2026-12-08
828	707	970	7	2026-11-02	2026-11-09
829	53	532	4	2025-10-19	2025-10-22
830	872	416	1	2026-12-10	2026-12-15
831	619	18	2	2025-04-08	2025-04-13
832	366	617	7	2025-10-15	2025-10-20
833	66	791	8	2026-03-05	2026-03-09
834	767	518	6	2025-08-13	2025-08-14
835	119	173	2	2026-05-25	2026-05-28
836	81	350	9	2025-07-29	2025-08-04
837	230	561	7	2025-12-02	2025-12-07
838	473	60	2	2025-05-15	2025-05-22
839	460	730	9	2025-10-08	2025-10-15
840	612	671	10	2026-06-09	2026-06-14
841	426	205	2	2025-02-12	2025-02-15
842	323	532	2	2026-04-29	2026-05-04
843	294	806	6	2025-03-26	2025-04-02
844	729	316	5	2026-08-14	2026-08-18
845	565	611	5	2025-02-18	2025-02-19
846	352	798	1	2026-01-05	2026-01-07
847	108	479	3	2026-01-21	2026-01-26
848	390	711	8	2025-11-20	2025-11-26
849	567	350	1	2025-07-22	2025-07-27
850	845	856	2	2026-05-10	2026-05-17
851	943	733	4	2026-05-28	2026-06-02
852	441	782	6	2026-01-20	2026-01-21
853	703	566	3	2025-06-17	2025-06-20
854	780	181	4	2025-07-03	2025-07-08
855	140	367	6	2026-02-20	2026-02-22
856	870	590	10	2026-01-01	2026-01-02
857	368	674	2	2025-11-16	2025-11-23
858	939	638	8	2025-11-08	2025-11-13
859	561	59	10	2026-08-22	2026-08-25
860	134	536	6	2025-08-11	2025-08-12
861	117	339	8	2025-11-06	2025-11-11
862	732	195	4	2025-05-02	2025-05-06
863	16	741	10	2025-08-29	2025-09-05
864	114	130	4	2026-05-08	2026-05-13
865	400	117	10	2025-10-28	2025-11-04
866	622	905	8	2025-03-26	2025-03-30
867	611	31	3	2025-06-24	2025-07-01
868	517	79	9	2025-11-01	2025-11-03
869	262	257	8	2025-09-24	2025-09-29
870	861	551	1	2026-07-21	2026-07-23
872	395	967	1	2026-03-18	2026-03-20
873	971	682	10	2025-08-09	2025-08-13
875	140	816	6	2026-07-22	2026-07-23
876	489	433	5	2025-10-02	2025-10-09
877	182	630	6	2025-11-03	2025-11-10
878	482	161	5	2026-12-16	2026-12-23
879	219	805	8	2025-08-15	2025-08-20
880	368	299	10	2026-01-07	2026-01-14
881	425	661	9	2026-08-31	2026-09-03
882	725	962	8	2025-05-21	2025-05-23
883	829	252	7	2025-02-20	2025-02-22
884	231	174	5	2026-12-30	2027-01-06
885	711	394	6	2026-12-03	2026-12-09
886	397	850	5	2025-10-15	2025-10-18
887	121	935	2	2025-09-23	2025-09-27
888	214	561	7	2025-11-14	2025-11-16
890	269	856	5	2026-07-23	2026-07-24
891	786	162	2	2026-03-30	2026-04-06
892	851	78	5	2025-07-15	2025-07-18
893	669	568	6	2026-04-30	2026-05-05
894	181	542	5	2026-10-24	2026-10-30
895	657	827	5	2025-08-22	2025-08-29
896	653	577	7	2025-09-17	2025-09-21
897	2	918	2	2025-03-14	2025-03-18
898	855	95	7	2026-01-11	2026-01-18
899	447	464	10	2025-12-01	2025-12-04
900	412	568	10	2025-08-09	2025-08-16
901	891	288	9	2025-05-23	2025-05-29
902	260	55	4	2026-06-14	2026-06-18
904	209	3	8	2025-11-16	2025-11-17
905	186	80	4	2026-02-03	2026-02-10
906	103	724	4	2025-07-19	2025-07-26
907	339	99	9	2025-10-04	2025-10-08
908	343	972	4	2026-12-08	2026-12-09
909	744	919	8	2025-04-26	2025-05-02
910	409	373	9	2026-04-14	2026-04-20
911	796	419	9	2026-08-01	2026-08-04
912	4	158	6	2026-09-15	2026-09-18
913	230	975	3	2025-11-07	2025-11-09
914	458	332	4	2025-01-09	2025-01-15
915	705	751	8	2025-05-04	2025-05-10
916	15	880	7	2025-10-17	2025-10-23
917	248	780	5	2026-12-02	2026-12-06
918	904	40	9	2026-09-08	2026-09-14
919	940	757	9	2026-01-30	2026-02-02
920	541	651	5	2026-06-04	2026-06-10
921	964	186	3	2026-09-10	2026-09-16
922	383	854	4	2025-01-02	2025-01-04
923	544	490	8	2025-08-16	2025-08-17
924	224	322	6	2025-07-13	2025-07-16
925	811	14	8	2025-05-03	2025-05-05
926	705	603	10	2025-09-25	2025-09-26
927	946	805	1	2025-03-27	2025-03-28
928	41	332	4	2026-08-14	2026-08-15
929	838	418	6	2025-11-21	2025-11-28
930	832	488	4	2025-07-08	2025-07-14
931	59	349	7	2026-05-03	2026-05-08
932	497	518	5	2026-04-06	2026-04-07
933	629	928	9	2026-01-21	2026-01-25
934	247	718	7	2026-10-22	2026-10-28
935	242	127	1	2025-04-13	2025-04-17
936	406	422	5	2026-05-06	2026-05-08
937	431	123	6	2026-04-20	2026-04-26
938	892	682	8	2026-02-12	2026-02-14
939	580	394	8	2025-06-01	2025-06-06
940	49	425	3	2025-03-16	2025-03-21
941	666	878	3	2025-07-11	2025-07-16
942	156	385	3	2025-01-08	2025-01-09
943	28	839	8	2026-10-23	2026-10-30
944	83	159	4	2025-03-03	2025-03-06
945	390	532	4	2026-01-28	2026-02-04
946	59	744	6	2026-02-05	2026-02-10
947	750	836	8	2026-10-03	2026-10-05
948	790	488	9	2025-09-26	2025-10-01
949	64	234	5	2025-03-25	2025-03-29
950	626	577	6	2025-12-02	2025-12-08
951	297	891	8	2025-04-30	2025-05-02
952	328	100	7	2025-04-29	2025-05-05
953	767	202	2	2026-05-13	2026-05-14
954	982	574	7	2026-06-24	2026-06-28
955	982	290	10	2025-09-22	2025-09-29
956	207	239	8	2025-01-30	2025-02-03
957	53	94	5	2026-04-29	2026-05-01
958	84	328	3	2025-04-14	2025-04-18
959	48	612	9	2025-04-28	2025-04-30
960	544	419	1	2025-07-28	2025-07-30
961	577	866	3	2026-05-15	2026-05-21
962	483	425	10	2025-01-12	2025-01-13
963	396	946	9	2025-01-10	2025-01-14
964	581	613	9	2026-03-08	2026-03-10
965	308	862	5	2026-01-23	2026-01-30
966	703	915	8	2026-01-08	2026-01-15
967	152	788	1	2025-02-18	2025-02-25
968	823	93	5	2025-11-20	2025-11-26
969	404	301	6	2025-08-14	2025-08-19
970	318	93	9	2026-06-30	2026-07-02
971	765	543	2	2025-11-23	2025-11-26
972	234	779	2	2025-10-06	2025-10-12
973	925	60	7	2025-07-08	2025-07-12
974	70	173	3	2025-07-16	2025-07-20
975	137	62	8	2026-07-11	2026-07-12
976	910	560	4	2025-09-19	2025-09-20
977	39	55	1	2026-06-29	2026-06-30
978	735	665	5	2026-12-14	2026-12-15
979	478	959	5	2025-09-17	2025-09-23
980	102	642	3	2025-03-23	2025-03-29
981	540	893	8	2025-09-12	2025-09-18
982	307	776	6	2025-05-11	2025-05-14
983	831	941	1	2025-07-17	2025-07-18
984	827	783	5	2026-08-13	2026-08-20
985	419	379	5	2025-06-15	2025-06-22
986	702	326	6	2026-04-27	2026-05-03
987	365	579	4	2026-02-07	2026-02-08
988	877	913	3	2026-09-29	2026-10-01
989	390	98	10	2026-04-04	2026-04-10
990	686	507	6	2025-06-28	2025-07-03
991	132	212	3	2025-01-19	2025-01-21
992	845	710	5	2025-08-09	2025-08-11
993	250	845	5	2025-04-13	2025-04-17
995	72	778	7	2025-07-29	2025-08-01
996	986	201	6	2025-10-04	2025-10-07
997	344	575	6	2025-09-29	2025-10-05
998	737	890	6	2025-02-07	2025-02-09
1000	14	663	3	2025-11-06	2025-11-08
31	452	17	4	2026-08-01	2026-08-08
83	287	46	2	2026-08-22	2026-08-25
15	613	57	2	2026-09-26	2026-10-03
87	613	57	10	2026-11-28	2026-12-03
92	918	33	6	2026-11-15	2026-11-22
134	690	71	3	2026-06-29	2026-07-03
176	706	98	6	2026-07-30	2026-08-03
182	843	92	9	2026-06-02	2026-06-03
195	526	122	7	2026-11-24	2026-11-29
235	809	38	2	2026-11-29	2026-12-06
240	370	49	4	2026-09-01	2026-09-07
319	979	73	3	2026-05-30	2026-06-05
903	979	73	9	2026-08-14	2026-08-16
336	593	81	8	2026-06-23	2026-06-26
374	589	139	1	2026-07-22	2026-07-24
383	522	120	9	2026-10-30	2026-11-04
389	153	151	1	2026-09-22	2026-09-26
399	206	13	6	2026-09-24	2026-09-27
474	257	52	10	2026-10-02	2026-10-08
515	991	180	8	2026-11-25	2026-11-26
597	644	164	1	2026-05-30	2026-06-03
606	745	199	3	2026-07-31	2026-08-01
620	349	67	7	2026-11-07	2026-11-10
632	479	197	5	2026-07-29	2026-08-03
52	340	91	9	2026-06-12	2026-06-15
196	340	91	9	2026-08-20	2026-08-21
649	340	91	2	2026-08-18	2026-08-23
994	340	91	9	2026-06-16	2026-06-21
664	701	35	4	2026-12-18	2026-12-24
669	428	280	4	2026-06-24	2026-07-01
696	267	78	7	2026-10-27	2026-10-30
602	954	43	7	2026-08-11	2026-08-12
700	954	43	4	2026-11-30	2026-12-05
748	746	173	4	2026-11-14	2026-11-21
288	303	148	2	2026-08-24	2026-08-25
751	303	148	7	2026-11-29	2026-12-06
765	467	167	7	2026-08-02	2026-08-03
799	135	206	1	2026-05-28	2026-05-31
807	244	68	7	2026-12-20	2026-12-27
809	469	260	1	2026-09-26	2026-10-01
2	839	221	2	2026-10-29	2026-11-01
871	839	221	6	2026-09-20	2026-09-24
421	948	303	8	2026-10-03	2026-10-07
874	948	303	7	2026-06-04	2026-06-10
889	779	340	3	2026-12-18	2026-12-22
999	145	74	1	2026-12-23	2026-12-25
1001	9	331	3	2026-05-13	2026-05-14
1002	11	331	8	2026-03-23	2026-03-26
1003	13	331	8	2026-05-25	2026-05-28
1004	17	331	3	2026-05-25	2026-05-28
1005	20	331	9	2026-05-25	2026-05-28
1006	24	331	2	2025-02-18	2025-02-22
1007	25	331	2	2026-01-19	2026-01-22
1008	27	331	3	2026-03-14	2026-03-25
1009	29	331	1	2026-05-25	2026-05-28
1010	30	331	6	2025-02-09	2025-02-12
1011	33	331	9	2026-05-25	2026-05-28
1012	34	331	6	2026-04-30	2026-05-13
1013	37	331	2	2026-05-25	2026-05-28
1014	38	331	2	2025-03-17	2025-03-25
1015	42	331	5	2026-05-25	2026-05-28
1016	43	331	10	2025-11-06	2025-11-08
1017	46	331	5	2026-05-25	2026-05-28
1018	47	331	3	2025-03-31	2025-04-10
1019	50	331	2	2026-05-25	2026-05-28
1020	52	331	3	2026-05-25	2026-05-28
1021	54	331	6	2026-05-25	2026-05-28
1022	56	331	9	2026-05-25	2026-05-28
1023	57	331	2	2026-05-25	2026-05-28
1024	58	331	9	2026-05-25	2026-05-28
1025	65	331	7	2025-08-06	2025-08-21
1026	67	331	8	2026-05-25	2026-05-28
1027	68	331	4	2026-05-25	2026-05-28
1028	69	331	10	2026-05-25	2026-05-28
1029	74	331	4	2026-05-25	2026-05-28
1030	75	331	4	2025-01-29	2025-02-09
1031	77	331	10	2026-05-25	2026-05-28
1032	79	331	4	2026-05-25	2026-05-28
1033	82	331	10	2026-05-25	2026-05-28
1034	86	331	4	2026-05-25	2026-05-28
1035	87	331	4	2026-05-25	2026-05-28
1036	90	331	4	2026-05-25	2026-05-28
1037	92	331	4	2026-04-03	2026-04-05
1038	95	331	8	2026-05-25	2026-05-28
1039	98	331	10	2026-05-25	2026-05-28
1040	99	331	5	2026-03-16	2026-03-31
1041	104	331	4	2026-05-25	2026-05-28
1042	105	331	9	2026-05-25	2026-05-28
1043	107	331	4	2026-05-25	2026-05-28
1044	109	331	9	2026-05-25	2026-05-28
1045	112	331	5	2026-05-25	2026-05-28
1046	113	331	1	2026-05-25	2026-05-28
1047	115	331	5	2026-05-25	2026-05-28
1048	118	331	6	2025-03-14	2025-03-15
1049	120	331	3	2025-10-03	2025-10-12
1050	125	331	4	2026-05-25	2026-05-28
1051	126	331	1	2025-04-01	2025-04-14
1052	129	331	9	2025-07-06	2025-07-14
1053	131	331	6	2026-05-25	2026-05-28
1054	133	331	5	2026-05-25	2026-05-28
1055	136	331	8	2026-05-25	2026-05-28
1056	138	331	9	2026-05-25	2026-05-28
1057	142	331	10	2026-05-25	2026-05-28
1058	144	331	3	2026-05-25	2026-05-28
1059	146	331	6	2026-05-25	2026-05-28
1060	157	331	9	2026-05-25	2026-05-28
1061	159	331	6	2026-05-25	2026-05-28
1062	163	331	8	2026-03-22	2026-04-03
1063	164	331	2	2025-10-28	2025-11-05
1064	165	331	3	2026-05-25	2026-05-28
1065	171	331	1	2026-05-25	2026-05-28
1066	172	331	10	2026-05-25	2026-05-28
1067	173	331	4	2026-05-25	2026-05-28
1068	175	331	6	2026-05-25	2026-05-28
1069	177	331	6	2026-05-25	2026-05-28
1070	184	331	4	2026-05-25	2026-05-28
1071	185	331	7	2026-05-25	2026-05-28
1072	187	331	6	2026-05-25	2026-05-28
1073	188	331	1	2026-05-25	2026-05-28
1074	192	331	6	2026-05-25	2026-05-28
1075	193	331	9	2026-05-25	2026-05-28
1076	194	331	7	2026-05-25	2026-05-28
1077	195	331	3	2026-05-25	2026-05-28
1078	196	331	9	2026-03-03	2026-03-17
1079	199	331	3	2026-05-25	2026-05-28
1080	202	331	4	2026-05-25	2026-05-28
1081	204	331	7	2026-05-25	2026-05-28
1082	205	331	6	2026-05-25	2026-05-28
1083	208	331	3	2026-05-25	2026-05-28
1084	210	331	7	2026-05-25	2026-05-28
1085	213	331	5	2026-05-25	2026-05-28
1086	216	331	9	2026-05-25	2026-05-28
1087	218	331	7	2026-05-25	2026-05-28
1088	222	331	9	2026-05-25	2026-05-28
1089	223	331	7	2026-01-18	2026-01-22
1090	225	331	8	2026-05-25	2026-05-28
1091	227	331	10	2025-05-18	2025-06-02
1092	229	331	5	2026-05-25	2026-05-28
1093	236	331	1	2026-05-25	2026-05-28
1094	238	331	7	2026-05-25	2026-05-28
1095	240	331	6	2026-05-25	2026-05-28
1096	241	331	7	2026-05-25	2026-05-28
1097	245	331	8	2026-05-25	2026-05-28
1098	246	331	3	2026-03-24	2026-03-30
1099	249	331	7	2026-05-25	2026-05-28
1100	251	331	6	2025-01-04	2025-01-12
1101	252	331	3	2026-05-25	2026-05-28
1102	258	331	7	2026-05-25	2026-05-28
1103	259	331	10	2026-05-05	2026-05-17
1104	263	331	8	2025-08-20	2025-09-03
1105	265	331	6	2026-05-25	2026-05-28
1106	268	331	10	2026-03-22	2026-04-03
1107	274	331	3	2026-05-25	2026-05-28
1108	275	331	7	2026-05-25	2026-05-28
1109	282	331	4	2026-05-25	2026-05-28
1110	285	331	6	2025-06-29	2025-07-11
1111	291	331	6	2026-05-25	2026-05-28
1112	292	331	7	2026-05-25	2026-05-28
1113	293	331	5	2025-12-27	2025-12-30
1114	295	331	8	2025-01-24	2025-02-01
1115	296	331	2	2026-05-25	2026-05-28
1116	298	331	3	2026-05-25	2026-05-28
1117	299	331	2	2026-05-25	2026-05-28
1118	301	331	9	2026-05-25	2026-05-28
1119	302	331	5	2026-05-25	2026-05-28
1120	306	331	9	2026-05-25	2026-05-28
1121	309	331	6	2025-04-19	2025-05-03
1122	311	331	10	2026-05-25	2026-05-28
1123	312	331	3	2026-05-25	2026-05-28
1124	313	331	9	2026-05-25	2026-05-28
1125	314	331	6	2026-05-25	2026-05-28
1126	315	331	1	2026-05-25	2026-05-28
1127	316	331	4	2026-05-25	2026-05-28
1128	320	331	7	2026-05-25	2026-05-28
1129	325	331	1	2026-05-25	2026-05-28
1130	326	331	6	2025-08-12	2025-08-15
1131	329	331	10	2026-05-25	2026-05-28
1132	330	331	8	2025-09-21	2025-10-02
1133	331	331	4	2026-05-25	2026-05-28
1134	332	331	2	2025-05-18	2025-05-21
1135	334	331	9	2025-03-21	2025-03-25
1136	335	331	3	2026-05-25	2026-05-28
1137	337	331	5	2026-05-25	2026-05-28
1138	338	331	1	2026-05-25	2026-05-28
1139	346	331	6	2026-05-25	2026-05-28
1140	347	331	1	2026-05-25	2026-05-28
1141	353	331	7	2026-05-25	2026-05-28
1142	355	331	4	2026-05-25	2026-05-28
1143	356	331	4	2026-05-25	2026-05-28
1144	358	331	10	2026-05-25	2026-05-28
1145	359	331	3	2026-05-25	2026-05-28
1146	360	331	2	2026-05-25	2026-05-28
1147	362	331	8	2026-05-25	2026-05-28
1148	364	331	6	2026-05-25	2026-05-28
1149	369	331	6	2026-05-25	2026-05-28
1150	371	331	9	2026-05-25	2026-05-28
1151	372	331	8	2026-05-25	2026-05-28
1152	373	331	2	2026-05-25	2026-05-28
1153	374	331	1	2025-07-30	2025-08-12
1154	375	331	6	2026-03-09	2026-03-22
1155	378	331	9	2026-05-25	2026-05-28
1156	380	331	6	2025-11-25	2025-12-04
1157	381	331	3	2026-05-25	2026-05-28
1158	382	331	8	2026-05-25	2026-05-28
1159	386	331	1	2026-05-25	2026-05-28
1160	387	331	9	2026-03-07	2026-03-16
1161	388	331	10	2026-05-25	2026-05-28
1162	391	331	4	2025-09-15	2025-09-23
1163	394	331	2	2026-05-25	2026-05-28
1164	401	331	8	2026-05-25	2026-05-28
1165	408	331	7	2026-05-25	2026-05-28
1166	411	331	9	2026-05-25	2026-05-28
1167	413	331	2	2026-05-25	2026-05-28
1168	414	331	3	2026-05-25	2026-05-28
1169	417	331	9	2026-05-25	2026-05-28
1170	418	331	10	2026-05-25	2026-05-28
1171	423	331	5	2026-05-25	2026-05-28
1172	424	331	4	2026-05-25	2026-05-28
1173	427	331	5	2026-05-25	2026-05-28
1174	432	331	4	2026-05-25	2026-05-28
1175	433	331	8	2026-05-25	2026-05-28
1176	434	331	10	2026-04-10	2026-04-21
1177	437	331	9	2026-05-25	2026-05-28
1178	439	331	6	2026-05-25	2026-05-28
1179	443	331	5	2025-03-29	2025-04-01
1180	444	331	6	2026-05-25	2026-05-28
1181	448	331	9	2026-05-25	2026-05-28
1182	453	331	9	2026-05-25	2026-05-28
1183	455	331	9	2026-05-25	2026-05-28
1184	456	331	10	2026-05-25	2026-05-28
1185	461	331	1	2026-05-25	2026-05-28
1186	463	331	7	2026-05-25	2026-05-28
1187	464	331	6	2026-05-25	2026-05-28
1188	476	331	7	2026-05-25	2026-05-28
1189	485	331	6	2025-06-11	2025-06-16
1190	486	331	5	2026-05-25	2026-05-28
1191	487	331	3	2026-05-25	2026-05-28
1192	492	331	6	2026-05-25	2026-05-28
1193	493	331	3	2026-05-25	2026-05-28
1194	494	331	1	2026-05-25	2026-05-28
1195	496	331	8	2026-05-25	2026-05-28
1196	498	331	5	2026-05-25	2026-05-28
1197	501	331	2	2026-05-25	2026-05-28
1198	504	331	8	2026-05-25	2026-05-28
1199	505	331	9	2026-05-25	2026-05-28
1200	514	331	7	2026-05-25	2026-05-28
1201	515	331	2	2026-05-25	2026-05-28
1202	516	331	4	2025-05-08	2025-05-20
1203	521	331	5	2026-05-25	2026-05-28
1204	523	331	10	2025-01-28	2025-01-31
1205	527	331	10	2026-05-25	2026-05-28
1206	528	331	1	2026-05-25	2026-05-28
1207	530	331	9	2026-05-25	2026-05-28
1208	531	331	5	2026-05-25	2026-05-28
1209	543	331	3	2026-05-25	2026-05-28
1210	546	331	5	2026-02-22	2026-03-04
1211	548	331	8	2026-05-25	2026-05-28
1212	549	331	9	2026-05-25	2026-05-28
1213	551	331	6	2026-05-25	2026-05-28
1214	552	331	8	2026-05-25	2026-05-28
1215	554	331	4	2026-05-25	2026-05-28
1216	556	331	8	2026-05-25	2026-05-28
1217	559	331	6	2026-05-25	2026-05-28
1218	564	331	6	2026-05-25	2026-05-28
1219	568	331	9	2026-05-25	2026-05-28
1220	569	331	6	2026-05-25	2026-05-28
1221	570	331	5	2026-05-25	2026-05-28
1222	572	331	8	2026-05-25	2026-05-28
1223	575	331	8	2026-05-25	2026-05-28
1224	578	331	7	2026-05-25	2026-05-28
1225	582	331	9	2026-05-25	2026-05-28
1226	585	331	3	2026-05-25	2026-05-28
1227	587	331	9	2026-03-29	2026-04-02
1228	590	331	7	2026-05-25	2026-05-28
1229	591	331	5	2026-05-25	2026-05-28
1230	592	331	10	2026-05-25	2026-05-28
1231	595	331	2	2026-05-25	2026-05-28
1232	596	331	3	2026-05-25	2026-05-28
1233	601	331	8	2026-05-25	2026-05-28
1234	603	331	7	2025-06-15	2025-06-16
1235	604	331	8	2026-05-25	2026-05-28
1236	605	331	7	2026-05-25	2026-05-28
1237	607	331	3	2026-05-25	2026-05-28
1238	608	331	1	2026-05-25	2026-05-28
1239	609	331	6	2026-05-25	2026-05-28
1240	610	331	5	2026-05-25	2026-05-28
1241	614	331	9	2026-05-25	2026-05-28
1242	615	331	9	2026-05-25	2026-05-28
1243	617	331	7	2026-05-25	2026-05-28
1244	620	331	6	2026-05-25	2026-05-28
1245	623	331	7	2026-05-25	2026-05-28
1246	624	331	4	2026-05-25	2026-05-28
1247	625	331	5	2026-05-25	2026-05-28
1248	631	331	6	2026-05-25	2026-05-28
1249	632	331	5	2026-05-25	2026-05-28
1250	633	331	3	2026-05-25	2026-05-28
1251	634	331	6	2025-09-11	2025-09-16
1252	635	331	2	2026-05-25	2026-05-28
1253	639	331	7	2026-05-25	2026-05-28
1254	645	331	5	2025-08-06	2025-08-09
1255	649	331	10	2026-05-25	2026-05-28
1256	654	331	5	2026-05-25	2026-05-28
1257	659	331	1	2026-05-25	2026-05-28
1258	660	331	10	2026-05-25	2026-05-28
1259	661	331	2	2026-05-25	2026-05-28
1260	663	331	4	2026-05-25	2026-05-28
1261	664	331	10	2026-05-25	2026-05-28
1262	670	331	7	2026-05-25	2026-05-28
1263	672	331	5	2026-05-25	2026-05-28
1264	673	331	2	2026-05-25	2026-05-28
1265	674	331	10	2026-05-25	2026-05-28
1266	676	331	8	2026-03-16	2026-03-28
1267	677	331	1	2025-04-23	2025-05-06
1268	678	331	6	2025-03-19	2025-03-26
1269	679	331	7	2026-05-25	2026-05-28
1270	683	331	9	2026-05-25	2026-05-28
1271	685	331	7	2026-05-25	2026-05-28
1272	687	331	4	2026-05-25	2026-05-28
1273	694	331	10	2026-01-28	2026-02-01
1274	698	331	7	2026-05-25	2026-05-28
1275	710	331	2	2026-05-25	2026-05-28
1276	712	331	7	2025-03-03	2025-03-12
1277	717	331	9	2026-05-25	2026-05-28
1278	718	331	8	2026-05-25	2026-05-28
1279	720	331	5	2026-05-25	2026-05-28
1280	722	331	7	2026-05-25	2026-05-28
1281	723	331	8	2025-06-07	2025-06-10
1282	726	331	4	2026-05-25	2026-05-28
1283	730	331	7	2026-05-25	2026-05-28
1284	731	331	3	2026-05-21	2026-05-29
1285	733	331	10	2026-05-25	2026-05-28
1286	738	331	10	2026-05-25	2026-05-28
1287	742	331	6	2025-04-29	2025-05-09
1288	747	331	3	2025-09-02	2025-09-10
1289	748	331	7	2026-05-25	2026-05-28
1290	749	331	7	2026-05-25	2026-05-28
1291	751	331	2	2025-10-13	2025-10-19
1292	753	331	6	2026-05-25	2026-05-28
1293	756	331	3	2026-05-25	2026-05-28
1294	758	331	4	2026-05-25	2026-05-28
1295	761	331	10	2026-05-25	2026-05-28
1296	766	331	1	2026-05-25	2026-05-28
1297	769	331	8	2026-05-25	2026-05-28
1298	770	331	2	2026-05-25	2026-05-28
1299	771	331	7	2026-05-25	2026-05-28
1300	772	331	9	2026-05-25	2026-05-28
1301	777	331	9	2026-05-25	2026-05-28
1302	778	331	3	2026-05-25	2026-05-28
1303	781	331	1	2026-05-25	2026-05-28
1304	782	331	7	2026-05-25	2026-05-28
1305	787	331	2	2026-05-25	2026-05-28
1306	789	331	2	2026-01-30	2026-02-10
1307	792	331	4	2026-05-25	2026-05-28
1308	797	331	3	2026-05-25	2026-05-28
1309	804	331	5	2026-05-25	2026-05-28
1310	806	331	1	2026-05-25	2026-05-28
1311	808	331	5	2026-05-25	2026-05-28
1312	812	331	9	2026-05-25	2026-05-28
1313	813	331	4	2026-05-25	2026-05-28
1314	818	331	8	2026-05-25	2026-05-28
1315	824	331	10	2025-02-11	2025-02-22
1316	826	331	7	2026-05-25	2026-05-28
1317	830	331	9	2026-05-25	2026-05-28
1318	833	331	6	2026-05-25	2026-05-28
1319	834	331	7	2025-05-12	2025-05-16
1320	835	331	4	2026-05-25	2026-05-28
1321	836	331	9	2026-05-25	2026-05-28
1322	840	331	4	2026-05-25	2026-05-28
1323	844	331	2	2026-05-25	2026-05-28
1324	847	331	10	2026-05-25	2026-05-28
1325	850	331	9	2026-04-05	2026-04-09
1326	857	331	7	2026-05-25	2026-05-28
1327	860	331	5	2026-05-25	2026-05-28
1328	864	331	1	2026-05-25	2026-05-28
1329	866	331	8	2026-05-25	2026-05-28
1330	868	331	7	2026-05-25	2026-05-28
1331	869	331	6	2026-05-25	2026-05-28
1332	871	331	7	2026-05-25	2026-05-28
1333	873	331	4	2025-04-18	2025-04-26
1334	874	331	7	2026-05-25	2026-05-28
1335	875	331	7	2026-05-25	2026-05-28
1336	878	331	9	2026-05-25	2026-05-28
1337	879	331	7	2026-05-25	2026-05-28
1338	880	331	6	2026-05-25	2026-05-28
1339	886	331	9	2026-05-25	2026-05-28
1340	888	331	1	2026-05-25	2026-05-28
1341	890	331	8	2025-10-29	2025-11-03
1342	893	331	4	2026-05-25	2026-05-28
1343	894	331	7	2026-05-25	2026-05-28
1344	897	331	7	2026-05-25	2026-05-28
1345	899	331	9	2026-02-11	2026-02-18
1346	900	331	8	2025-06-09	2025-06-14
1347	902	331	6	2026-05-25	2026-05-28
1348	908	331	8	2026-05-25	2026-05-28
1349	911	331	8	2026-05-25	2026-05-28
1350	912	331	2	2025-04-21	2025-05-06
1351	913	331	9	2026-05-25	2026-05-28
1352	920	331	3	2026-05-25	2026-05-28
1353	923	331	4	2026-05-25	2026-05-28
1354	926	331	7	2025-07-13	2025-07-18
1355	928	331	1	2026-05-25	2026-05-28
1356	929	331	1	2026-05-25	2026-05-28
1357	932	331	5	2026-05-25	2026-05-28
1358	935	331	10	2026-05-25	2026-05-28
1359	938	331	4	2026-05-25	2026-05-28
1360	942	331	9	2026-05-25	2026-05-28
1361	944	331	10	2026-05-25	2026-05-28
1362	950	331	3	2026-05-25	2026-05-28
1363	956	331	9	2026-05-25	2026-05-28
1364	960	331	8	2025-04-14	2025-04-24
1365	961	331	4	2026-05-25	2026-05-28
1366	968	331	8	2026-05-25	2026-05-28
1367	969	331	2	2026-05-25	2026-05-28
1368	972	331	6	2026-05-25	2026-05-28
1369	973	331	1	2026-05-25	2026-05-28
1370	974	331	2	2026-05-25	2026-05-28
1371	975	331	4	2026-05-25	2026-05-28
1372	978	331	8	2025-09-30	2025-10-15
1373	980	331	4	2026-05-25	2026-05-28
1374	983	331	6	2026-05-25	2026-05-28
1375	984	331	6	2026-05-25	2026-05-28
1376	985	331	1	2025-12-10	2025-12-17
1377	988	331	5	2026-05-25	2026-05-28
1378	989	331	4	2026-01-23	2026-02-06
1379	990	331	5	2026-05-25	2026-05-28
1380	992	331	6	2025-04-11	2025-04-18
1381	993	331	4	2026-05-25	2026-05-28
1382	995	331	7	2025-01-23	2025-02-03
1383	997	331	1	2026-05-25	2026-05-28
1384	999	331	8	2026-05-25	2026-05-28
1385	1000	331	9	2026-05-25	2026-05-28
1386	1001	196	2	2025-10-24	2025-10-28
1387	1002	809	2	2025-04-16	2025-04-20
1388	1003	570	2	2025-02-27	2025-03-03
1389	1004	198	2	2025-03-07	2025-03-09
1390	1005	547	2	2025-05-28	2025-06-03
1391	1006	729	2	2025-05-24	2025-05-26
1392	1007	97	2	2025-09-05	2025-09-09
1393	1008	151	2	2025-05-14	2025-05-17
1394	1009	121	2	2025-10-20	2025-10-25
1395	1010	349	2	2025-08-09	2025-08-14
\.


--
-- TOC entry 5356 (class 0 OID 31152)
-- Dependencies: 236
-- Data for Name: empleado; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.empleado (id_empleado, id_tipo_empleado, nombre, correo, telefono, dui, salario) FROM stdin;
1	9	Wallache Reading	wreading0@mit.edu	+50365647572	02545831-6	503.42
2	6	Tatum Frayn	tfrayn1@storify.com	+50374851477	31296321-4	738.51
3	7	Chiquia Trebilcock	ctrebilcock2@freewebs.com	+50375515372	63633188-0	592.39
4	9	Aymer Sprott	asprott3@symantec.com	+50368780948	57489109-1	419.66
5	3	Wenda Mumby	wmumby4@businessweek.com	+50374762731	28147458-7	1108.05
6	7	Clemente Godfray	cgodfray5@examiner.com	+50360651905	32381364-0	854.42
7	10	Morton Tipens	mtipens6@wordpress.com	+50322413291	48897105-9	920.20
8	10	Ellerey Tancock	etancock7@amazonaws.com	+50362761491	97301379-8	410.47
9	9	Tadeo Cammocke	tcammocke8@mapy.cz	+50329605809	52780275-3	1277.52
10	1	Lon Lauderdale	llauderdale9@hhs.gov	+50324218987	16333662-4	1105.05
11	6	Mario Rasor	mrasora@twitpic.com	+50325672183	09523307-6	508.38
12	10	Shawn McDuffie	smcduffieb@cbsnews.com	+50324138094	43522964-1	437.23
13	3	Alphard Drury	adruryc@godaddy.com	+50370131513	36632606-5	1231.86
14	6	Tonye Musterd	tmusterdd@mediafire.com	+50324956959	65056394-1	675.88
15	10	Ulberto Creelman	ucreelmane@pcworld.com	+50377300291	76972455-3	545.78
16	4	Baxie Stittle	bstittlef@bloglines.com	+50366628060	80469740-1	1183.94
17	10	Barnebas Gossop	bgossopg@upenn.edu	+50377325865	14008593-1	596.63
18	3	Karel Cozby	kcozbyh@indiegogo.com	+50324461427	76453521-4	967.82
19	1	Suellen Arnow	sarnowi@yandex.ru	+50364711833	14251375-5	1395.06
20	2	Dulcie Argue	darguej@forbes.com	+50377737994	50417360-3	1278.05
21	3	Nelly Mannooch	nmannoochk@comsenz.com	+50374095234	12135110-7	558.04
22	1	Melisa McPhee	mmcpheel@cargocollective.com	+50371595782	82806062-6	687.36
23	3	Oralle Minney	ominneym@europa.eu	+50329620644	43869355-2	1024.21
24	1	Ida Folbige	ifolbigen@sogou.com	+50371346961	84494237-9	747.74
25	4	Des Bonass	dbonasso@imageshack.us	+50324784784	14151032-7	1045.33
26	3	Marissa Faye	mfayep@huffingtonpost.com	+50360651335	54098485-7	649.09
27	3	Tris Maciaszczyk	tmaciaszczykq@example.com	+50327877546	71262277-3	860.71
28	5	Gabbie Gue	gguer@phpbb.com	+50368294073	55934429-9	537.46
29	2	Killian Dael	kdaels@youtube.com	+50321274338	15453838-0	1009.64
30	3	Deny Farmar	dfarmart@va.gov	+50364104830	11245536-9	646.91
31	8	Adlai Linstead	alinsteadu@upenn.edu	+50379805776	68239717-8	385.03
32	5	Donni Capin	dcapinv@barnesandnoble.com	+50370553764	78322351-3	1361.36
33	8	Lockwood Bartolijn	lbartolijnw@youtu.be	+50368743716	49237797-2	596.01
34	4	Cesar Danielovitch	cdanielovitchx@time.com	+50324763490	45476026-4	1146.64
35	10	Vasily Brookwood	vbrookwoody@umich.edu	+50326786352	16379522-9	554.81
36	1	Modesty Wanell	mwanellz@google.nl	+50324219571	35523137-1	869.39
37	7	Julissa Planke	jplanke10@imageshack.us	+50370958691	21523521-5	948.29
38	5	Mandie Hartright	mhartright11@dagondesign.com	+50374375891	94111866-3	1440.44
39	10	Ardelis Van Salzberger	avan12@phpbb.com	+50374621161	72791719-6	923.80
40	3	Mattie De Cristofalo	mde13@cnn.com	+50323539295	70056708-8	677.52
41	2	Gideon Crummie	gcrummie14@rambler.ru	+50373494941	44775931-4	818.09
42	3	Atalanta Harry	aharry15@epa.gov	+50363795346	56434040-9	587.69
43	5	Crichton Kilpin	ckilpin16@rambler.ru	+50326052327	79656439-6	882.79
44	3	Hillel Gillyett	hgillyett17@time.com	+50378599948	27349368-2	1361.26
45	1	Jacobo McGarrity	jmcgarrity18@furl.net	+50377913161	42089459-1	949.05
46	2	Mitchel Sivil	msivil19@nifty.com	+50320898126	51683007-0	1025.84
47	6	Mikey Melbert	mmelbert1a@google.co.uk	+50328827350	85422300-3	703.01
48	1	Artemis Willoway	awilloway1b@eepurl.com	+50360353077	27570335-4	927.51
49	8	Cassandra Zealander	czealander1c@reuters.com	+50366371765	27058375-2	1071.49
50	9	Danice Maslen	dmaslen1d@dedecms.com	+50326244920	69303800-2	1018.88
51	1	Gayler Leeb	gleeb1e@sogou.com	+50364133816	70222918-9	1451.38
52	1	Nerti Beese	nbeese1f@pen.io	+50375319620	15650369-9	475.34
53	8	Byram Latty	blatty1g@businessinsider.com	+50329702353	62945267-9	1438.55
54	7	Freddie Latimer	flatimer1h@exblog.jp	+50325282582	14900378-1	1193.41
55	8	Ondrea Griffitt	ogriffitt1i@scribd.com	+50362219094	96913208-5	963.40
56	10	Rufe Leyban	rleyban1j@ucsd.edu	+50323878251	06903389-8	1219.86
57	2	Kirsteni Pecha	kpecha1k@yelp.com	+50375253928	94440331-0	628.39
58	4	Bren Dugall	bdugall1l@behance.net	+50325970879	48454781-3	1390.50
59	7	Jeramie Shirley	jshirley1m@artisteer.com	+50370349714	36568069-5	631.47
60	9	Shanan Tilley	stilley1n@wix.com	+50323651670	24596396-8	1384.64
61	3	Nari I'anson	nianson1o@pbs.org	+50374560949	63043673-2	868.64
62	6	Zulema Gammon	zgammon1p@archive.org	+50324988076	71773002-5	393.33
63	6	Valentin Golt	vgolt1q@netscape.com	+50373774452	06145571-9	661.26
64	5	Vachel McIlwrath	vmcilwrath1r@netvibes.com	+50366134816	63163927-6	1393.58
65	2	Theodor Balsdone	tbalsdone1s@bravesites.com	+50327876747	73776565-8	1050.78
66	2	Nicki De Carlo	nde1t@ucoz.ru	+50368307062	10083410-8	1353.81
67	4	Datha Keizman	dkeizman1u@webmd.com	+50376157195	16816392-9	1224.13
68	5	Sybille Saturley	ssaturley1v@webnode.com	+50374029997	93029079-4	530.73
69	2	Lexi Mullin	lmullin1w@printfriendly.com	+50370312758	61371328-3	494.18
70	6	Rip Blaney	rblaney1x@oaic.gov.au	+50376565981	75600198-8	1170.43
71	5	Hans Janczewski	hjanczewski1y@usa.gov	+50368713540	68690403-2	757.15
72	6	Carie Yole	cyole1z@stanford.edu	+50323689391	97810330-6	758.53
73	3	Gilbertina Duiguid	gduiguid20@dedecms.com	+50322281967	75927685-7	1068.50
74	10	Cathryn Laurenzi	claurenzi21@cbc.ca	+50322452577	06418240-7	665.80
75	1	Gwenny Pegden	gpegden22@bing.com	+50360759747	28061912-3	1068.83
76	1	Judd Conman	jconman23@paginegialle.it	+50366081613	20366496-0	1398.09
77	3	Roger Neighbour	rneighbour24@1688.com	+50368392213	20840009-5	496.40
78	10	Simone Brownsmith	sbrownsmith25@who.int	+50373750689	43758580-0	631.95
79	10	Constancy Waylen	cwaylen26@constantcontact.com	+50326772901	12469153-5	1375.40
80	6	Bronnie Foulkes	bfoulkes27@ezinearticles.com	+50328162231	94748629-2	1083.18
81	5	Nevile Roots	nroots28@nsw.gov.au	+50361846051	36468031-8	525.32
82	6	Nels Sieb	nsieb29@issuu.com	+50363919392	51439832-7	649.37
83	1	Kriste Samudio	ksamudio2a@google.co.uk	+50361156789	12260890-6	619.73
84	2	Aluino Stickler	astickler2b@globo.com	+50369102362	54306682-8	878.75
85	4	Madel Tower	mtower2c@bbb.org	+50375415748	58646635-1	824.24
86	10	Zebulen Varnes	zvarnes2d@homestead.com	+50325074869	69410397-3	778.51
87	9	Dotty Diggins	ddiggins2e@bloglines.com	+50360584012	52988977-6	1379.26
88	10	Alexina Taplow	ataplow2f@army.mil	+50328267748	15852126-0	411.67
89	3	Orbadiah Adnett	oadnett2g@delicious.com	+50375166742	44012689-5	573.76
90	2	Anabel Voysey	avoysey2h@tripod.com	+50369900769	48855700-7	1204.95
91	8	Lindsay Palluschek	lpalluschek2i@sogou.com	+50367871677	93610093-2	1330.78
92	4	Verney Maccaddie	vmaccaddie2j@yahoo.com	+50366791290	65239233-5	693.77
93	8	Sancho Infante	sinfante2k@telegraph.co.uk	+50324361769	92364154-5	1476.16
94	3	Lenci Aslie	laslie2l@china.com.cn	+50374472094	20545987-7	491.28
95	2	Sarene Bocken	sbocken2m@nasa.gov	+50321700498	77101394-5	1402.63
96	3	Norbert Ianelli	nianelli2n@mtv.com	+50325722454	74788619-2	693.66
97	9	Augustina Muckle	amuckle2o@npr.org	+50328038718	11609510-3	1093.97
98	6	Emanuel Bricham	ebricham2p@tripadvisor.com	+50320601412	65599538-1	921.28
99	3	Eachelle Seel	eseel2q@reverbnation.com	+50323643137	10363303-8	1397.39
100	1	Clementia Judgkins	cjudgkins2r@omniture.com	+50376558821	95661027-5	1008.29
101	4	Terrence Cornwell	tcornwell2s@bbc.co.uk	+50379089192	52798132-4	693.57
102	5	Mellisent Windrass	mwindrass2t@webmd.com	+50327991264	82117029-3	456.98
103	10	Madelina Arrault	marrault2u@latimes.com	+50371168062	69523843-3	467.52
104	4	Kellsie Uglow	kuglow2v@constantcontact.com	+50361749311	60916718-6	826.43
105	5	Arlette De Cruz	ade2w@wisc.edu	+50361094764	37784685-1	1150.92
106	1	Tiffy Rainsbury	trainsbury2x@dyndns.org	+50367360473	93837829-8	497.57
107	10	Wally Dalling	wdalling2y@sphinn.com	+50379755282	57371888-7	1139.83
108	4	Gwenneth Lovell	glovell2z@bigcartel.com	+50361983345	63137724-2	763.13
109	8	Michaela Domengue	mdomengue30@japanpost.jp	+50370637975	36926748-4	1136.61
110	10	Florian Menichi	fmenichi31@nih.gov	+50373772362	59375356-0	742.92
111	3	Jessika Davidofski	jdavidofski32@google.cn	+50329458517	62425861-4	1188.38
112	9	Carry Kilduff	ckilduff33@guardian.co.uk	+50376207694	12268638-7	1101.92
113	9	Roosevelt Antonacci	rantonacci34@bravesites.com	+50377858066	70238138-5	828.32
114	2	Yasmin Kyle	ykyle35@un.org	+50327940053	13038116-1	695.26
115	10	Sebastien Suttie	ssuttie36@seattletimes.com	+50320729646	01865600-3	791.76
116	10	Christi Surgood	csurgood37@themeforest.net	+50364925497	09470914-8	653.78
117	5	Nissa Jelkes	njelkes38@51.la	+50321402504	86656923-5	622.14
118	3	Hedwiga Clemendet	hclemendet39@unc.edu	+50379311737	29984833-2	492.16
119	1	Belicia Feast	bfeast3a@vimeo.com	+50375478255	84708147-8	1124.87
120	4	Burnaby Treace	btreace3b@list-manage.com	+50327251246	99415496-1	651.77
121	4	Clayton Konke	ckonke3c@princeton.edu	+50375919316	86191271-9	1243.33
122	9	Berti Jevon	bjevon3d@youtube.com	+50327097811	41749918-6	1074.85
123	10	Megan Shipsey	mshipsey3e@theguardian.com	+50372533662	97462126-5	963.73
124	9	Fields Vallentin	fvallentin3f@alexa.com	+50375835829	91519641-7	1310.08
125	1	Johny Cosby	jcosby3g@topsy.com	+50378552202	37338526-9	434.71
126	1	Caprice Dodson	cdodson3h@java.com	+50364034080	54190726-7	562.09
127	4	Peg Capp	pcapp3i@google.com.br	+50367443639	74133089-0	534.29
128	9	Lidia Egdale	legdale3j@skype.com	+50327817736	09259961-9	520.68
129	3	Jaquenetta Leckie	jleckie3k@wikispaces.com	+50321635491	56881596-9	756.84
130	2	Cati Darlington	cdarlington3l@fotki.com	+50369271127	72851311-9	1173.30
131	6	Kaylil Tern	ktern3m@furl.net	+50369608047	01169947-2	923.47
132	4	Berri Piris	bpiris3n@technorati.com	+50379449998	30458493-9	960.72
133	6	Rozele Ledwidge	rledwidge3o@wikispaces.com	+50376165960	14781366-6	952.75
134	9	Marcelline Pifford	mpifford3p@cisco.com	+50373002881	33398977-3	955.36
135	10	Glennis Steptowe	gsteptowe3q@theglobeandmail.com	+50329976141	89713841-7	610.99
136	4	Jena Peirone	jpeirone3r@dagondesign.com	+50369479806	58919249-7	918.20
137	9	Brianna Swede	bswede3s@mail.ru	+50371633263	61321459-1	1387.21
138	6	Melodie D'Ruel	mdruel3t@virginia.edu	+50370280871	29478978-0	1203.99
139	1	Constantine Silveston	csilveston3u@zdnet.com	+50363809115	18657999-3	1404.08
140	3	Vivyanne Petrescu	vpetrescu3v@goo.gl	+50375100814	90288311-6	1059.16
141	4	Sheridan Dows	sdows3w@nifty.com	+50328405054	33513213-4	1097.38
142	4	Delilah Churchyard	dchurchyard3x@businesswire.com	+50367278311	79513118-3	640.71
143	9	Antoinette Couvert	acouvert3y@intel.com	+50325215883	53694615-8	1348.99
144	3	Henrie Dyos	hdyos3z@1688.com	+50377134824	83293674-3	561.49
145	3	Ingeberg Klink	iklink40@google.co.jp	+50320161848	29065270-0	525.15
146	1	Myrtle Armfirld	marmfirld41@joomla.org	+50374738725	51797887-3	617.44
147	5	Edd Peat	epeat42@aol.com	+50364750078	59339031-8	1246.42
148	10	Nichole Searchwell	nsearchwell43@blinklist.com	+50376114145	99708668-7	1431.66
149	7	Lilllie Hugill	lhugill44@flavors.me	+50366397962	67370893-0	512.16
150	8	Stacey Topper	stopper45@microsoft.com	+50374442147	27284733-3	1450.07
151	8	Saba Harsnipe	sharsnipe46@liveinternet.ru	+50365545204	75405971-3	695.55
152	7	Hyacinthie Carleman	hcarleman47@edublogs.org	+50375628623	38035769-2	1039.45
153	6	Emma Pym	epym48@bandcamp.com	+50375688035	93048093-8	512.53
154	6	Bert Roper	broper49@bbc.co.uk	+50374754991	23354278-2	838.14
155	8	Baxy Masham	bmasham4a@bing.com	+50360333942	75378628-7	1028.00
156	8	Peggy Fance	pfance4b@linkedin.com	+50363316150	83043118-3	444.32
157	4	Danit Woofenden	dwoofenden4c@tamu.edu	+50369799044	76548742-1	1352.84
158	9	Clay Guinness	cguinness4d@amazon.com	+50361491676	22602963-7	1477.82
159	7	Carree Sporner	csporner4e@uiuc.edu	+50360093222	05554432-9	679.05
160	10	Luke Fryer	lfryer4f@hibu.com	+50376604854	72486148-0	1477.13
161	5	Rhoda Sammons	rsammons4g@prweb.com	+50363532666	44584852-0	1095.06
162	1	Minna Mackinder	mmackinder4h@oakley.com	+50363576971	40919155-9	794.54
163	1	Madeline Stiffell	mstiffell4i@archive.org	+50366275806	29511701-2	996.91
164	4	Phylis Jobin	pjobin4j@dion.ne.jp	+50364315610	52282209-2	446.17
165	5	Page Simla	psimla4k@miitbeian.gov.cn	+50320089503	67595170-2	996.00
166	10	Sherrie Mussilli	smussilli4l@mit.edu	+50328987342	81097791-2	1108.02
167	9	Jimmie Missington	jmissington4m@blinklist.com	+50371469012	04806379-1	1008.31
168	10	Gwenette Manthroppe	gmanthroppe4n@abc.net.au	+50368034859	62012893-2	960.11
169	2	Quincy Lancett	qlancett4o@reuters.com	+50326759825	82146427-6	1185.07
170	8	Thea Farrow	tfarrow4p@parallels.com	+50367806559	36782088-0	405.75
171	7	Janel Relf	jrelf4q@dot.gov	+50377469248	91351250-0	1454.13
172	10	Darrick Ballach	dballach4r@goo.ne.jp	+50368412598	67822118-6	454.67
173	8	Toddy Cowthart	tcowthart4s@un.org	+50374703627	70310729-7	1020.50
174	7	Aili Hurkett	ahurkett4t@tripadvisor.com	+50320366036	85770667-1	1094.52
175	1	Sebastiano Rulf	srulf4u@sakura.ne.jp	+50377940726	78243461-3	479.04
176	6	Morie Fernanando	mfernanando4v@gizmodo.com	+50374928463	44626987-8	1092.68
177	9	Dianna Piel	dpiel4w@nhs.uk	+50376521545	14254968-3	1197.27
178	3	Gipsy Manolov	gmanolov4x@amazon.de	+50373631306	01999078-3	1042.88
179	10	Eduardo Sponer	esponer4y@artisteer.com	+50322124489	56919883-0	789.85
180	9	Frans Conklin	fconklin4z@abc.net.au	+50378493899	86319335-8	1227.87
181	5	Florida Rowling	frowling50@ycombinator.com	+50320149623	72618847-2	981.94
182	2	Ives Casford	icasford51@nydailynews.com	+50327739873	67923639-9	448.46
183	9	Erna Dabner	edabner52@intel.com	+50329146565	92109417-8	1014.21
184	4	Marcellus Cheyenne	mcheyenne53@google.co.uk	+50320524723	00572976-2	976.35
185	10	Saunders Rathbourne	srathbourne54@yahoo.co.jp	+50368782949	84415195-2	655.33
186	7	Nichole Ianson	nianson55@abc.net.au	+50323238459	01139377-3	1323.01
187	4	Christoper Filoniere	cfiloniere56@moonfruit.com	+50326792647	42742121-3	848.56
188	6	Bert Crumb	bcrumb57@usa.gov	+50329344687	04032320-3	1195.04
189	6	Gladi Hagart	ghagart58@chicagotribune.com	+50374271761	49642781-9	1314.47
190	1	Ruperta Woofinden	rwoofinden59@yahoo.com	+50328661039	14691713-8	1125.00
191	10	Kristel Somers	ksomers5a@mozilla.org	+50325431844	57111954-8	775.70
192	1	Mechelle Ligertwood	mligertwood5b@house.gov	+50322016784	30721940-8	753.37
193	6	Odilia Maffi	omaffi5c@yellowpages.com	+50374593496	39976244-4	945.96
194	5	Madison Burns	mburns5d@wired.com	+50377741409	92911695-5	1070.99
195	7	Marieann Calbreath	mcalbreath5e@indiatimes.com	+50322761362	63642041-1	1147.31
196	2	Lottie De Coursey	lde5f@xrea.com	+50377587542	29558654-8	560.20
197	2	Gasparo Tsar	gtsar5g@statcounter.com	+50320839635	18696438-8	443.83
198	3	Nikolos Sugarman	nsugarman5h@furl.net	+50377180350	21321891-6	675.14
199	3	Bert Plumb	bplumb5i@taobao.com	+50324400609	47405021-6	1030.44
200	1	Herc Olpin	holpin5j@squarespace.com	+50368426049	02232880-1	1155.19
201	6	Ashla Giriardelli	agiriardelli5k@newyorker.com	+50376251357	22072800-8	750.24
202	4	Goldie Burril	gburril5l@oracle.com	+50327947537	79454274-6	1383.78
203	4	Kristo Lilion	klilion5m@technorati.com	+50365267493	00465045-4	558.05
204	4	Faythe Turneaux	fturneaux5n@etsy.com	+50378318236	12952448-9	1239.09
205	9	Baudoin Strangman	bstrangman5o@columbia.edu	+50374491930	84437135-3	814.08
206	10	Jacquelyn Jeffress	jjeffress5p@google.co.uk	+50365921257	52330130-5	584.38
207	1	Stearne Padillo	spadillo5q@chronoengine.com	+50325397053	29140374-7	704.14
208	3	Colene Jordi	cjordi5r@slate.com	+50327437239	09347948-1	786.11
209	4	Shandra Sorrell	ssorrell5s@paginegialle.it	+50322538526	66932301-1	1036.95
210	10	Nessie Shitliff	nshitliff5t@lulu.com	+50377340517	05360775-2	437.26
211	8	Sampson Shrubb	sshrubb5u@about.com	+50361784061	44338044-3	1112.77
212	9	Blanch Alexsandrev	balexsandrev5v@alexa.com	+50375983247	44551869-1	1119.36
213	9	Darius Rosier	drosier5w@discovery.com	+50361685581	34251383-4	470.74
214	9	Giselbert Kirkland	gkirkland5x@auda.org.au	+50323507749	20796204-3	1139.91
215	8	Konstantin Hunday	khunday5y@elpais.com	+50322162513	32338224-2	1342.93
216	6	Christye MacCallam	cmaccallam5z@admin.ch	+50373614770	98818079-2	582.80
217	8	Indira Pasmore	ipasmore60@businesswire.com	+50371138758	52500976-6	911.61
218	5	Byran Aucott	baucott61@rakuten.co.jp	+50369139830	19777689-7	388.28
219	6	Mikkel Scrace	mscrace62@bluehost.com	+50377525068	87936917-7	983.27
220	7	Crissy Stirley	cstirley63@a8.net	+50376601118	88128678-1	1241.30
221	3	Nert Smallshaw	nsmallshaw64@tuttocitta.it	+50327634791	52518655-5	768.95
222	3	Hartwell Gowlett	hgowlett65@gmpg.org	+50366668617	74129873-5	1047.24
223	4	Kirby Wudeland	kwudeland66@google.co.jp	+50326688615	96235002-3	743.55
224	2	Tremain Solland	tsolland67@springer.com	+50377798394	16194641-0	737.26
225	9	Valdemar Treversh	vtreversh68@google.ru	+50366268515	85794071-8	648.24
226	9	Edwin Mattschas	emattschas69@mit.edu	+50325827793	05707686-6	824.22
227	3	Angelique Hemstead	ahemstead6a@soup.io	+50376512823	45331572-5	1400.42
228	4	Lita Seery	lseery6b@wikimedia.org	+50373133923	37255863-5	1189.40
229	6	Dela McQuillen	dmcquillen6c@trellian.com	+50366931651	47241248-0	644.66
230	3	Kitty Olenchenko	kolenchenko6d@mashable.com	+50372826758	10010120-1	481.09
231	6	Carmelle Steel	csteel6e@linkedin.com	+50375505396	28810053-3	1179.99
232	8	Ros Purcell	rpurcell6f@tinypic.com	+50366107987	32675698-3	1109.61
233	8	Lois Cuer	lcuer6g@cdbaby.com	+50363101456	58258085-6	644.72
234	3	Reed Shadwick	rshadwick6h@constantcontact.com	+50373917874	44791516-5	527.48
235	8	Gunner Benzie	gbenzie6i@samsung.com	+50372148825	36500849-7	614.07
236	8	Blanche Amer	bamer6j@webs.com	+50372624036	56614615-4	715.20
237	2	Georgette Ordelt	gordelt6k@flavors.me	+50326633603	79684489-5	634.04
238	7	Valli Levick	vlevick6l@theglobeandmail.com	+50375066321	23292139-7	821.63
239	4	Giordano Calvard	gcalvard6m@phpbb.com	+50371534412	17821811-4	740.93
240	8	Ikey Hasser	ihasser6n@yolasite.com	+50320338407	94004103-6	855.79
241	6	Riordan Enos	renos6o@discovery.com	+50369381690	69743576-4	651.36
242	10	Raffaello Whitney	rwhitney6p@cnn.com	+50374595422	52199677-3	1236.92
243	5	Harcourt Ahrendsen	hahrendsen6q@amazonaws.com	+50360066660	54018601-7	919.83
244	8	Chicky Calwell	ccalwell6r@instagram.com	+50375543519	73246740-2	1188.01
245	2	Jaimie Stammer	jstammer6s@wix.com	+50324667551	84644954-8	521.56
246	10	Adam Amoore	aamoore6t@geocities.com	+50362944303	47313634-0	561.34
247	4	Urbanus Burrow	uburrow6u@alibaba.com	+50360120179	87540757-2	1475.91
248	2	Lorette Iiannoni	liiannoni6v@businessweek.com	+50328690238	91717690-9	566.03
249	8	Patience Synnott	psynnott6w@mtv.com	+50365038907	68556663-8	1409.73
250	2	Celie Gomery	cgomery6x@theatlantic.com	+50379946597	08014350-9	1310.27
251	7	Mandel Kubas	mkubas6y@marketwatch.com	+50370799852	95796827-2	564.60
252	2	Irv Henrionot	ihenrionot6z@odnoklassniki.ru	+50324650951	24183153-5	1358.08
253	2	Murdoch Kirckman	mkirckman70@usatoday.com	+50361117308	15849552-1	1293.94
254	2	Sammy Bladder	sbladder71@sohu.com	+50379611038	50109319-3	1368.14
255	10	Cecily Montfort	cmontfort72@studiopress.com	+50326554215	52096376-0	1290.33
256	4	Stu Josskoviz	sjosskoviz73@kickstarter.com	+50377763037	20576825-7	1435.61
257	9	Wilie Snarr	wsnarr74@china.com.cn	+50323445888	21871693-8	383.74
258	9	Jaymee Todhunter	jtodhunter75@gov.uk	+50375187682	01912909-3	964.30
259	2	Bonita Rosewall	brosewall76@dion.ne.jp	+50326264104	33361452-3	994.11
260	8	Salli Grebbin	sgrebbin77@accuweather.com	+50373841482	22200702-5	488.47
261	2	Camile Corbert	ccorbert78@yandex.ru	+50364957324	59031640-6	1018.41
262	1	Melessa Marfe	mmarfe79@webnode.com	+50320815041	17481201-2	906.57
263	1	Ulises Tapenden	utapenden7a@trellian.com	+50376088224	29720796-7	1277.90
264	4	Wenona Cowherd	wcowherd7b@tinypic.com	+50324645612	09539275-4	1479.03
265	5	Alejandra Iacovazzi	aiacovazzi7c@slideshare.net	+50328229297	44028327-9	791.18
266	6	Sheff Bolliver	sbolliver7d@yandex.ru	+50324113549	54717192-0	539.51
267	10	Cayla Simpkin	csimpkin7e@people.com.cn	+50373140441	82303680-5	769.17
268	2	Freddi Leason	fleason7f@slideshare.net	+50366727242	53559845-7	1439.48
269	10	Phedra Jedrych	pjedrych7g@dion.ne.jp	+50328080131	79788818-1	377.35
270	5	Haven Blaydes	hblaydes7h@w3.org	+50327473628	07162608-9	859.44
271	10	Truda Sessions	tsessions7i@tmall.com	+50360596502	57918685-3	1296.82
272	9	Patten Godspeede	pgodspeede7j@com.com	+50368697652	13608141-9	505.63
273	8	Astrid Stothard	astothard7k@boston.com	+50372717143	60070154-0	1232.51
274	6	Jinny Matyushkin	jmatyushkin7l@soup.io	+50372022074	45929061-8	919.66
275	1	Conrado Pantecost	cpantecost7m@so-net.ne.jp	+50374617398	87910329-5	366.93
276	1	Dollie Baszkiewicz	dbaszkiewicz7n@networkadvertising.org	+50361916624	05181373-3	1132.42
277	5	Arlena Sammars	asammars7o@cbslocal.com	+50374329077	90523648-5	863.81
278	5	Deloria Clarae	dclarae7p@nhs.uk	+50322836235	28657886-4	1420.15
279	1	Darryl Rowen	drowen7q@webeden.co.uk	+50364486989	80551775-2	1350.07
280	7	Conny Ivanov	civanov7r@ebay.co.uk	+50365782716	05528073-5	442.20
281	3	Myrna Paoletti	mpaoletti7s@com.com	+50327776837	87841753-1	1356.83
282	4	Mahmud Origin	morigin7t@archive.org	+50376036683	05996807-7	992.55
283	5	Janessa Teideman	jteideman7u@hostgator.com	+50376259084	20155113-1	1201.92
284	7	Nicol Streather	nstreather7v@go.com	+50368762327	84976111-7	1140.98
285	8	Brandyn Smail	bsmail7w@bandcamp.com	+50360457826	17963694-4	1489.34
286	5	Waring Filpo	wfilpo7x@google.ca	+50367392564	13625130-4	706.87
287	5	Ida Edwicker	iedwicker7y@xing.com	+50372236171	50465468-5	1072.93
288	3	Elvera Kern	ekern7z@latimes.com	+50375890808	33847363-4	1137.33
289	8	Thorstein Cottel	tcottel80@webnode.com	+50360965837	15626934-6	1056.50
290	3	Darnell Normanville	dnormanville81@intel.com	+50363259625	68712940-9	1397.04
291	9	Aron Dashper	adashper82@wix.com	+50379832453	43611161-5	709.66
292	7	Frazer Manass	fmanass83@networkadvertising.org	+50370590702	09011067-7	1115.31
293	8	Ingra Lilburn	ililburn84@quantcast.com	+50323080591	06698730-0	383.40
294	7	Lucas Folbigg	lfolbigg85@wufoo.com	+50371457835	55422101-5	1123.42
295	5	Lita Gerasch	lgerasch86@princeton.edu	+50320120413	39453840-8	871.19
296	3	Renell Dionsetto	rdionsetto87@lulu.com	+50373440667	90963251-0	1187.27
297	10	Bab Boarder	bboarder88@imageshack.us	+50364360039	51715618-5	547.56
298	4	Winslow MacCahee	wmaccahee89@newyorker.com	+50369100966	39943600-6	1086.53
299	6	Joan Ducker	jducker8a@digg.com	+50322733745	86963034-1	1482.86
300	1	Barbee Tape	btape8b@t.co	+50365131144	07883576-6	682.27
301	7	Dulcinea Carletto	dcarletto8c@ebay.com	+50370589512	91639949-4	529.39
302	5	Jenn Cobain	jcobain8d@typepad.com	+50329204991	32861622-0	932.07
303	10	Corissa Danzelman	cdanzelman8e@soup.io	+50364902275	78660154-2	1405.39
304	4	Terrance Dudbridge	tdudbridge8f@infoseek.co.jp	+50363856965	03390087-8	682.31
305	2	Hamnet Sturror	hsturror8g@canalblog.com	+50377668230	36390191-5	735.22
306	1	Janis Aldred	jaldred8h@creativecommons.org	+50321336017	61168067-3	739.65
307	8	Juliane Jobson	jjobson8i@i2i.jp	+50363294781	72793242-7	502.86
308	2	Leelah Balm	lbalm8j@ihg.com	+50320096244	18857043-5	1164.75
309	6	Bernadina Dix	bdix8k@youtu.be	+50322179037	93893693-7	1375.55
310	3	Mohammed Everix	meverix8l@auda.org.au	+50363952288	36920610-2	1090.62
311	7	Ad Dodson	adodson8m@dell.com	+50374901661	23915005-4	884.90
312	7	Eba Wiffen	ewiffen8n@arstechnica.com	+50371018202	46822531-3	1291.44
313	5	Hank Trodler	htrodler8o@chicagotribune.com	+50379873603	33086066-8	1290.04
314	2	Bayard Spain-Gower	bspaingower8p@ibm.com	+50371433964	28861152-5	906.49
315	9	Eydie Stearley	estearley8q@chron.com	+50326341954	82170046-0	526.43
316	3	Brose Shutler	bshutler8r@ning.com	+50321112385	51722673-9	370.64
317	9	Clemens Von Der Empten	cvon8s@cnbc.com	+50367857320	20640523-7	453.57
318	3	Waylan Bovingdon	wbovingdon8t@toplist.cz	+50377929284	69127333-2	521.66
319	3	Cate Larroway	clarroway8u@blogs.com	+50361989584	81367875-3	710.00
320	8	Theressa Zannutti	tzannutti8v@howstuffworks.com	+50329570017	26508828-6	418.14
321	5	Reese Deason	rdeason8w@merriam-webster.com	+50326913981	58177886-4	581.02
322	2	Tedmund Rother	trother8x@blog.com	+50322828603	64088502-8	751.81
323	5	Trudey Grange	tgrange8y@auda.org.au	+50360918793	53168321-5	791.95
324	6	Diego Mackro	dmackro8z@vistaprint.com	+50325607317	66811305-3	1134.24
325	6	Allyce Ingleton	aingleton90@mozilla.com	+50379108972	33694538-5	1011.20
326	5	Trudie Zanuciolii	tzanuciolii91@globo.com	+50364375174	97648560-3	574.36
327	9	Keven Kehri	kkehri92@nytimes.com	+50364859671	30833164-8	443.98
328	5	Birdie Keme	bkeme93@toplist.cz	+50362997714	98217920-7	1037.91
329	2	Kellie Castelain	kcastelain94@cbsnews.com	+50378959033	54699508-3	1483.41
330	7	Reena Itscovitz	ritscovitz95@examiner.com	+50376469079	77680932-3	1102.06
331	2	Lock Sharratt	lsharratt96@ifeng.com	+50326101879	25357802-1	647.87
332	1	Taylor Havoc	thavoc97@webnode.com	+50323371194	83773195-0	514.19
333	7	Barbara-anne Alcock	balcock98@cdbaby.com	+50374754808	38595741-4	1058.29
334	3	Nita Allder	nallder99@gravatar.com	+50372379524	99601934-8	1279.01
335	1	Bordie Moye	bmoye9a@lulu.com	+50328044239	59175845-7	1060.67
336	1	Tommy Craighall	tcraighall9b@statcounter.com	+50365806457	42272003-0	1185.14
337	1	Quincey Brightey	qbrightey9c@youku.com	+50372436691	16324718-2	744.50
338	4	Gerardo Guenther	gguenther9d@facebook.com	+50379663613	23484450-2	1124.87
339	3	Gregoor Fuke	gfuke9e@mashable.com	+50372622175	04933024-5	1119.46
340	1	Eziechiele Ashwell	eashwell9f@adobe.com	+50325117698	29240367-0	1134.45
341	2	Cirillo Deschelle	cdeschelle9g@comsenz.com	+50326819626	05290953-4	843.71
342	10	Daphene Dwane	ddwane9h@paginegialle.it	+50366225682	74723120-4	675.55
343	2	Renado Buxcy	rbuxcy9i@google.com.hk	+50361352938	00722161-8	522.42
344	9	Drew Shakle	dshakle9j@mit.edu	+50368466989	45327639-5	1360.18
345	9	Dorthy Le Barre	dle9k@illinois.edu	+50366682971	89270397-7	827.91
346	9	Franklin Dytham	fdytham9l@zimbio.com	+50325854141	78425429-7	567.56
347	9	Larissa Tearle	ltearle9m@sakura.ne.jp	+50373427829	49051922-6	383.17
348	6	Pasquale Wheelhouse	pwheelhouse9n@narod.ru	+50327464350	26702421-6	1329.69
349	10	Addia Shenton	ashenton9o@patch.com	+50328587175	67608012-8	869.19
350	8	Evin Le Marchant	ele9p@cafepress.com	+50375157693	01533427-3	673.17
351	7	Arne Evanson	aevanson9q@drupal.org	+50378128140	93810407-7	1483.46
352	6	Guillaume McGeachey	gmcgeachey9r@irs.gov	+50328088855	51163718-0	770.83
353	3	Honey Cleevely	hcleevely9s@reverbnation.com	+50360508245	83232317-9	1142.27
354	8	Nealy Brecknell	nbrecknell9t@typepad.com	+50322779567	57239957-7	636.29
355	6	Fairleigh Simanek	fsimanek9u@soup.io	+50360463542	55791506-1	668.23
356	5	Elli Pickton	epickton9v@bbb.org	+50363931780	88123813-7	379.16
357	4	Gawen Jindrich	gjindrich9w@ox.ac.uk	+50377520972	22361285-0	1438.17
358	5	Amery Castelyn	acastelyn9x@toplist.cz	+50323666265	62305343-9	535.35
359	5	Andris Ibbott	aibbott9y@examiner.com	+50369496224	32189364-1	1099.11
360	6	Gertie Cardall	gcardall9z@wordpress.com	+50329454199	44546817-3	1461.49
361	6	Paolina Heaps	pheapsa0@cdc.gov	+50364187508	66918601-7	993.89
362	9	Alexei Richmont	arichmonta1@google.nl	+50324892075	24907499-4	816.50
363	6	Shelly Lagadu	slagadua2@last.fm	+50324174383	59715526-8	566.58
364	7	Valentijn Rollett	vrolletta3@zimbio.com	+50377664268	24849880-1	595.68
365	7	Lamond Ernke	lernkea4@uiuc.edu	+50376564261	37987915-8	462.12
366	10	Randall Edmans	redmansa5@narod.ru	+50320597987	16884141-2	393.54
367	6	Maurice Eastment	meastmenta6@chronoengine.com	+50360177732	84866484-7	1432.07
368	3	Garik Syphas	gsyphasa7@w3.org	+50360526775	77708807-7	1473.67
369	10	Basilio Manjot	bmanjota8@gov.uk	+50366096153	89342742-7	427.82
370	7	Aldridge Niven	anivena9@stanford.edu	+50364972448	10928822-1	1334.94
371	4	Amitie Haxell	ahaxellaa@blogs.com	+50328771587	01157561-1	549.91
372	6	Meggie McClean	mmccleanab@europa.eu	+50322636675	49245929-7	872.53
373	10	Rupert Anear	ranearac@businessinsider.com	+50366549590	81835697-6	793.49
374	5	Katine Hatchard	khatchardad@arstechnica.com	+50375818969	76230780-5	549.07
375	4	Donielle Chidgey	dchidgeyae@ca.gov	+50371154640	17425958-7	1259.60
376	6	Nertie McGrotty	nmcgrottyaf@intel.com	+50323918824	37003680-8	1171.02
377	8	Lizzy Scrimshaw	lscrimshawag@t.co	+50323074124	96196611-7	460.72
378	2	Georgi Douce	gdouceah@seesaa.net	+50364403933	19548598-6	958.97
379	1	Gae Blankenship	gblankenshipai@cornell.edu	+50373629447	78083009-2	397.94
380	2	Von Whitefoot	vwhitefootaj@woothemes.com	+50320829145	55885800-8	973.67
381	9	Sile Jirka	sjirkaak@about.me	+50376865365	10542439-2	1307.38
382	3	Randell Cordingly	rcordinglyal@earthlink.net	+50322370326	50504268-5	489.29
383	2	Eimile Shory	eshoryam@altervista.org	+50325670811	43453114-1	775.17
384	7	Saleem Rowlings	srowlingsan@shareasale.com	+50375964872	72211746-3	1275.66
385	4	Nina McCreary	nmccrearyao@baidu.com	+50365917419	38956973-8	436.51
386	8	Carolina Tomasik	ctomasikap@paypal.com	+50328227602	97585968-8	1147.88
387	10	Vonnie Keddie	vkeddieaq@amazon.co.jp	+50363475887	22202683-8	1179.80
388	10	Gaston Bleackley	gbleackleyar@hibu.com	+50327659197	44466065-4	1323.49
389	7	Fanya Starkie	fstarkieas@paypal.com	+50366583474	20782733-7	1324.47
390	5	Wilbur Lamberth	wlamberthat@upenn.edu	+50329319926	99957196-4	1100.94
391	1	Devonne Nickless	dnicklessau@rediff.com	+50372042489	89145692-2	1028.22
392	6	Lu Vernazza	lvernazzaav@reuters.com	+50321531553	62629292-9	527.41
393	5	Kaleena Patient	kpatientaw@theglobeandmail.com	+50373594290	40399456-5	1324.96
394	8	Ronni Ourtic	rourticax@phoca.cz	+50368174346	62628971-2	980.95
395	1	Hewett Tomlin	htomlinay@alibaba.com	+50366620569	62959047-8	826.03
396	2	Howie Veelers	hveelersaz@eventbrite.com	+50320747695	69187888-7	1474.00
397	7	Lindi Shiril	lshirilb0@biglobe.ne.jp	+50329116067	16600945-2	1049.75
398	7	Gaile Dunnico	gdunnicob1@google.com.br	+50322601973	90297027-8	1407.73
399	5	Angelique Houdmont	ahoudmontb2@google.nl	+50321866569	96423809-6	664.69
400	10	Hesther Kahane	hkahaneb3@163.com	+50360489783	67098092-2	1114.61
401	3	Verna Husselbee	vhusselbeeb4@dot.gov	+50370485459	54538959-8	1316.14
402	10	Tricia Eager	teagerb5@dedecms.com	+50328770221	64807574-7	1348.40
403	9	Hedvige Tomaszczyk	htomaszczykb6@dagondesign.com	+50369149625	45069989-9	818.25
404	1	Murdoch Arsmith	marsmithb7@sciencedirect.com	+50371016855	08268741-8	1245.92
405	1	Renaldo Rockwell	rrockwellb8@blogtalkradio.com	+50362619188	79520425-0	546.28
406	2	Corrine Blick	cblickb9@senate.gov	+50379642438	28328870-6	390.45
407	5	Bev Allflatt	ballflattba@zimbio.com	+50321172436	48986249-3	885.48
408	10	Kippie Hasely	khaselybb@seattletimes.com	+50324501003	48701030-7	783.16
409	8	Morris Parmby	mparmbybc@buzzfeed.com	+50325162377	53232843-4	1436.27
410	6	Bartholemy McCallister	bmccallisterbd@elegantthemes.com	+50377430901	51253872-0	1446.83
411	6	Rubi Gustus	rgustusbe@hc360.com	+50364821365	03103455-4	980.83
412	1	Devina Mossman	dmossmanbf@nationalgeographic.com	+50377959870	72075073-3	1075.52
413	10	Lynna Borthwick	lborthwickbg@sitemeter.com	+50369616138	50194439-9	1246.29
414	4	Cob Goford	cgofordbh@archive.org	+50379567875	00107510-4	1013.43
415	8	Doro Peteri	dpeteribi@vimeo.com	+50369451693	34260805-5	1107.53
416	2	Madelina Dodworth	mdodworthbj@whitehouse.gov	+50370968498	41371046-1	622.89
417	8	Betty Shevell	bshevellbk@ed.gov	+50364940960	16593964-3	1079.65
418	6	Valeda Waldie	vwaldiebl@parallels.com	+50324910316	88085243-3	795.52
419	2	Avie Domican	adomicanbm@technorati.com	+50327111171	03417570-3	456.26
420	10	Douglass De la croix	ddebn@slideshare.net	+50379298123	09110303-4	895.87
421	9	Evey O'Crevy	eocrevybo@cnbc.com	+50362850647	83017093-2	400.36
422	7	Mandel Antyshev	mantyshevbp@posterous.com	+50327795072	23056864-1	813.44
423	6	Iseabal Vogeler	ivogelerbq@hud.gov	+50362944851	65042671-0	911.74
424	3	Ardella Wicken	awickenbr@360.cn	+50367131096	75519845-9	1007.54
425	8	Larissa Lecordier	llecordierbs@bluehost.com	+50375981512	05973555-8	561.29
426	1	Helsa Whyatt	hwhyattbt@usda.gov	+50361268361	15354766-5	784.27
427	7	Pietra Giacovelli	pgiacovellibu@cocolog-nifty.com	+50375135878	67537638-0	660.83
428	3	Drucie Forkan	dforkanbv@state.tx.us	+50328813500	24928469-9	954.10
429	4	Maryjo Hubberstey	mhubbersteybw@statcounter.com	+50379588607	69578509-4	1197.39
430	5	Bambie Noakes	bnoakesbx@virginia.edu	+50361361173	47224912-9	1269.08
431	6	Maud Bagot	mbagotby@etsy.com	+50379582907	72243450-0	1057.64
432	9	Jozef Leeson	jleesonbz@google.cn	+50326677903	33872126-6	762.23
433	5	Gabriela Bartleman	gbartlemanc0@addtoany.com	+50327148353	49018244-3	1398.11
434	5	Florance McKeran	fmckeranc1@skype.com	+50329351225	57184834-7	379.18
435	1	Jeffrey Wayvill	jwayvillc2@i2i.jp	+50375333938	38015668-1	1355.70
436	2	Vale Draxford	vdraxfordc3@chicagotribune.com	+50324339234	61600545-0	379.05
437	3	Simmonds Camblin	scamblinc4@hostgator.com	+50327380761	45068673-1	1497.76
438	8	Alberto Jeynes	ajeynesc5@a8.net	+50360261902	87305285-6	1306.76
439	3	Kristan Lording	klordingc6@answers.com	+50370474656	71876182-0	1436.88
440	5	Hyacinthie Mogg	hmoggc7@cyberchimps.com	+50326311562	10546884-2	703.73
441	7	Ferdie Laidler	flaidlerc8@mapy.cz	+50321424632	28119304-7	548.44
442	8	Gerick Speares	gspearesc9@xrea.com	+50367520773	18802384-2	1354.03
443	3	Michele Cory	mcoryca@opensource.org	+50328123926	33643759-8	553.97
444	9	Brook Shipp	bshippcb@soup.io	+50377239598	97600532-6	1393.67
445	3	Meagan Minichillo	mminichillocc@virginia.edu	+50375930221	59636746-5	835.80
446	3	Valli Fernihough	vfernihoughcd@twitpic.com	+50370274448	86144932-7	1463.03
447	4	Pamella Brumham	pbrumhamce@miitbeian.gov.cn	+50323594865	41472976-7	777.19
448	8	Dedie Cummine	dcumminecf@dion.ne.jp	+50322475643	22394475-0	966.37
449	4	Winnie Mankor	wmankorcg@google.com.au	+50374668737	28732680-6	1001.45
450	5	Shalom Heifer	sheiferch@vinaora.com	+50366663660	16054891-4	1116.87
451	8	Heall Harbage	hharbageci@cyberchimps.com	+50326341611	40256646-1	1426.38
452	7	Betteanne De Vaan	bdecj@miibeian.gov.cn	+50368298343	27542051-9	809.32
453	9	Ingamar Utting	iuttingck@mail.ru	+50369053268	72398770-5	673.27
454	7	Octavia Teall	oteallcl@jimdo.com	+50323562407	82629026-3	1167.39
455	4	Lynnelle Scholtis	lscholtiscm@newyorker.com	+50325593784	53068512-2	878.02
456	1	Herculie Hammond	hhammondcn@goodreads.com	+50327174730	31457377-9	1069.69
457	8	Meta Carradice	mcarradiceco@webnode.com	+50363284596	14394064-5	1217.15
458	8	Maribel Simukov	msimukovcp@webs.com	+50371193269	20465070-1	756.05
459	3	Darda Glenn	dglenncq@dell.com	+50323273867	48993504-1	839.33
460	5	Eustacia Domke	edomkecr@t-online.de	+50322134708	86798709-2	1257.12
461	6	Alejandra Geistbeck	ageistbeckcs@delicious.com	+50372974473	48244467-3	958.14
462	9	Corty Grayland	cgraylandct@springer.com	+50321467203	36613236-3	553.42
463	7	Nevins Tender	ntendercu@ed.gov	+50321146147	62283040-1	555.77
464	8	Saunder Cleef	scleefcv@bloglovin.com	+50368887102	70187880-6	1082.34
465	7	Puff Normabell	pnormabellcw@huffingtonpost.com	+50322665685	97695412-8	613.41
466	8	Noll Staddart	nstaddartcx@g.co	+50371917458	78554880-0	1055.90
467	1	Winn McKibbin	wmckibbincy@netlog.com	+50324585948	28605056-3	1079.67
468	6	Oliy Coyne	ocoynecz@usgs.gov	+50376374699	58851712-5	826.45
469	4	Marsh Ewing	mewingd0@edublogs.org	+50366785512	97812159-8	1334.06
470	1	Rosene Viel	rvield1@businesswire.com	+50370995660	51083357-9	587.37
471	7	Kareem Lummasana	klummasanad2@wunderground.com	+50327066628	11676316-6	399.19
472	5	Garth Stairmond	gstairmondd3@sphinn.com	+50373644980	42798828-9	842.06
473	5	Tim Campbell-Dunlop	tcampbelldunlopd4@oracle.com	+50369340354	74623569-8	1320.56
474	4	Griselda Cottam	gcottamd5@pagesperso-orange.fr	+50327515814	22509115-6	1068.73
475	7	Kaitlynn Whiskin	kwhiskind6@netvibes.com	+50368178399	22714299-1	907.67
476	1	Hayley Leggen	hleggend7@pen.io	+50324714749	96443119-9	506.04
477	9	Davey Sayer	dsayerd8@lulu.com	+50376869665	42944533-0	1227.61
478	10	Lethia Walewicz	lwalewiczd9@cnn.com	+50329061067	88048804-6	1201.11
479	4	Prudi Kabos	pkabosda@about.me	+50362425252	26746984-4	554.55
480	4	Davide Strutton	dstruttondb@nifty.com	+50376832102	89207817-7	786.81
481	5	Carolynn Overbury	coverburydc@hp.com	+50327962481	60868980-7	774.55
482	6	Carlene Eccott	ceccottdd@google.es	+50364812846	28088243-4	1154.53
483	6	Dionne Quested	dquestedde@i2i.jp	+50327235044	99396981-9	736.50
484	2	Elysha Haddy	ehaddydf@wiley.com	+50378840397	33503231-8	1143.18
485	2	Lorrie Raiston	lraistondg@mediafire.com	+50364267134	80936224-1	750.96
486	5	Roley Concannon	rconcannondh@tmall.com	+50370692623	44505250-3	1438.78
487	8	Dionis Szymanowicz	dszymanowiczdi@globo.com	+50378504025	60937695-8	1306.97
488	10	Jinny Paddle	jpaddledj@ibm.com	+50372287517	77710521-8	1046.50
489	7	Caterina Gladtbach	cgladtbachdk@surveymonkey.com	+50365419235	02320897-4	1127.98
490	8	Taylor Medler	tmedlerdl@cdbaby.com	+50322484169	97877850-4	611.43
491	4	Sylvester Blesli	sbleslidm@icq.com	+50366322565	94494930-8	1212.40
492	5	Dietrich Blurton	dblurtondn@tripod.com	+50369921998	10780133-8	1392.93
493	3	Jory Gilliard	jgilliarddo@edublogs.org	+50368469693	02742106-3	880.96
494	3	Tristam Norvell	tnorvelldp@flickr.com	+50367693203	59169307-5	1312.39
495	10	Delila Judkin	djudkindq@elpais.com	+50379612493	40030889-9	1171.92
496	7	Daphene Guiot	dguiotdr@chron.com	+50324247063	84105225-6	566.23
497	7	Vergil Kaesmakers	vkaesmakersds@usnews.com	+50321245027	01877196-1	1105.93
498	5	Reece Grayer	rgrayerdt@imgur.com	+50369740950	02703139-4	409.50
499	3	Conrad Hailston	chailstondu@mtv.com	+50323792618	97784575-4	1068.21
500	10	Cookie O'Doghesty	codoghestydv@slate.com	+50367203576	70440065-1	1261.47
501	6	Kaycee Spandley	kspandleydw@flickr.com	+50327032028	69773691-4	896.63
502	7	Franzen Kermott	fkermottdx@so-net.ne.jp	+50325571713	98530068-5	512.57
503	6	Orelie MacCorley	omaccorleydy@angelfire.com	+50366428982	73876041-6	542.60
504	3	Winni Fearn	wfearndz@usatoday.com	+50369144004	83906697-0	867.01
505	8	Lynnette Benoi	lbenoie0@cocolog-nifty.com	+50372849480	17021309-7	1052.15
506	4	Essa Haster	ehastere1@technorati.com	+50361958648	58227768-8	402.37
507	9	Stevana Hinckesman	shinckesmane2@ihg.com	+50366525119	16150905-4	1133.40
508	3	Adel Earengey	aearengeye3@cam.ac.uk	+50365919202	76223965-0	618.16
509	1	Aleece Collar	acollare4@rakuten.co.jp	+50378577319	75430141-6	1322.87
510	3	Kati Branca	kbrancae5@businessweek.com	+50324084720	59473166-4	745.14
511	7	Egbert Brayley	ebrayleye6@google.de	+50372575548	93696957-9	1369.74
512	5	Gloriana Delmage	gdelmagee7@businessinsider.com	+50327975023	20931938-3	1122.90
513	10	Zachary Reside	zresidee8@abc.net.au	+50373232545	33069912-9	1497.26
514	2	Delcine McKibbin	dmckibbine9@slashdot.org	+50369972514	37285636-2	599.93
515	6	Dodie Chamberlin	dchamberlinea@reuters.com	+50326976337	29191074-9	1332.81
516	2	Forster Offell	foffelleb@google.nl	+50326187034	47614453-8	1485.79
517	2	Quintin Bradbeer	qbradbeerec@imdb.com	+50324836355	96243220-8	381.28
518	5	Kingsley Brazier	kbraziered@yellowbook.com	+50361529144	22191552-9	1213.01
519	2	Dulcine Goodrum	dgoodrumee@tripod.com	+50324012840	19877801-5	1454.99
520	4	Ruy Coping	rcopingef@tmall.com	+50371533326	01103602-4	1324.28
521	7	Darlleen Wildber	dwildbereg@zdnet.com	+50374123865	27007574-9	1049.65
522	9	Gaby Poff	gpoffeh@g.co	+50324178346	00887772-0	828.27
523	3	Merrill Olkowicz	molkowiczei@timesonline.co.uk	+50369893032	78200894-7	1087.18
524	10	Winona Kasparski	wkasparskiej@shop-pro.jp	+50371242198	94748203-5	1024.66
525	5	Junina Manhare	jmanhareek@npr.org	+50379633261	01268276-0	1280.38
526	2	Erwin Lebourn	elebournel@economist.com	+50364922405	79422142-8	1193.00
527	7	Franciskus Enoksson	fenokssonem@twitter.com	+50367293717	73309862-2	1328.67
528	5	Ogden Timmes	otimmesen@dot.gov	+50323615344	17038660-7	379.41
529	5	Tildie Thumann	tthumanneo@army.mil	+50369237519	71681871-0	1416.00
530	1	Richie Lezemere	rlezemereep@nature.com	+50323258928	71092828-7	1077.40
531	3	Jobey Scoggan	jscogganeq@newsvine.com	+50369305301	57691413-9	507.01
532	2	Bone Warwick	bwarwicker@t-online.de	+50369109089	95987580-7	1472.01
533	3	Catha Cristofano	ccristofanoes@1und1.de	+50363878395	22211408-3	1413.88
534	2	Jeniece Wormell	jwormellet@spiegel.de	+50366827024	99175148-2	1411.33
535	7	Townsend Duell	tduelleu@yellowbook.com	+50372443241	98834932-3	441.46
536	6	Anthe Gerbl	agerblev@scientificamerican.com	+50371839748	27105692-4	519.33
537	10	Yankee Tosh	ytoshew@4shared.com	+50375066317	83558146-3	1439.38
538	6	Culver Exelby	cexelbyex@msu.edu	+50365917373	85913529-7	533.96
539	8	Gerrie Linskey	glinskeyey@nytimes.com	+50328060666	31610106-4	769.92
540	5	Murray Skudder	mskudderez@macromedia.com	+50368342940	23988760-4	1456.45
541	1	Lolly Andrioletti	landriolettif0@google.ca	+50324528163	75420101-1	982.06
542	4	Brandice Hinks	bhinksf1@senate.gov	+50376459732	82003664-6	812.73
543	2	Milly Sperry	msperryf2@qq.com	+50369224277	31949597-1	628.47
544	3	Marlene Pettet	mpettetf3@dagondesign.com	+50377529306	59396238-7	1354.09
545	1	Karin Cuardall	kcuardallf4@posterous.com	+50326965575	40757338-3	431.47
546	2	Thibaud Wederell	twederellf5@fotki.com	+50326246568	18419700-1	782.38
547	6	Millicent Eldridge	meldridgef6@vinaora.com	+50377775469	19642641-2	541.58
548	2	Glynis Boarer	gboarerf7@shop-pro.jp	+50377965309	73689838-9	734.73
549	8	Cos Beckham	cbeckhamf8@blogger.com	+50363998724	79674198-6	884.15
550	8	Ab Partridge	apartridgef9@skyrock.com	+50376579238	39620785-2	1229.74
\.


--
-- TOC entry 5347 (class 0 OID 31069)
-- Dependencies: 226
-- Data for Name: estadia; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.estadia (id_estadia, id_reservacion, checkin, checkout) FROM stdin;
1001	1001	2025-10-24 09:23:38.724962	2025-10-28 09:23:38.724962
1002	1002	2025-04-16 12:45:44.95173	2025-04-20 12:45:44.95173
1003	1003	2025-02-27 08:38:59.326933	2025-03-03 08:38:59.326933
1004	1004	2025-03-07 20:42:46.665251	2025-03-09 20:42:46.665251
1005	1005	2025-05-28 15:33:49.02363	2025-06-03 15:33:49.02363
9	9	2026-05-13 07:17:08	2026-05-14 07:17:08
1006	1006	2025-05-24 01:28:33.142464	2025-05-26 01:28:33.142464
11	11	2026-03-23 22:26:25	2026-03-26 22:26:25
1007	1007	2025-09-05 04:42:30.473955	2025-09-09 04:42:30.473955
1008	1008	2025-05-14 19:02:15.326906	2025-05-17 19:02:15.326906
1009	1009	2025-10-20 01:36:32.21981	2025-10-25 01:36:32.21981
1010	1010	2025-08-09 12:10:25.681884	2025-08-14 12:10:25.681884
16	16	2026-04-25 23:21:13	2026-05-10 23:21:13
24	24	2025-02-18 07:18:53	2025-02-22 07:18:53
25	25	2026-01-19 04:51:23	2026-01-22 04:51:23
27	27	2026-03-14 11:00:29	2026-03-25 11:00:29
30	30	2025-02-09 13:43:47	2025-02-12 13:43:47
34	34	2026-04-30 00:14:34	2026-05-13 00:14:34
38	38	2025-03-17 22:08:49	2025-03-25 22:08:49
43	43	2025-11-06 11:56:37	2025-11-08 11:56:37
47	47	2025-03-31 01:26:48	2025-04-10 01:26:48
60	60	2025-01-26 08:54:25	2025-02-05 08:54:25
65	65	2025-08-06 23:16:35	2025-08-21 23:16:35
71	71	2026-05-08 07:22:36	2026-05-11 07:22:36
73	73	2025-06-05 23:11:20	2025-06-15 23:11:20
75	75	2025-01-29 17:43:53	2025-02-09 17:43:53
92	92	2026-04-03 00:44:19	2026-04-05 00:44:19
96	96	2025-05-08 10:35:43	2025-05-19 10:35:43
99	99	2026-03-16 05:50:29	2026-03-31 05:50:29
118	118	2025-03-14 01:28:55	2025-03-15 01:28:55
120	120	2025-10-03 07:07:01	2025-10-12 07:07:01
121	121	2025-10-07 16:02:08	2025-10-19 16:02:08
122	122	2025-10-19 15:18:42	2025-11-03 15:18:42
124	124	2026-03-17 12:13:40	2026-03-20 12:13:40
126	126	2025-04-01 11:36:41	2025-04-14 11:36:41
129	129	2025-07-06 00:34:50	2025-07-14 00:34:50
134	134	2025-03-20 09:43:03	2025-04-03 09:43:03
140	140	2026-04-27 23:50:19	2026-05-03 23:50:19
148	148	2025-11-14 23:32:18	2025-11-18 23:32:18
153	153	2025-02-10 04:20:40	2025-02-24 04:20:40
163	163	2026-03-22 09:15:31	2026-04-03 09:15:31
164	164	2025-10-28 03:13:20	2025-11-05 03:13:20
168	168	2026-05-24 22:53:59	2026-05-27 22:53:59
196	196	2026-03-03 14:40:07	2026-03-17 14:40:07
206	206	2025-03-21 03:32:22	2025-03-26 03:32:22
214	214	2025-10-03 17:14:00	2025-10-06 17:14:00
221	221	2025-12-07 08:27:35	2025-12-18 08:27:35
223	223	2026-01-18 21:26:56	2026-01-22 21:26:56
226	226	2026-01-20 18:26:27	2026-02-01 18:26:27
227	227	2025-05-18 02:12:43	2025-06-02 02:12:43
228	228	2025-09-27 21:21:39	2025-10-10 21:21:39
233	233	2025-12-21 03:12:19	2025-12-26 03:12:19
243	243	2025-12-31 12:02:59	2026-01-03 12:02:59
246	246	2026-03-24 14:16:15	2026-03-30 14:16:15
251	251	2025-01-04 03:06:12	2025-01-12 03:06:12
259	259	2026-05-05 10:16:48	2026-05-17 10:16:48
263	263	2025-08-20 22:35:43	2025-09-03 22:35:43
266	266	2025-05-14 05:45:18	2025-05-27 05:45:18
267	267	2025-04-28 18:55:28	2025-05-08 18:55:28
268	268	2026-03-22 16:32:04	2026-04-03 16:32:04
281	281	2025-04-21 03:06:11	2025-05-05 03:06:11
283	283	2025-07-20 13:29:51	2025-08-03 13:29:51
284	284	2025-12-16 18:39:03	2025-12-21 18:39:03
285	285	2025-06-29 07:40:17	2025-07-11 07:40:17
289	289	2026-03-15 10:01:39	2026-03-27 10:01:39
293	293	2025-12-27 18:28:35	2025-12-30 18:28:35
294	294	2025-01-17 01:29:14	2025-01-21 01:29:14
295	295	2025-01-24 07:56:21	2025-02-01 07:56:21
309	309	2025-04-19 21:07:21	2025-05-03 21:07:21
317	317	2025-07-09 19:34:57	2025-07-16 19:34:57
318	318	2025-08-26 16:01:47	2025-09-10 16:01:47
321	321	2025-06-12 16:50:18	2025-06-21 16:50:18
322	322	2025-10-24 21:31:22	2025-10-31 21:31:22
323	323	2025-12-15 17:49:22	2025-12-26 17:49:22
326	326	2025-08-12 21:04:11	2025-08-15 21:04:11
330	330	2025-09-21 21:41:56	2025-10-02 21:41:56
332	332	2025-05-18 00:25:05	2025-05-21 00:25:05
334	334	2025-03-21 16:10:00	2025-03-25 16:10:00
341	341	2025-04-05 08:49:28	2025-04-10 08:49:28
350	350	2026-02-02 08:56:42	2026-02-05 08:56:42
370	370	2025-08-09 23:33:51	2025-08-21 23:33:51
374	374	2025-07-30 02:34:01	2025-08-12 02:34:01
375	375	2026-03-09 08:10:05	2026-03-22 08:10:05
380	380	2025-11-25 18:02:25	2025-12-04 18:02:25
385	385	2025-11-09 14:02:36	2025-11-20 14:02:36
387	387	2026-03-07 10:07:14	2026-03-16 10:07:14
391	391	2025-09-15 09:43:11	2025-09-23 09:43:11
404	404	2025-11-04 10:58:18	2025-11-09 10:58:18
405	405	2026-02-26 02:53:39	2026-02-27 02:53:39
430	430	2025-12-21 19:33:54	2026-01-03 19:33:54
434	434	2026-04-10 03:44:47	2026-04-21 03:44:47
443	443	2025-03-29 11:46:51	2025-04-01 11:46:51
447	447	2025-09-11 18:51:44	2025-09-12 18:51:44
449	449	2025-07-02 20:49:28	2025-07-06 20:49:28
451	451	2026-03-09 18:29:17	2026-03-16 18:29:17
452	452	2025-04-02 15:35:20	2025-04-04 15:35:20
454	454	2026-02-07 00:20:04	2026-02-15 00:20:04
457	457	2025-03-04 21:33:22	2025-03-19 21:33:22
458	458	2025-07-05 20:16:07	2025-07-18 20:16:07
468	468	2025-11-09 05:39:55	2025-11-24 05:39:55
469	469	2026-05-08 22:27:58	2026-05-17 22:27:58
475	475	2026-01-24 07:27:21	2026-01-27 07:27:21
485	485	2025-06-11 20:32:19	2025-06-16 20:32:19
488	488	2025-01-26 06:19:46	2025-02-02 06:19:46
490	490	2025-10-20 08:59:22	2025-10-24 08:59:22
516	516	2025-05-08 04:19:02	2025-05-20 04:19:02
518	518	2026-02-24 05:47:09	2026-03-07 05:47:09
522	522	2025-01-28 23:27:01	2025-02-07 23:27:01
523	523	2025-01-28 03:54:58	2025-01-31 03:54:58
534	534	2026-01-12 10:52:23	2026-01-19 10:52:23
537	537	2025-10-26 13:50:08	2025-11-05 13:50:08
539	539	2026-04-02 17:29:29	2026-04-12 17:29:29
544	544	2025-12-27 19:00:28	2026-01-07 19:00:28
545	545	2026-05-28 12:27:24	2026-05-29 12:27:24
546	546	2026-02-22 04:42:37	2026-03-04 04:42:37
566	566	2026-04-12 18:54:41	2026-04-20 18:54:41
581	581	2025-02-22 04:38:29	2025-03-05 04:38:29
587	587	2026-03-29 18:49:08	2026-04-02 18:49:08
593	593	2025-09-18 19:56:09	2025-09-29 19:56:09
602	602	2026-04-16 19:37:22	2026-04-28 19:37:22
603	603	2025-06-15 22:29:22	2025-06-16 22:29:22
613	613	2025-11-08 17:53:30	2025-11-13 17:53:30
616	616	2025-07-25 03:07:27	2025-07-28 03:07:27
618	618	2025-10-04 19:59:35	2025-10-17 19:59:35
630	630	2025-07-25 15:25:00	2025-08-02 15:25:00
634	634	2025-09-11 13:24:37	2025-09-16 13:24:37
637	637	2025-05-29 22:29:37	2025-05-30 22:29:37
643	643	2026-01-17 22:10:37	2026-01-26 22:10:37
645	645	2025-08-06 06:58:58	2025-08-09 06:58:58
668	668	2025-03-24 16:13:28	2025-04-06 16:13:28
671	671	2026-05-14 12:33:16	2026-05-22 12:33:16
676	676	2026-03-16 08:56:42	2026-03-28 08:56:42
677	677	2025-04-23 10:07:04	2025-05-06 10:07:04
678	678	2025-03-19 03:02:05	2025-03-26 03:02:05
684	684	2026-01-24 16:57:51	2026-02-08 16:57:51
694	694	2026-01-28 21:01:45	2026-02-01 21:01:45
708	708	2025-04-15 11:59:41	2025-04-28 11:59:41
712	712	2025-03-03 11:05:17	2025-03-12 11:05:17
723	723	2025-06-07 23:06:00	2025-06-10 23:06:00
731	731	2026-05-21 23:12:37	2026-05-29 23:12:37
740	740	2026-04-23 05:33:29	2026-05-03 05:33:29
742	742	2025-04-29 14:15:32	2025-05-09 14:15:32
747	747	2025-09-02 11:12:01	2025-09-10 11:12:01
751	751	2025-10-13 23:57:13	2025-10-19 23:57:13
755	755	2025-03-10 14:02:29	2025-03-19 14:02:29
763	763	2026-03-28 11:32:17	2026-04-05 11:32:17
764	764	2026-02-28 13:31:01	2026-03-09 13:31:01
767	767	2026-03-21 15:00:51	2026-03-25 15:00:51
776	776	2025-12-27 14:24:58	2025-12-29 14:24:58
780	780	2025-10-09 06:39:34	2025-10-10 06:39:34
783	783	2025-09-01 12:09:40	2025-09-07 12:09:40
786	786	2025-01-15 20:08:17	2025-01-28 20:08:17
789	789	2026-01-30 09:43:55	2026-02-10 09:43:55
790	790	2025-01-24 23:57:44	2025-02-07 23:57:44
794	794	2025-07-29 00:10:31	2025-08-13 00:10:31
796	796	2025-02-14 03:57:27	2025-03-01 03:57:27
807	807	2025-08-11 20:37:23	2025-08-13 20:37:23
809	809	2025-03-10 12:24:21	2025-03-25 12:24:21
810	810	2026-02-07 11:19:29	2026-02-12 11:19:29
824	824	2025-02-11 23:07:13	2025-02-22 23:07:13
827	827	2025-10-22 05:04:48	2025-11-05 05:04:48
834	834	2025-05-12 02:00:37	2025-05-16 02:00:37
838	838	2025-06-25 21:33:04	2025-06-28 21:33:04
850	850	2026-04-05 11:19:28	2026-04-09 11:19:28
851	851	2025-07-08 10:54:32	2025-07-16 10:54:32
852	852	2026-02-18 14:45:29	2026-02-19 14:45:29
854	854	2025-10-01 14:51:18	2025-10-11 14:51:18
873	873	2025-04-18 20:17:16	2025-04-26 20:17:16
887	887	2025-08-10 18:52:37	2025-08-12 18:52:37
890	890	2025-10-29 22:10:19	2025-11-03 22:10:19
891	891	2026-04-04 23:50:36	2026-04-14 23:50:36
899	899	2026-02-11 01:21:41	2026-02-18 01:21:41
900	900	2025-06-09 03:40:17	2025-06-14 03:40:17
907	907	2025-05-25 05:57:23	2025-06-09 05:57:23
912	912	2025-04-21 19:11:16	2025-05-06 19:11:16
926	926	2025-07-13 21:29:38	2025-07-18 21:29:38
927	927	2026-03-01 17:49:02	2026-03-05 17:49:02
934	934	2026-04-13 11:04:17	2026-04-21 11:04:17
945	945	2025-12-23 21:29:08	2025-12-29 21:29:08
948	948	2025-09-21 22:49:06	2025-09-24 22:49:06
957	957	2026-02-03 04:07:43	2026-02-16 04:07:43
960	960	2025-04-14 13:53:05	2025-04-24 13:53:05
963	963	2026-03-03 12:55:24	2026-03-06 12:55:24
978	978	2025-09-30 01:29:41	2025-10-15 01:29:41
979	979	2025-01-22 12:05:38	2025-02-04 12:05:38
985	985	2025-12-10 17:06:48	2025-12-17 17:06:48
989	989	2026-01-23 18:37:36	2026-02-06 18:37:36
991	991	2025-07-31 15:05:18	2025-08-04 15:05:18
992	992	2025-04-11 12:38:59	2025-04-18 12:38:59
995	995	2025-01-23 19:04:06	2025-02-03 19:04:06
\.


--
-- TOC entry 5348 (class 0 OID 31077)
-- Dependencies: 227
-- Data for Name: factura; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.factura (id_factura, id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar) FROM stdin;
181	244	838	1001	2025-10-28 09:23:38.724962	TARJETA	2384.36
182	289	143	1002	2025-04-20 12:45:44.95173	TARJETA	1574.56
183	509	899	1003	2025-03-03 08:38:59.326933	EFECTIVO	1016.84
184	180	827	1004	2025-03-09 20:42:46.665251	PAYPAL	1017.06
185	415	403	1005	2025-06-03 15:33:49.02363	TARJETA	3791.86
186	545	838	1006	2025-05-26 01:28:33.142464	EFECTIVO	1462.56
187	462	143	1007	2025-09-09 04:42:30.473955	BITCOIN	1365.20
188	126	899	1008	2025-05-17 19:02:15.326906	PAYPAL	468.62
189	527	827	1009	2025-10-25 01:36:32.21981	TRANSFERENCIA	3622.75
190	327	403	1010	2025-08-14 12:10:25.681884	BITCOIN	892.20
1	210	169	9	2026-05-14 07:17:08	EFECTIVO	185.86
2	528	254	11	2026-03-26 22:26:25	TARJETA	475.58
3	129	760	24	2025-02-22 07:18:53	EFECTIVO	467.44
4	404	120	25	2026-01-22 04:51:23	TRANSFERENCIA	350.58
5	317	911	27	2026-03-25 11:00:29	EFECTIVO	1322.46
6	143	784	30	2025-02-12 13:43:47	PAYPAL	350.58
7	27	630	34	2026-05-13 00:14:34	TRANSFERENCIA	1519.18
8	33	205	38	2025-03-25 22:08:49	TARJETA	1004.88
9	243	920	43	2025-11-08 11:56:37	EFECTIVO	248.72
10	111	703	47	2025-04-10 01:26:48	BITCOIN	1195.60
11	358	224	60	2025-02-05 08:54:25	BITCOIN	7699.50
12	487	494	65	2025-08-21 23:16:35	BITCOIN	1797.90
13	222	399	75	2025-02-09 17:43:53	TRANSFERENCIA	1336.46
14	433	316	92	2026-04-05 00:44:19	TARJETA	293.72
15	192	706	99	2026-03-31 05:50:29	BITCOIN	1752.90
16	180	267	118	2025-03-15 01:28:55	PAYPAL	116.86
17	65	587	120	2025-10-12 07:07:01	PAYPAL	1051.74
18	360	812	126	2025-04-14 11:36:41	PAYPAL	1661.18
19	488	889	129	2025-07-14 00:34:50	BITCOIN	934.88
20	525	363	153	2025-02-24 04:20:40	BITCOIN	1735.56
21	522	753	163	2026-04-03 09:15:31	TRANSFERENCIA	1457.32
22	390	934	164	2025-11-05 03:13:20	PAYPAL	975.88
23	61	941	196	2026-03-17 14:40:07	BITCOIN	1636.04
24	436	107	206	2025-03-26 03:32:22	BITCOIN	3449.25
25	355	575	223	2026-01-22 21:26:56	EFECTIVO	594.44
26	35	783	227	2025-06-02 02:12:43	BITCOIN	1752.90
27	524	16	246	2026-03-30 14:16:15	TARJETA	701.16
28	278	597	251	2025-01-12 03:06:12	TARJETA	989.88
29	113	959	259	2026-05-17 10:16:48	PAYPAL	1462.32
30	135	67	263	2025-09-03 22:35:43	TARJETA	1696.04
31	522	819	267	2025-05-08 18:55:28	EFECTIVO	1935.90
32	374	266	268	2026-04-03 16:32:04	TARJETA	1427.32
33	51	919	285	2025-07-11 07:40:17	TARJETA	1414.32
34	214	134	293	2025-12-30 18:28:35	PAYPAL	350.58
35	224	283	295	2025-02-01 07:56:21	TRANSFERENCIA	944.88
36	290	990	309	2025-05-03 21:07:21	TRANSFERENCIA	1668.04
37	433	679	326	2025-08-15 21:04:11	EFECTIVO	385.58
38	300	127	330	2025-10-02 21:41:56	TARJETA	1317.46
39	49	982	332	2025-05-21 00:25:05	BITCOIN	382.58
40	4	127	334	2025-03-25 16:10:00	TRANSFERENCIA	544.44
41	46	732	370	2025-08-21 23:33:51	PAYPAL	5586.80
42	361	977	374	2025-08-12 02:34:01	TRANSFERENCIA	1519.18
43	301	670	375	2026-03-22 08:10:05	TRANSFERENCIA	1599.18
44	305	225	380	2025-12-04 18:02:25	TRANSFERENCIA	1111.74
45	121	207	387	2026-03-16 10:07:14	TARJETA	1051.74
46	112	452	391	2025-09-23 09:43:11	EFECTIVO	994.88
47	126	371	434	2026-04-21 03:44:47	TARJETA	1338.46
48	31	193	443	2025-04-01 11:46:51	EFECTIVO	350.58
49	215	387	452	2025-04-04 15:35:20	PAYPAL	1036.16
50	126	552	469	2026-05-17 22:27:58	PAYPAL	4071.34
51	33	650	485	2025-06-16 20:32:19	TARJETA	609.30
52	208	913	516	2025-05-20 04:19:02	TARJETA	1447.32
53	257	594	522	2025-02-07 23:27:01	BITCOIN	1758.00
54	466	710	523	2025-01-31 03:54:58	EFECTIVO	350.58
55	319	763	546	2026-03-04 04:42:37	PAYPAL	1224.60
56	442	325	587	2026-04-02 18:49:08	TARJETA	502.44
57	128	443	593	2025-09-29 19:56:09	PAYPAL	5002.33
58	370	892	603	2025-06-16 22:29:22	BITCOIN	116.86
59	315	631	613	2025-11-13 17:53:30	TRANSFERENCIA	7237.00
60	520	653	618	2025-10-17 19:59:35	EFECTIVO	2937.29
61	486	280	630	2025-08-02 15:25:00	EFECTIVO	5752.08
62	302	241	634	2025-09-16 13:24:37	EFECTIVO	584.30
63	24	45	643	2026-01-26 22:10:37	TARJETA	2538.84
64	439	800	645	2025-08-09 06:58:58	PAYPAL	350.58
65	19	405	671	2026-05-22 12:33:16	PAYPAL	1792.48
66	258	857	676	2026-03-28 08:56:42	TRANSFERENCIA	1482.32
67	480	217	677	2025-05-06 10:07:04	TARJETA	1674.18
68	224	537	678	2025-03-26 03:02:05	TRANSFERENCIA	863.02
69	174	457	694	2026-02-01 21:01:45	TARJETA	467.44
70	258	827	712	2025-03-12 11:05:17	TARJETA	1051.74
71	95	830	723	2025-06-10 23:06:00	TRANSFERENCIA	350.58
72	241	545	731	2026-05-29 23:12:37	TRANSFERENCIA	934.88
73	263	851	742	2025-05-09 14:15:32	EFECTIVO	1168.60
74	487	356	747	2025-09-10 11:12:01	PAYPAL	985.88
75	250	216	751	2025-10-19 23:57:13	PAYPAL	701.16
76	86	279	789	2026-02-10 09:43:55	TARJETA	1300.46
77	148	816	809	2025-03-25 12:24:21	EFECTIVO	3607.70
78	35	126	824	2025-02-22 23:07:13	TRANSFERENCIA	1285.46
79	465	303	834	2025-05-16 02:00:37	EFECTIVO	467.44
80	416	139	850	2026-04-09 11:19:28	EFECTIVO	467.44
81	23	603	873	2025-04-26 20:17:16	PAYPAL	934.88
82	374	754	890	2025-11-03 22:10:19	EFECTIVO	584.30
83	491	427	899	2026-02-18 01:21:41	TARJETA	828.02
84	89	221	900	2025-06-14 03:40:17	PAYPAL	584.30
85	168	97	912	2025-05-06 19:11:16	PAYPAL	1797.90
86	84	638	926	2025-07-18 21:29:38	TARJETA	584.30
87	369	284	948	2025-09-24 22:49:06	TRANSFERENCIA	4622.14
88	536	965	960	2025-04-24 13:53:05	BITCOIN	1168.60
89	263	371	978	2025-10-15 01:29:41	TRANSFERENCIA	1752.90
90	409	563	979	2025-02-04 12:05:38	BITCOIN	14156.06
91	517	745	985	2025-12-17 17:06:48	PAYPAL	818.02
92	136	450	989	2026-02-06 18:37:36	PAYPAL	1651.04
93	271	991	991	2025-08-04 15:05:18	EFECTIVO	2480.64
94	411	651	992	2025-04-18 12:38:59	PAYPAL	818.02
95	431	197	995	2025-02-03 19:04:06	BITCOIN	1371.46
96	403	661	934	2026-04-21 11:04:17	BITCOIN	7887.88
97	109	609	780	2025-10-10 06:39:34	BITCOIN	1817.23
98	109	605	544	2026-01-07 19:00:28	PAYPAL	13011.97
99	69	999	284	2025-12-21 18:39:03	EFECTIVO	1211.10
100	81	899	318	2025-09-10 16:01:47	BITCOIN	21594.80
101	411	480	708	2025-04-28 11:59:41	PAYPAL	8187.08
102	22	822	887	2025-08-12 18:52:37	TRANSFERENCIA	3254.82
103	199	838	827	2025-11-05 05:04:48	PAYPAL	34316.12
104	361	16	581	2025-03-05 04:38:29	EFECTIVO	13864.74
105	346	867	783	2025-09-07 12:09:40	TARJETA	3729.82
106	228	71	740	2026-05-03 05:33:29	TARJETA	3673.50
107	410	527	96	2025-05-19 10:35:43	TRANSFERENCIA	16454.25
108	28	924	341	2025-04-10 08:49:28	TRANSFERENCIA	3283.80
109	297	209	168	2026-05-27 22:53:59	TRANSFERENCIA	2656.51
110	399	944	545	2026-05-29 12:27:24	TRANSFERENCIA	863.98
111	511	91	957	2026-02-16 04:07:43	EFECTIVO	6301.41
112	532	375	786	2025-01-28 20:08:17	TRANSFERENCIA	14892.61
113	143	266	776	2025-12-29 14:24:58	TARJETA	448.70
114	164	423	454	2026-02-15 00:20:04	PAYPAL	5511.84
115	36	258	283	2025-08-03 13:29:51	EFECTIVO	11163.62
116	175	123	148	2025-11-18 23:32:18	TRANSFERENCIA	2508.80
117	360	232	451	2026-03-16 18:29:17	TARJETA	5040.57
118	148	398	405	2026-02-27 02:53:39	BITCOIN	719.24
119	195	905	281	2025-05-05 03:06:11	EFECTIVO	15024.48
120	348	616	539	2026-04-12 17:29:29	EFECTIVO	5047.10
121	149	143	16	2026-05-10 23:21:13	EFECTIVO	26166.30
122	164	151	134	2025-04-03 09:43:03	EFECTIVO	15199.12
123	110	477	927	2026-03-05 17:49:02	PAYPAL	748.36
124	91	827	430	2026-01-03 19:33:54	BITCOIN	17745.05
125	419	959	851	2025-07-16 10:54:32	TRANSFERENCIA	5970.40
126	174	562	221	2025-12-18 08:27:35	TARJETA	1251.00
127	426	403	321	2025-06-21 16:50:18	TRANSFERENCIA	17247.49
128	191	106	668	2025-04-06 16:13:28	TRANSFERENCIA	9248.38
129	236	39	243	2026-01-03 12:02:59	BITCOIN	2135.03
130	312	28	602	2026-04-28 19:37:22	EFECTIVO	2978.84
131	345	136	124	2026-03-20 12:13:40	TARJETA	1981.88
132	43	26	490	2025-10-24 08:59:22	PAYPAL	2504.40
133	86	554	763	2026-04-05 11:32:17	BITCOIN	4274.80
134	389	935	266	2025-05-27 05:45:18	BITCOIN	3838.47
135	241	929	637	2025-05-30 22:29:37	EFECTIVO	1393.29
136	147	18	534	2026-01-19 10:52:23	PAYPAL	1972.96
137	524	389	963	2026-03-06 12:55:24	PAYPAL	4021.00
138	364	80	907	2025-06-09 05:57:23	TRANSFERENCIA	3843.70
139	476	262	228	2025-10-10 21:21:39	BITCOIN	11447.06
140	313	347	764	2026-03-09 13:31:01	EFECTIVO	13886.97
141	113	534	121	2025-10-19 16:02:08	PAYPAL	12488.32
142	19	439	566	2026-04-20 18:54:41	EFECTIVO	4883.28
143	538	621	73	2025-06-15 23:11:20	EFECTIVO	6767.80
144	92	971	945	2025-12-29 21:29:08	PAYPAL	4094.04
145	186	628	322	2025-10-31 21:31:22	TRANSFERENCIA	10603.13
146	103	868	71	2026-05-11 07:22:36	BITCOIN	1935.76
147	437	621	350	2026-02-05 08:56:42	PAYPAL	465.19
148	327	472	468	2025-11-24 05:39:55	TRANSFERENCIA	15916.75
149	161	441	796	2025-03-01 03:57:27	EFECTIVO	16175.85
150	34	136	684	2026-02-08 16:57:51	EFECTIVO	4872.65
151	356	519	854	2025-10-11 14:51:18	TRANSFERENCIA	4145.30
152	204	642	810	2026-02-12 11:19:29	TRANSFERENCIA	3568.75
153	268	415	122	2025-11-03 15:18:42	TRANSFERENCIA	6917.95
154	347	76	794	2025-08-13 00:10:31	TRANSFERENCIA	10962.70
155	13	842	475	2026-01-27 07:27:21	BITCOIN	1523.35
156	441	8	488	2025-02-02 06:19:46	EFECTIVO	7166.55
157	355	500	385	2025-11-20 14:02:36	TRANSFERENCIA	8249.61
158	248	600	537	2025-11-05 13:50:08	BITCOIN	4053.00
159	429	741	807	2025-08-13 20:37:23	TARJETA	1291.56
160	508	928	317	2025-07-16 19:34:57	TRANSFERENCIA	759.66
161	303	532	518	2026-03-07 05:47:09	BITCOIN	6976.81
162	5	87	457	2025-03-19 21:33:22	BITCOIN	10050.05
163	435	386	755	2025-03-19 14:02:29	PAYPAL	4865.27
164	22	155	449	2025-07-06 20:49:28	PAYPAL	663.04
165	173	129	790	2025-02-07 23:57:44	TARJETA	9517.54
166	488	491	616	2025-07-28 03:07:27	TARJETA	2083.41
167	37	377	289	2026-03-27 10:01:39	TRANSFERENCIA	2225.12
168	331	59	852	2026-02-19 14:45:29	TRANSFERENCIA	786.76
169	236	153	233	2025-12-26 03:12:19	TRANSFERENCIA	872.95
170	413	52	226	2026-02-01 18:26:27	TARJETA	8313.28
171	486	442	767	2026-03-25 15:00:51	BITCOIN	4113.56
172	202	33	323	2025-12-26 17:49:22	TRANSFERENCIA	895.00
173	494	254	294	2025-01-21 01:29:14	TARJETA	636.72
174	490	529	140	2026-05-03 23:50:19	PAYPAL	4596.76
175	435	147	214	2025-10-06 17:14:00	BITCOIN	1663.11
176	387	711	447	2025-09-12 18:51:44	EFECTIVO	758.28
177	259	440	891	2026-04-14 23:50:36	EFECTIVO	1059.00
178	40	132	458	2025-07-18 20:16:07	BITCOIN	8446.31
179	477	941	838	2025-06-28 21:33:04	TARJETA	2305.61
180	208	995	404	2025-11-09 10:58:18	TRANSFERENCIA	2701.60
\.


--
-- TOC entry 5349 (class 0 OID 31090)
-- Dependencies: 228
-- Data for Name: habitacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.habitacion (id_habitacion, id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima, descripcion) FROM stdin;
9	1	6	1609	8	518.22	OCUPADA	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio. Curabitur convallis.
13	2	10	3013	2	646.25	DISPONIBLE	7	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Vivamus vestibulum sagittis sapien.
22	2	5	2522	6	105.00	OCUPADA	9	Nulla facilisi.
20	3	10	5020	4	76.00	OCUPADA	4	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
118	2	2	6318	2	64.00	OCUPADA	4	Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
166	2	5	6666	9	73.00	OCUPADA	9	Suspendisse potenti.
211	2	10	11211	10	98.00	MANTENIMIENTO	1	Nunc purus. Phasellus in felis.
228	1	1	8328	7	116.00	OCUPADA	6	Aliquam erat volutpat. In congue.
391	2	9	5291	7	119.00	MANTENIMIENTO	1	Integer ac leo.
471	1	1	7571	3	121.00	MANTENIMIENTO	9	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
31	3	9	3931	10	716.77	OCUPADA	2	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique.
473	3	2	4673	4	60.00	MANTENIMIENTO	7	Nam dui.
33	3	9	3933	8	273.74	DISPONIBLE	3	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
489	1	7	5189	5	62.00	MANTENIMIENTO	7	Nam dui.
496	2	2	8696	7	73.00	DISPONIBLE	4	Cras non velit nec nisi vulputate nonummy.
555	1	5	6055	6	120.00	DISPONIBLE	7	Duis bibendum.
37	1	7	1737	6	373.20	MANTENIMIENTO	6	Pellentesque ultrices mattis odio. Donec vitae nisi.
38	2	2	2238	3	229.98	DISPONIBLE	7	Sed accumsan felis. Ut at dolor quis odio consequat varius.
563	3	8	11363	4	148.00	DISPONIBLE	3	Vestibulum rutrum rutrum neque.
684	1	5	9184	8	104.00	DISPONIBLE	5	Vivamus tortor. Duis mattis egestas metus.
735	1	8	8535	8	62.00	DISPONIBLE	8	Donec dapibus.
789	1	8	7589	1	132.00	OCUPADA	5	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
797	3	1	6897	6	110.00	DISPONIBLE	7	Integer a nibh. In quis justo.
44	2	9	2944	1	461.14	DISPONIBLE	9	In congue. Etiam justo.
817	2	2	8017	4	91.00	MANTENIMIENTO	5	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo. In blandit ultrices enim.
46	1	2	1246	7	745.31	DISPONIBLE	5	Ut tellus. Nulla ut erat id mauris vulputate elementum.
47	3	7	3747	9	722.58	OCUPADA	10	Phasellus in felis. Donec semper sapien a libero.
876	1	2	8076	5	113.00	MANTENIMIENTO	2	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
51	2	7	2751	9	742.68	MANTENIMIENTO	6	Proin at turpis a pede posuere nonummy. Integer non velit.
53	3	8	3853	2	208.83	DISPONIBLE	1	Aliquam erat volutpat.
63	3	7	3763	10	120.95	DISPONIBLE	8	Vivamus vel nulla eget eros elementum pellentesque.
64	3	8	3864	3	384.40	OCUPADA	2	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
65	3	2	3265	1	569.37	MANTENIMIENTO	5	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
72	3	5	3572	2	394.77	MANTENIMIENTO	1	Vivamus tortor.
77	2	2	2277	1	91.67	OCUPADA	3	In hac habitasse platea dictumst.
78	1	6	1678	3	176.29	DISPONIBLE	6	Nullam sit amet turpis elementum ligula vehicula consequat.
80	1	10	2080	4	632.37	MANTENIMIENTO	8	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
82	2	10	3082	8	305.12	DISPONIBLE	8	Aliquam non mauris.
89	3	5	3589	6	352.60	OCUPADA	3	Sed accumsan felis.
90	2	3	2390	9	100.68	MANTENIMIENTO	1	Quisque id justo sit amet sapien dignissim vestibulum. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est.
92	2	10	3092	6	211.34	DISPONIBLE	5	Duis aliquam convallis nunc.
95	2	3	2395	1	142.47	MANTENIMIENTO	8	Duis mattis egestas metus.
101	3	2	3301	2	438.55	OCUPADA	2	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
105	2	5	2605	5	569.61	OCUPADA	1	In hac habitasse platea dictumst.
133	1	3	1433	3	133.00	MANTENIMIENTO	5	Donec quis orci eget orci vehicula condimentum.
108	1	7	1808	8	668.35	MANTENIMIENTO	10	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
109	2	7	2809	10	315.82	MANTENIMIENTO	8	Nulla suscipit ligula in lacus.
115	1	3	1415	8	224.17	MANTENIMIENTO	3	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
120	2	8	2920	1	155.80	DISPONIBLE	10	Morbi a ipsum.
123	2	5	2623	3	320.35	OCUPADA	5	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
127	3	1	3227	4	399.86	OCUPADA	9	Proin leo odio, porttitor id, consequat in, consequat ut, nulla. Sed accumsan felis.
129	1	5	1629	3	450.67	OCUPADA	2	Vestibulum ac est lacinia nisi venenatis tristique.
130	1	3	1430	5	309.15	MANTENIMIENTO	6	Pellentesque at nulla.
134	2	8	2934	1	445.17	OCUPADA	7	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
135	2	5	2635	8	591.71	OCUPADA	3	Aenean fermentum.
136	1	2	1336	3	683.21	OCUPADA	6	In sagittis dui vel nisl. Duis ac nibh.
140	2	9	3040	10	368.56	OCUPADA	10	Pellentesque at nulla. Suspendisse potenti.
141	3	1	3241	7	721.16	MANTENIMIENTO	4	Integer a nibh.
146	1	7	1846	4	345.42	OCUPADA	5	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
150	2	1	2250	7	636.72	OCUPADA	3	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
154	3	8	3954	1	178.37	MANTENIMIENTO	1	In quis justo. Maecenas rhoncus aliquam lacus.
155	3	5	3655	8	325.68	MANTENIMIENTO	9	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
160	2	7	2860	5	670.90	MANTENIMIENTO	8	Suspendisse potenti. In eleifend quam a odio.
163	3	7	3863	5	137.68	OCUPADA	5	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
164	1	8	1964	1	218.33	DISPONIBLE	2	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
165	1	9	2065	4	144.18	DISPONIBLE	8	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
169	2	8	2969	10	501.78	OCUPADA	8	Duis mattis egestas metus. Aenean fermentum.
172	1	3	1472	8	352.56	MANTENIMIENTO	5	Etiam pretium iaculis justo.
173	3	5	3673	3	359.61	DISPONIBLE	4	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa. Donec dapibus.
174	2	7	2874	4	360.77	DISPONIBLE	8	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
177	3	4	3577	1	371.73	MANTENIMIENTO	9	In eleifend quam a odio. In hac habitasse platea dictumst.
186	2	1	2286	1	245.46	DISPONIBLE	6	Phasellus sit amet erat. Nulla tempus.
187	2	9	3087	8	497.66	MANTENIMIENTO	9	Proin eu mi. Nulla ac enim.
188	1	5	1688	2	716.18	MANTENIMIENTO	1	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
189	1	10	2189	1	132.61	MANTENIMIENTO	10	Etiam vel augue.
193	2	2	2393	4	386.17	MANTENIMIENTO	10	Nulla tellus.
198	2	9	3098	9	473.03	DISPONIBLE	6	Vestibulum sed magna at nunc commodo placerat.
200	2	2	2400	10	72.47	OCUPADA	5	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo. Pellentesque viverra pede ac diam.
205	3	7	3905	4	646.19	MANTENIMIENTO	4	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
208	3	9	4108	9	663.28	OCUPADA	2	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
210	3	3	3510	2	744.00	MANTENIMIENTO	2	Morbi quis tortor id nulla ultrices aliquet.
214	2	7	2914	3	164.66	OCUPADA	4	Donec posuere metus vitae ipsum. Aliquam non mauris.
216	2	9	3116	6	492.07	DISPONIBLE	4	Duis aliquam convallis nunc. Proin at turpis a pede posuere nonummy.
217	1	9	2117	1	108.07	OCUPADA	1	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci. Nullam molestie nibh in lectus.
222	2	1	2322	3	365.52	OCUPADA	6	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
230	2	10	3230	10	436.79	DISPONIBLE	1	Donec quis orci eget orci vehicula condimentum. Curabitur in libero ut massa volutpat convallis.
235	2	9	3135	9	520.98	DISPONIBLE	6	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Vivamus vestibulum sagittis sapien.
245	3	6	3845	4	340.23	OCUPADA	4	Phasellus in felis. Donec semper sapien a libero.
246	3	4	3646	2	351.19	MANTENIMIENTO	9	Donec ut dolor.
247	3	9	4147	2	389.36	OCUPADA	9	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
250	2	1	2350	6	484.54	DISPONIBLE	5	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
252	3	7	3952	10	110.27	DISPONIBLE	9	Ut at dolor quis odio consequat varius. Integer ac leo.
255	2	3	2555	3	350.76	OCUPADA	5	Vivamus vestibulum sagittis sapien.
259	3	7	3959	6	393.72	DISPONIBLE	9	Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat.
264	2	8	3064	7	440.84	MANTENIMIENTO	7	Quisque ut erat.
266	2	3	2566	10	104.40	DISPONIBLE	1	In hac habitasse platea dictumst. Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
272	2	5	2772	4	114.05	DISPONIBLE	4	Mauris ullamcorper purus sit amet nulla.
273	3	4	3673	8	411.81	OCUPADA	2	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
286	3	3	3586	6	121.19	MANTENIMIENTO	7	Aenean lectus.
291	2	2	2491	4	478.17	MANTENIMIENTO	9	In est risus, auctor sed, tristique in, tempus sit amet, sem.
299	2	10	3299	8	723.50	OCUPADA	9	Integer ac neque.
305	1	6	1905	5	84.70	DISPONIBLE	9	Cras non velit nec nisi vulputate nonummy. Maecenas tincidunt lacus at velit.
306	3	4	3706	10	195.75	DISPONIBLE	1	Curabitur in libero ut massa volutpat convallis.
309	3	3	3609	5	302.02	OCUPADA	6	In hac habitasse platea dictumst.
311	2	2	2511	8	255.02	DISPONIBLE	5	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
313	1	5	1813	4	387.22	DISPONIBLE	8	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
318	2	7	3018	9	498.46	OCUPADA	10	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
319	2	8	3119	4	643.02	DISPONIBLE	6	Nulla facilisi.
320	3	7	4020	9	462.94	DISPONIBLE	2	Nullam sit amet turpis elementum ligula vehicula consequat.
324	1	7	2024	2	295.71	DISPONIBLE	4	Nulla mollis molestie lorem.
327	3	2	3527	8	380.40	MANTENIMIENTO	2	Fusce posuere felis sed lacus.
330	3	9	4230	6	708.92	OCUPADA	6	Phasellus in felis. Donec semper sapien a libero.
331	1	2	1531	3	116.86	DISPONIBLE	2	Donec dapibus.
332	3	5	3832	9	470.38	DISPONIBLE	8	Nam tristique tortor eu pede.
335	2	10	3335	10	288.30	MANTENIMIENTO	3	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
340	1	1	1440	7	257.22	DISPONIBLE	2	Nunc rhoncus dui vel sem.
342	2	1	2442	4	740.68	DISPONIBLE	1	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
346	2	9	3246	7	266.96	MANTENIMIENTO	9	Etiam pretium iaculis justo.
350	3	4	3750	7	346.83	DISPONIBLE	4	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
357	3	7	4057	8	380.54	OCUPADA	6	Etiam faucibus cursus urna.
361	2	8	3161	10	487.63	DISPONIBLE	2	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
362	2	6	2962	6	237.34	OCUPADA	2	Quisque id justo sit amet sapien dignissim vestibulum.
411	1	4	1811	10	100.00	DISPONIBLE	1	Pellentesque ultrices mattis odio.
365	2	7	3065	3	303.41	DISPONIBLE	6	Nullam porttitor lacus at turpis.
366	2	8	3166	3	692.51	MANTENIMIENTO	8	In blandit ultrices enim.
370	2	8	3170	4	296.44	DISPONIBLE	4	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
372	2	6	2972	8	629.80	DISPONIBLE	3	Aliquam erat volutpat. In congue.
379	3	8	4179	8	566.82	OCUPADA	7	Donec ut mauris eget massa tempor convallis.
381	2	10	3381	1	722.46	OCUPADA	4	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus.
384	1	8	2184	5	90.72	MANTENIMIENTO	6	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
385	1	2	1585	9	727.60	DISPONIBLE	4	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
386	2	3	2686	2	130.32	DISPONIBLE	2	In sagittis dui vel nisl.
394	2	5	2894	1	246.59	OCUPADA	2	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
398	2	9	3298	3	331.64	OCUPADA	7	In congue.
399	2	1	2499	10	470.14	OCUPADA	9	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
401	2	5	2901	6	448.34	MANTENIMIENTO	7	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi. Integer ac neque.
406	1	6	2006	3	611.37	DISPONIBLE	9	Nulla nisl. Nunc nisl.
407	1	6	2007	6	119.20	MANTENIMIENTO	9	Vestibulum rutrum rutrum neque.
410	2	6	3010	1	642.90	OCUPADA	6	Aenean sit amet justo.
415	2	2	2615	8	90.44	DISPONIBLE	10	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
392	3	8	5192	1	228.05	OCUPADA	8	Vivamus tortor.
417	2	6	3017	5	722.55	MANTENIMIENTO	4	Nulla suscipit ligula in lacus. Curabitur at ipsum ac tellus semper interdum.
418	2	10	3418	1	700.87	MANTENIMIENTO	8	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
430	3	10	4430	5	504.08	MANTENIMIENTO	10	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
431	1	7	2131	2	505.81	DISPONIBLE	5	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
436	2	7	3136	7	345.50	MANTENIMIENTO	4	Proin at turpis a pede posuere nonummy.
443	2	6	3043	10	422.58	OCUPADA	10	Suspendisse potenti.
447	1	2	1647	5	615.61	DISPONIBLE	4	Nullam porttitor lacus at turpis.
449	3	8	4249	1	591.31	MANTENIMIENTO	3	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin interdum mauris non ligula pellentesque ultrices.
451	2	5	2951	5	319.04	OCUPADA	9	Praesent blandit.
453	1	7	2153	8	609.89	MANTENIMIENTO	8	Aenean lectus. Pellentesque eget nunc.
458	2	5	2958	6	190.91	MANTENIMIENTO	4	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
465	3	9	4365	4	436.90	MANTENIMIENTO	3	Suspendisse accumsan tortor quis turpis.
469	1	6	2069	8	516.27	MANTENIMIENTO	5	Aliquam non mauris. Morbi non lectus.
523	3	4	3923	6	96.00	MANTENIMIENTO	6	Donec vitae nisi.
474	1	5	1974	5	307.04	OCUPADA	3	Integer ac neque. Duis bibendum.
476	2	7	3176	10	50.94	OCUPADA	5	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
477	3	5	3977	1	324.65	OCUPADA	10	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
478	3	9	4378	6	621.08	MANTENIMIENTO	7	Nullam molestie nibh in lectus. Pellentesque at nulla.
480	1	7	2180	4	514.60	OCUPADA	6	Aliquam non mauris. Morbi non lectus.
488	3	1	3588	8	532.94	MANTENIMIENTO	3	Proin leo odio, porttitor id, consequat in, consequat ut, nulla. Sed accumsan felis.
492	2	9	3392	2	625.07	DISPONIBLE	8	Nulla tellus.
494	3	2	3694	1	739.72	DISPONIBLE	8	Donec vitae nisi.
495	1	1	1595	2	697.61	OCUPADA	6	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
500	3	10	4500	4	406.33	OCUPADA	8	Fusce consequat.
501	3	4	3901	5	450.62	MANTENIMIENTO	5	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
502	2	8	3302	4	424.58	MANTENIMIENTO	1	Nulla tempus. Vivamus in felis eu sapien cursus vestibulum.
504	2	8	3304	8	605.78	DISPONIBLE	2	Proin risus.
508	1	4	1908	8	135.57	OCUPADA	3	Morbi a ipsum.
519	3	5	4019	6	268.87	DISPONIBLE	9	Integer ac leo.
527	2	5	3027	2	89.36	MANTENIMIENTO	3	Sed ante.
532	3	1	3632	6	67.00	MANTENIMIENTO	9	Vivamus tortor.
536	3	3	3836	1	676.69	OCUPADA	2	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
541	1	6	2141	2	724.27	DISPONIBLE	8	Nullam molestie nibh in lectus. Pellentesque at nulla.
545	1	9	2445	3	300.83	MANTENIMIENTO	9	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh. Quisque id justo sit amet sapien dignissim vestibulum.
547	3	9	4447	6	612.81	DISPONIBLE	3	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
548	1	2	1748	6	558.73	OCUPADA	1	Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
551	3	2	3751	1	629.52	OCUPADA	10	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
554	3	3	3854	5	635.52	MANTENIMIENTO	7	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
557	3	2	3757	7	459.07	DISPONIBLE	5	Nulla mollis molestie lorem. Quisque ut erat.
560	3	8	4360	10	709.17	MANTENIMIENTO	2	Curabitur convallis.
565	3	10	4565	4	502.15	MANTENIMIENTO	10	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
566	3	6	4166	2	438.51	DISPONIBLE	4	Pellentesque at nulla.
568	3	6	4168	3	439.64	DISPONIBLE	9	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
573	2	6	3173	8	516.50	MANTENIMIENTO	4	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
575	3	2	3775	6	656.50	DISPONIBLE	10	Nulla ut erat id mauris vulputate elementum.
579	2	5	3079	4	280.17	OCUPADA	6	Vestibulum sed magna at nunc commodo placerat.
582	1	6	2182	9	437.06	DISPONIBLE	2	Nunc purus. Phasellus in felis.
531	1	1	6631	2	396.51	OCUPADA	10	Donec dapibus.
586	2	4	2986	6	682.91	MANTENIMIENTO	1	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa.
597	2	9	3497	2	594.17	DISPONIBLE	2	Maecenas pulvinar lobortis est. Phasellus sit amet erat.
608	3	6	4208	5	392.54	DISPONIBLE	9	Phasellus in felis. Donec semper sapien a libero.
616	3	7	4316	4	236.43	DISPONIBLE	5	Vestibulum rutrum rutrum neque. Aenean auctor gravida sem.
618	2	1	2718	7	569.88	DISPONIBLE	2	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
630	2	2	2830	3	53.32	DISPONIBLE	9	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
631	3	10	4631	1	120.53	OCUPADA	7	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
632	3	2	3832	5	636.85	DISPONIBLE	5	Integer tincidunt ante vel ipsum.
612	1	6	8212	8	509.07	OCUPADA	5	Morbi non lectus.
636	3	8	4436	1	264.12	OCUPADA	3	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
640	1	5	2140	8	714.98	MANTENIMIENTO	5	In sagittis dui vel nisl. Duis ac nibh.
645	3	5	4145	6	705.98	OCUPADA	1	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
649	2	9	3549	9	588.24	OCUPADA	7	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
655	3	1	3755	5	566.78	OCUPADA	4	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa.
664	2	4	3064	4	639.25	OCUPADA	10	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
668	1	10	2668	8	674.04	DISPONIBLE	2	Aenean sit amet justo.
669	2	8	3469	3	683.27	MANTENIMIENTO	4	In quis justo.
673	2	9	3573	3	254.28	MANTENIMIENTO	4	Proin at turpis a pede posuere nonummy. Integer non velit.
676	3	10	4676	1	450.93	MANTENIMIENTO	1	Donec posuere metus vitae ipsum.
678	1	5	2178	4	441.29	MANTENIMIENTO	4	Proin risus. Praesent lectus.
680	3	3	3980	7	515.27	DISPONIBLE	1	Nunc purus. Phasellus in felis.
681	3	3	3981	6	145.90	DISPONIBLE	9	Praesent lectus.
683	2	4	3083	4	185.06	DISPONIBLE	8	Fusce posuere felis sed lacus.
685	2	5	3185	3	415.64	DISPONIBLE	9	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
687	2	10	3687	1	495.09	DISPONIBLE	4	Pellentesque viverra pede ac diam.
698	3	8	4498	10	72.00	DISPONIBLE	9	Pellentesque eget nunc.
695	2	3	2995	5	587.28	OCUPADA	5	Suspendisse potenti.
697	3	8	4497	2	93.81	DISPONIBLE	1	Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis. Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci.
699	2	2	2899	8	351.55	OCUPADA	8	Proin eu mi. Nulla ac enim.
703	2	2	2903	4	181.91	DISPONIBLE	4	Suspendisse accumsan tortor quis turpis.
705	3	1	3805	4	265.84	OCUPADA	2	In hac habitasse platea dictumst. Maecenas ut massa quis augue luctus tincidunt.
709	1	6	2309	2	328.67	OCUPADA	6	Proin at turpis a pede posuere nonummy.
713	2	5	3213	7	503.31	DISPONIBLE	9	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
721	3	3	4021	7	249.06	MANTENIMIENTO	7	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
722	3	5	4222	2	55.34	MANTENIMIENTO	7	Nullam porttitor lacus at turpis.
726	2	9	3626	1	713.22	DISPONIBLE	5	Pellentesque ultrices mattis odio.
729	2	1	2829	10	696.78	MANTENIMIENTO	4	Praesent id massa id nisl venenatis lacinia.
730	3	2	3930	7	135.86	OCUPADA	8	Praesent id massa id nisl venenatis lacinia.
732	3	8	4532	2	604.33	OCUPADA	6	Curabitur in libero ut massa volutpat convallis. Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
737	2	2	2937	6	502.21	OCUPADA	4	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
739	2	7	3439	2	376.80	DISPONIBLE	5	Donec vitae nisi.
744	2	4	3144	1	374.12	DISPONIBLE	1	Suspendisse potenti.
746	2	4	3146	8	74.56	DISPONIBLE	7	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
747	3	6	4347	8	432.53	MANTENIMIENTO	9	Ut at dolor quis odio consequat varius. Integer ac leo.
748	3	7	4448	9	285.68	DISPONIBLE	3	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
766	3	10	4766	5	135.00	MANTENIMIENTO	7	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
752	2	2	2952	7	201.36	DISPONIBLE	5	Praesent blandit lacinia erat.
754	1	6	2354	10	277.72	MANTENIMIENTO	9	Fusce consequat. Nulla nisl.
757	3	4	4157	6	746.48	DISPONIBLE	8	Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue. Aliquam erat volutpat.
758	2	1	2858	5	124.29	DISPONIBLE	1	Duis aliquam convallis nunc.
759	2	4	3159	5	596.67	MANTENIMIENTO	9	Morbi quis tortor id nulla ultrices aliquet.
763	1	9	2663	8	677.27	DISPONIBLE	8	Etiam justo.
764	3	5	4264	6	360.52	MANTENIMIENTO	5	Proin interdum mauris non ligula pellentesque ultrices.
765	2	5	3265	1	518.33	OCUPADA	9	Integer ac neque. Duis bibendum.
769	2	10	3769	3	493.83	MANTENIMIENTO	7	Aliquam quis turpis eget elit sodales scelerisque. Mauris sit amet eros.
770	3	1	3870	5	427.18	MANTENIMIENTO	9	Vivamus vel nulla eget eros elementum pellentesque.
774	2	3	3074	6	573.87	OCUPADA	10	Aenean lectus.
780	1	7	2480	7	620.02	DISPONIBLE	7	Sed ante. Vivamus tortor.
784	1	9	2684	10	472.57	MANTENIMIENTO	5	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
785	3	2	3985	6	339.08	OCUPADA	10	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo.
787	2	5	3287	9	318.30	MANTENIMIENTO	4	Donec semper sapien a libero. Nam dui.
790	3	5	4290	8	591.60	DISPONIBLE	10	Proin interdum mauris non ligula pellentesque ultrices.
796	1	4	2196	1	612.61	DISPONIBLE	1	Phasellus id sapien in sapien iaculis congue. Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
799	2	9	3699	9	536.00	MANTENIMIENTO	10	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo. In blandit ultrices enim.
801	2	6	3401	10	370.76	MANTENIMIENTO	6	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl. Nunc rhoncus dui vel sem.
802	2	5	3302	3	685.03	OCUPADA	2	Sed vel enim sit amet nunc viverra dapibus.
803	2	6	3403	4	623.92	DISPONIBLE	1	Integer tincidunt ante vel ipsum. Praesent blandit lacinia erat.
809	3	9	4709	10	377.14	MANTENIMIENTO	1	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
820	3	7	4520	4	148.49	DISPONIBLE	1	Praesent id massa id nisl venenatis lacinia. Aenean sit amet justo.
821	1	1	1921	9	145.94	DISPONIBLE	9	Integer ac neque.
823	3	2	4023	1	736.11	DISPONIBLE	2	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
824	2	9	3724	3	109.37	MANTENIMIENTO	2	Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus.
828	3	7	4528	8	221.35	MANTENIMIENTO	9	Vestibulum rutrum rutrum neque.
831	2	7	3531	6	749.82	MANTENIMIENTO	4	Etiam pretium iaculis justo.
834	3	4	4234	4	494.96	MANTENIMIENTO	3	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
838	3	4	4238	5	151.76	MANTENIMIENTO	4	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
839	3	5	4339	3	382.78	DISPONIBLE	8	Maecenas rhoncus aliquam lacus. Morbi quis tortor id nulla ultrices aliquet.
841	2	5	3341	4	733.60	DISPONIBLE	3	Praesent id massa id nisl venenatis lacinia.
844	3	3	4144	6	533.38	DISPONIBLE	2	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
850	1	2	2050	7	685.74	MANTENIMIENTO	1	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
851	2	5	3351	9	732.58	MANTENIMIENTO	3	Integer ac leo.
853	2	6	3453	6	261.76	DISPONIBLE	10	Morbi porttitor lorem id ligula.
855	3	4	4255	6	662.34	MANTENIMIENTO	9	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
862	2	7	3562	1	169.52	OCUPADA	8	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
866	2	2	3066	9	721.16	OCUPADA	9	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
534	1	8	9334	1	495.41	OCUPADA	9	Morbi non lectus. Aliquam sit amet diam in magna bibendum imperdiet.
867	3	3	4167	3	505.30	OCUPADA	10	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est.
871	3	7	4571	2	247.31	OCUPADA	8	Praesent blandit.
872	3	3	4172	8	592.91	MANTENIMIENTO	10	Duis consequat dui nec nisi volutpat eleifend. Donec ut dolor.
874	3	3	4174	1	691.42	OCUPADA	1	Integer ac neque. Duis bibendum.
875	3	3	4175	9	503.29	MANTENIMIENTO	5	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
879	3	5	4379	8	212.29	DISPONIBLE	8	In congue.
882	2	4	3282	1	100.91	DISPONIBLE	3	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero.
885	3	8	4685	5	188.47	OCUPADA	1	Nullam molestie nibh in lectus. Pellentesque at nulla.
886	1	9	2786	8	117.19	DISPONIBLE	5	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem. Duis aliquam convallis nunc.
891	2	7	3591	8	93.75	MANTENIMIENTO	4	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
894	3	10	4894	3	727.98	MANTENIMIENTO	3	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
903	2	7	3603	6	588.47	MANTENIMIENTO	3	Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
911	2	1	3011	9	331.18	OCUPADA	4	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
912	2	3	3212	10	416.87	DISPONIBLE	5	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
915	3	4	4315	2	628.76	MANTENIMIENTO	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est. Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros.
924	3	6	4524	3	674.40	DISPONIBLE	6	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
925	3	8	4725	6	196.19	OCUPADA	2	Donec vitae nisi. Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
926	2	9	3826	1	91.80	MANTENIMIENTO	7	Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
928	2	8	3728	1	685.35	OCUPADA	4	Nulla suscipit ligula in lacus. Curabitur at ipsum ac tellus semper interdum.
936	2	1	3036	7	496.00	MANTENIMIENTO	10	Duis bibendum. Morbi non quam nec dui luctus rutrum.
937	3	6	4537	7	162.18	MANTENIMIENTO	2	Quisque porta volutpat erat. Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
942	3	7	4642	2	111.90	OCUPADA	2	In est risus, auctor sed, tristique in, tempus sit amet, sem.
945	1	6	2545	2	633.28	OCUPADA	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
947	1	5	2447	3	92.74	DISPONIBLE	3	Maecenas ut massa quis augue luctus tincidunt. Nulla mollis molestie lorem.
949	3	10	4949	9	260.92	DISPONIBLE	7	Aliquam quis turpis eget elit sodales scelerisque.
962	3	7	4662	3	86.10	MANTENIMIENTO	1	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
964	3	9	4864	10	530.92	OCUPADA	10	Cras in purus eu magna vulputate luctus.
967	2	5	3467	4	359.01	OCUPADA	3	In congue.
956	3	1	5056	3	472.96	DISPONIBLE	5	Suspendisse ornare consequat lectus.
957	1	6	7557	7	331.65	DISPONIBLE	10	Integer non velit. Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
958	2	2	9158	4	656.89	DISPONIBLE	6	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
959	3	9	9859	5	120.73	OCUPADA	1	Duis mattis egestas metus.
960	1	3	5260	5	616.71	MANTENIMIENTO	9	Nulla facilisi. Cras non velit nec nisi vulputate nonummy.
961	2	3	5261	9	60.05	MANTENIMIENTO	1	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
963	1	9	10863	10	665.52	DISPONIBLE	5	Nulla justo.
965	3	10	8965	10	507.39	MANTENIMIENTO	10	Curabitur in libero ut massa volutpat convallis.
966	1	2	5166	3	396.83	MANTENIMIENTO	3	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
968	3	6	6568	7	270.93	DISPONIBLE	3	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus.
969	1	3	6269	1	550.03	OCUPADA	7	Morbi non quam nec dui luctus rutrum. Nulla tellus.
970	2	8	5770	6	126.46	DISPONIBLE	9	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
971	3	10	9971	4	637.19	MANTENIMIENTO	2	Proin at turpis a pede posuere nonummy.
972	1	4	5372	3	505.02	DISPONIBLE	4	In eleifend quam a odio.
973	2	6	6573	9	111.26	DISPONIBLE	9	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
974	3	4	9374	7	67.44	DISPONIBLE	9	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
975	1	5	5475	8	223.42	OCUPADA	6	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa. Donec dapibus.
976	2	4	8376	8	192.66	MANTENIMIENTO	8	Nulla mollis molestie lorem.
1	2	3	4301	6	79.74	MANTENIMIENTO	4	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
2	3	6	4602	3	537.13	OCUPADA	3	Duis at velit eu est congue elementum. In hac habitasse platea dictumst.
3	1	9	9903	4	690.70	OCUPADA	1	In hac habitasse platea dictumst. Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
4	2	6	6604	9	371.35	MANTENIMIENTO	7	In eleifend quam a odio. In hac habitasse platea dictumst.
5	3	9	8905	8	73.87	OCUPADA	10	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
6	1	7	8706	9	649.71	MANTENIMIENTO	6	In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
7	2	2	7207	2	600.42	MANTENIMIENTO	7	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
8	3	3	4308	4	378.19	OCUPADA	1	Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
10	2	7	4710	6	521.07	OCUPADA	3	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
11	3	2	9211	2	658.48	MANTENIMIENTO	5	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem. Integer tincidunt ante vel ipsum.
12	1	8	4812	1	246.90	MANTENIMIENTO	3	Integer non velit.
14	3	6	6614	9	285.02	DISPONIBLE	7	Pellentesque ultrices mattis odio. Donec vitae nisi.
15	1	2	6215	7	418.03	MANTENIMIENTO	4	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
16	2	1	6116	8	283.98	MANTENIMIENTO	4	Maecenas ut massa quis augue luctus tincidunt. Nulla mollis molestie lorem.
17	3	9	6917	5	439.08	DISPONIBLE	5	Phasellus sit amet erat. Nulla tempus.
18	1	8	8818	3	518.29	MANTENIMIENTO	8	Proin interdum mauris non ligula pellentesque ultrices.
19	2	3	6319	10	593.18	OCUPADA	10	Vestibulum ac est lacinia nisi venenatis tristique.
21	1	1	5121	10	304.71	OCUPADA	6	Vivamus vestibulum sagittis sapien.
23	3	8	8823	3	394.30	OCUPADA	4	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
24	1	4	6424	9	661.38	OCUPADA	4	Duis bibendum. Morbi non quam nec dui luctus rutrum.
25	2	5	6525	3	389.85	OCUPADA	3	Morbi quis tortor id nulla ultrices aliquet. Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
26	3	10	5026	6	661.38	OCUPADA	8	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
27	1	6	5627	6	320.23	DISPONIBLE	4	Duis at velit eu est congue elementum.
28	2	5	5528	5	388.56	OCUPADA	3	In sagittis dui vel nisl. Duis ac nibh.
29	3	6	9629	8	626.28	OCUPADA	8	Proin interdum mauris non ligula pellentesque ultrices.
30	1	10	5030	9	562.56	OCUPADA	9	Nullam sit amet turpis elementum ligula vehicula consequat.
32	3	10	6032	9	331.15	OCUPADA	3	Morbi non quam nec dui luctus rutrum. Nulla tellus.
34	2	1	4134	5	437.28	MANTENIMIENTO	1	Mauris sit amet eros.
35	3	7	9735	4	398.25	DISPONIBLE	1	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
36	1	4	8436	6	223.95	OCUPADA	10	In hac habitasse platea dictumst.
39	1	6	6639	3	296.32	OCUPADA	9	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
40	2	1	6140	2	574.34	OCUPADA	3	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
41	3	2	5241	10	377.01	OCUPADA	9	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
42	1	2	10242	4	266.91	OCUPADA	8	Donec posuere metus vitae ipsum.
43	2	7	5743	4	340.75	DISPONIBLE	2	In quis justo.
45	1	6	6645	4	732.84	MANTENIMIENTO	4	Nullam varius.
48	1	7	6748	6	429.21	MANTENIMIENTO	9	Morbi quis tortor id nulla ultrices aliquet.
49	2	5	8549	8	451.40	DISPONIBLE	8	Nam dui.
688	2	10	6688	8	520.26	MANTENIMIENTO	1	In hac habitasse platea dictumst.
50	3	6	4650	6	386.66	OCUPADA	8	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
52	2	1	6152	2	292.11	DISPONIBLE	2	Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus. Suspendisse potenti.
54	1	8	6854	2	465.67	DISPONIBLE	4	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
55	2	2	7255	6	694.16	OCUPADA	7	Curabitur at ipsum ac tellus semper interdum.
56	3	10	6056	6	423.58	OCUPADA	4	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
57	1	5	6557	7	683.50	DISPONIBLE	2	In eleifend quam a odio. In hac habitasse platea dictumst.
58	2	6	4658	9	641.36	MANTENIMIENTO	1	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
59	3	10	5059	3	664.19	OCUPADA	3	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
60	1	5	7560	8	634.68	OCUPADA	3	In eleifend quam a odio.
61	2	2	4261	3	269.40	OCUPADA	5	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
62	3	7	5762	2	551.42	MANTENIMIENTO	5	In quis justo. Maecenas rhoncus aliquam lacus.
66	1	8	10866	7	86.36	MANTENIMIENTO	1	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
67	2	7	8767	3	410.71	DISPONIBLE	1	Nullam varius. Nulla facilisi.
68	3	3	4368	8	148.87	DISPONIBLE	4	Nam dui. Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
69	1	9	4969	6	372.17	MANTENIMIENTO	7	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa. Donec dapibus.
535	2	2	5735	2	734.51	DISPONIBLE	6	Ut tellus.
70	2	3	6370	10	170.26	OCUPADA	9	Integer tincidunt ante vel ipsum.
71	3	3	4371	1	615.09	DISPONIBLE	5	In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
73	2	8	4873	1	532.31	DISPONIBLE	5	Praesent blandit. Nam nulla.
74	3	8	4874	8	182.00	DISPONIBLE	10	Duis bibendum.
75	1	9	4975	9	420.68	DISPONIBLE	9	Duis bibendum.
76	2	4	6476	9	398.68	OCUPADA	1	Nulla facilisi. Cras non velit nec nisi vulputate nonummy.
79	2	7	4779	10	162.34	OCUPADA	2	Aliquam sit amet diam in magna bibendum imperdiet.
81	1	10	8081	1	439.03	DISPONIBLE	3	Cras pellentesque volutpat dui.
83	3	6	4683	3	211.00	OCUPADA	8	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl. Nunc rhoncus dui vel sem.
84	1	8	7884	8	415.07	DISPONIBLE	9	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
85	2	9	5985	2	204.31	DISPONIBLE	7	Suspendisse potenti. Nullam porttitor lacus at turpis.
86	3	7	8786	10	640.47	OCUPADA	2	Praesent blandit lacinia erat.
87	1	1	6187	1	530.83	OCUPADA	7	Quisque porta volutpat erat. Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
88	2	6	8688	2	402.67	MANTENIMIENTO	10	Pellentesque ultrices mattis odio.
91	2	3	10391	7	200.65	DISPONIBLE	3	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
93	1	10	7093	7	717.83	MANTENIMIENTO	10	Nulla ac enim.
94	2	8	7894	8	496.05	OCUPADA	10	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
96	1	2	7296	6	141.49	OCUPADA	8	Maecenas ut massa quis augue luctus tincidunt.
97	2	4	5497	2	316.30	DISPONIBLE	1	Duis consequat dui nec nisi volutpat eleifend.
98	3	9	5998	10	535.51	DISPONIBLE	1	In hac habitasse platea dictumst. Maecenas ut massa quis augue luctus tincidunt.
99	1	7	4799	4	221.85	OCUPADA	1	In eleifend quam a odio. In hac habitasse platea dictumst.
100	2	9	10000	5	313.60	OCUPADA	9	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo.
102	1	2	7302	10	90.98	OCUPADA	9	Morbi non quam nec dui luctus rutrum. Nulla tellus.
103	2	8	5903	8	618.46	OCUPADA	4	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo. Maecenas pulvinar lobortis est.
104	3	10	5104	9	139.19	OCUPADA	10	Integer tincidunt ante vel ipsum. Praesent blandit lacinia erat.
106	2	9	6006	7	552.66	OCUPADA	3	In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
107	3	6	9707	9	599.50	OCUPADA	3	Nulla ac enim. In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
110	3	9	6010	9	288.54	MANTENIMIENTO	9	Proin risus. Praesent lectus.
111	1	10	5111	4	234.07	MANTENIMIENTO	9	Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
112	2	6	5712	10	210.33	DISPONIBLE	4	Curabitur convallis.
113	3	10	5113	3	181.85	MANTENIMIENTO	2	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo. In blandit ultrices enim.
114	1	9	6014	2	399.47	OCUPADA	9	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
116	3	3	8416	2	653.66	OCUPADA	7	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero.
117	1	3	8417	2	706.43	DISPONIBLE	2	Proin eu mi. Nulla ac enim.
119	3	2	5319	4	84.73	MANTENIMIENTO	3	Curabitur in libero ut massa volutpat convallis.
121	2	6	4721	8	694.55	DISPONIBLE	4	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
122	3	1	5222	6	243.59	DISPONIBLE	10	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
124	2	10	11124	3	475.84	OCUPADA	1	Donec vitae nisi. Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
125	3	7	8825	3	236.50	OCUPADA	5	Proin risus. Praesent lectus.
126	1	2	5326	4	295.04	DISPONIBLE	3	Maecenas pulvinar lobortis est.
128	3	4	6528	9	386.61	MANTENIMIENTO	5	Duis consequat dui nec nisi volutpat eleifend.
131	3	6	6731	2	529.45	MANTENIMIENTO	10	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
132	1	4	4532	3	80.59	MANTENIMIENTO	1	Duis mattis egestas metus. Aenean fermentum.
137	3	5	6637	2	584.05	OCUPADA	10	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus.
138	1	8	5938	9	585.64	DISPONIBLE	7	Duis consequat dui nec nisi volutpat eleifend. Donec ut dolor.
139	2	2	9339	6	494.99	DISPONIBLE	8	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
142	2	8	4942	2	254.86	OCUPADA	10	Donec vitae nisi.
819	1	7	10519	3	520.55	OCUPADA	10	Donec vitae nisi.
143	3	7	5843	10	698.70	OCUPADA	8	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
144	1	2	6344	4	524.45	OCUPADA	9	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci.
145	2	4	6545	3	475.37	MANTENIMIENTO	1	Proin interdum mauris non ligula pellentesque ultrices.
147	1	3	10447	8	281.19	DISPONIBLE	7	Ut at dolor quis odio consequat varius. Integer ac leo.
148	2	9	7048	7	496.18	DISPONIBLE	10	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
149	3	6	8749	4	647.78	OCUPADA	8	Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
151	2	4	7551	6	110.54	DISPONIBLE	7	Vestibulum ac est lacinia nisi venenatis tristique. Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue.
152	3	5	8652	7	245.81	OCUPADA	6	In est risus, auctor sed, tristique in, tempus sit amet, sem.
153	1	1	4253	8	278.58	OCUPADA	9	Quisque porta volutpat erat. Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
156	1	6	7756	10	680.09	MANTENIMIENTO	8	Proin at turpis a pede posuere nonummy.
157	2	9	5057	3	734.49	MANTENIMIENTO	8	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
158	3	10	11158	8	349.77	OCUPADA	2	Morbi vel lectus in quam fringilla rhoncus.
159	1	7	5859	9	338.27	MANTENIMIENTO	1	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero.
161	3	6	10761	8	690.47	DISPONIBLE	5	Phasellus sit amet erat.
162	1	4	6562	1	668.63	OCUPADA	8	Morbi quis tortor id nulla ultrices aliquet. Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
167	3	4	8567	6	323.98	DISPONIBLE	7	Nunc nisl.
168	1	2	4368	9	717.95	MANTENIMIENTO	3	Donec dapibus. Duis at velit eu est congue elementum.
170	3	4	4570	1	604.38	MANTENIMIENTO	7	Nunc rhoncus dui vel sem.
171	1	7	5871	7	53.19	OCUPADA	4	Donec quis orci eget orci vehicula condimentum. Curabitur in libero ut massa volutpat convallis.
175	2	6	8775	5	193.43	MANTENIMIENTO	2	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
176	3	7	4876	3	383.65	MANTENIMIENTO	10	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
178	2	5	6678	1	353.55	OCUPADA	2	Proin risus. Praesent lectus.
179	3	1	5279	2	514.90	DISPONIBLE	3	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
180	1	10	9180	10	580.66	DISPONIBLE	4	In quis justo. Maecenas rhoncus aliquam lacus.
181	2	1	9281	4	655.55	OCUPADA	10	Pellentesque ultrices mattis odio. Donec vitae nisi.
182	3	2	6382	8	500.86	OCUPADA	4	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
183	1	2	4383	10	135.47	DISPONIBLE	6	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
184	2	8	5984	10	429.03	MANTENIMIENTO	5	Maecenas pulvinar lobortis est. Phasellus sit amet erat.
185	3	9	7085	1	156.67	OCUPADA	4	Donec vitae nisi. Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
190	2	3	4490	8	572.13	OCUPADA	2	Cras in purus eu magna vulputate luctus.
191	3	7	8891	9	554.32	MANTENIMIENTO	2	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
192	1	8	4992	3	412.26	OCUPADA	9	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo. Maecenas pulvinar lobortis est.
194	3	9	7094	4	362.59	OCUPADA	8	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
195	1	6	6795	10	310.50	OCUPADA	2	Nulla mollis molestie lorem.
196	2	2	6396	4	568.09	MANTENIMIENTO	9	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus.
197	3	6	6797	1	215.98	DISPONIBLE	2	Vivamus in felis eu sapien cursus vestibulum.
199	2	8	5999	5	700.50	DISPONIBLE	4	In hac habitasse platea dictumst. Maecenas ut massa quis augue luctus tincidunt.
201	1	1	5301	4	82.36	DISPONIBLE	3	Morbi non lectus. Aliquam sit amet diam in magna bibendum imperdiet.
202	2	7	6902	8	548.44	MANTENIMIENTO	6	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
203	3	3	4503	10	232.34	OCUPADA	7	Ut tellus. Nulla ut erat id mauris vulputate elementum.
204	1	9	8104	1	352.62	MANTENIMIENTO	4	Donec vitae nisi. Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
206	3	10	5206	3	159.50	DISPONIBLE	6	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
207	1	2	8407	3	707.09	MANTENIMIENTO	5	Donec quis orci eget orci vehicula condimentum. Curabitur in libero ut massa volutpat convallis.
209	3	4	8609	10	129.55	MANTENIMIENTO	4	Integer ac leo.
212	3	8	6012	4	616.01	MANTENIMIENTO	3	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
213	1	5	6713	8	725.17	MANTENIMIENTO	9	Nam dui.
215	3	10	10215	6	473.19	DISPONIBLE	9	Pellentesque at nulla.
218	3	3	9518	3	533.71	OCUPADA	9	Vestibulum sed magna at nunc commodo placerat.
219	1	7	8919	6	240.86	DISPONIBLE	6	Nunc purus.
220	2	1	5320	10	258.65	DISPONIBLE	3	Integer tincidunt ante vel ipsum.
221	3	9	10121	5	259.69	DISPONIBLE	1	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
223	2	2	7423	8	107.82	MANTENIMIENTO	10	Maecenas ut massa quis augue luctus tincidunt. Nulla mollis molestie lorem.
224	3	5	8724	2	93.88	MANTENIMIENTO	6	Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus.
225	1	2	5425	8	634.62	DISPONIBLE	7	Phasellus id sapien in sapien iaculis congue.
226	2	3	6526	7	734.36	OCUPADA	8	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros.
537	1	9	6437	3	700.03	DISPONIBLE	5	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
538	2	8	5338	1	411.57	OCUPADA	2	Suspendisse potenti.
227	3	6	8827	8	497.54	DISPONIBLE	3	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
229	2	3	9529	8	118.17	OCUPADA	6	Quisque porta volutpat erat.
231	1	2	6431	7	732.92	MANTENIMIENTO	1	Aenean lectus. Pellentesque eget nunc.
232	2	6	10832	5	277.02	MANTENIMIENTO	2	Nam dui. Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
233	3	5	6733	5	686.64	OCUPADA	9	Donec posuere metus vitae ipsum.
234	1	5	10734	7	271.10	OCUPADA	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
236	3	1	4336	4	668.80	MANTENIMIENTO	4	Cras pellentesque volutpat dui. Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
237	1	10	11237	6	508.66	OCUPADA	5	Phasellus id sapien in sapien iaculis congue. Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
238	2	6	6838	1	198.36	OCUPADA	8	Integer ac leo.
239	3	4	6639	2	648.95	DISPONIBLE	1	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
240	1	5	4740	1	300.52	OCUPADA	10	Nullam sit amet turpis elementum ligula vehicula consequat.
241	2	3	6541	6	218.30	MANTENIMIENTO	5	Morbi non quam nec dui luctus rutrum.
242	3	10	5242	5	401.76	DISPONIBLE	5	Mauris ullamcorper purus sit amet nulla.
243	1	2	8443	8	207.70	DISPONIBLE	2	In hac habitasse platea dictumst.
244	2	7	5944	5	563.19	MANTENIMIENTO	7	Mauris sit amet eros.
248	3	1	6348	9	137.99	DISPONIBLE	9	Quisque ut erat. Curabitur gravida nisi at nibh.
249	1	7	6949	8	142.36	DISPONIBLE	6	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
251	3	8	9051	3	207.50	DISPONIBLE	8	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
253	2	3	4553	6	517.46	MANTENIMIENTO	10	Quisque ut erat. Curabitur gravida nisi at nibh.
254	3	7	10954	5	675.20	MANTENIMIENTO	10	Donec posuere metus vitae ipsum.
256	2	1	6356	7	536.08	MANTENIMIENTO	8	Morbi non quam nec dui luctus rutrum. Nulla tellus.
257	3	1	9357	3	745.32	OCUPADA	6	Ut at dolor quis odio consequat varius. Integer ac leo.
258	1	10	7258	3	162.16	OCUPADA	9	Nunc rhoncus dui vel sem. Sed sagittis.
260	3	2	5460	7	431.26	DISPONIBLE	5	Aliquam non mauris. Morbi non lectus.
261	1	6	6861	9	99.94	DISPONIBLE	6	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
262	2	4	6662	6	82.47	OCUPADA	6	Proin leo odio, porttitor id, consequat in, consequat ut, nulla. Sed accumsan felis.
263	3	10	8263	10	53.89	DISPONIBLE	7	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est. Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros.
265	2	5	4765	9	110.51	OCUPADA	7	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
267	1	4	4667	9	710.75	OCUPADA	8	Nulla facilisi.
268	2	10	5268	6	692.95	MANTENIMIENTO	8	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
269	3	3	8569	9	621.74	OCUPADA	8	Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
270	1	5	8770	7	664.31	MANTENIMIENTO	5	Fusce consequat.
271	2	4	5671	4	714.29	MANTENIMIENTO	5	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
274	2	3	5574	8	615.79	OCUPADA	8	Maecenas ut massa quis augue luctus tincidunt. Nulla mollis molestie lorem.
275	3	7	10975	10	175.95	DISPONIBLE	4	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique.
276	1	10	9276	6	271.47	MANTENIMIENTO	8	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
277	2	3	6577	2	733.09	MANTENIMIENTO	4	Etiam justo.
278	3	5	8778	6	298.97	MANTENIMIENTO	10	Donec vitae nisi.
279	1	8	9079	3	242.22	MANTENIMIENTO	6	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
280	2	6	4880	1	575.88	DISPONIBLE	10	In eleifend quam a odio.
281	3	5	6781	9	697.75	MANTENIMIENTO	1	Aliquam quis turpis eget elit sodales scelerisque.
282	1	5	6782	1	748.15	DISPONIBLE	2	Nulla nisl. Nunc nisl.
283	2	1	5383	1	392.91	DISPONIBLE	10	Morbi quis tortor id nulla ultrices aliquet. Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
284	3	1	4384	2	385.17	MANTENIMIENTO	7	Mauris lacinia sapien quis libero.
285	1	1	9385	10	643.36	DISPONIBLE	1	Aenean lectus.
287	3	6	9887	7	595.36	MANTENIMIENTO	1	Morbi a ipsum. Integer a nibh.
289	2	9	9189	10	78.46	OCUPADA	4	Nulla mollis molestie lorem. Quisque ut erat.
290	3	5	6790	8	696.15	MANTENIMIENTO	6	Ut tellus. Nulla ut erat id mauris vulputate elementum.
292	2	5	5792	10	416.80	OCUPADA	6	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
293	3	4	5693	2	320.99	DISPONIBLE	7	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
294	1	1	9394	2	78.80	DISPONIBLE	2	In hac habitasse platea dictumst.
539	3	1	6639	10	637.82	OCUPADA	5	Aenean lectus.
295	2	9	6195	2	468.63	MANTENIMIENTO	7	In sagittis dui vel nisl.
296	3	6	5896	1	209.02	DISPONIBLE	1	Aenean auctor gravida sem. Praesent id massa id nisl venenatis lacinia.
297	1	10	6297	3	670.01	OCUPADA	10	Suspendisse potenti. In eleifend quam a odio.
298	2	8	6098	5	64.20	OCUPADA	1	Nulla nisl. Nunc nisl.
300	1	8	11100	3	247.16	DISPONIBLE	5	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
301	2	4	6701	10	508.72	MANTENIMIENTO	9	Suspendisse accumsan tortor quis turpis. Sed ante.
302	3	4	4702	4	716.11	MANTENIMIENTO	8	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
303	1	10	10303	7	707.69	DISPONIBLE	6	In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
304	2	9	9204	10	275.92	MANTENIMIENTO	9	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
307	2	3	10607	10	386.39	OCUPADA	2	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
308	3	10	11308	3	280.62	MANTENIMIENTO	6	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
310	2	1	9410	5	54.27	OCUPADA	7	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
312	1	8	10112	6	719.55	MANTENIMIENTO	8	Vestibulum rutrum rutrum neque.
314	3	6	4914	2	82.38	OCUPADA	2	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
315	1	6	4915	8	400.25	MANTENIMIENTO	1	Duis consequat dui nec nisi volutpat eleifend. Donec ut dolor.
316	2	9	7216	1	637.33	DISPONIBLE	5	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
317	3	6	9917	3	280.58	MANTENIMIENTO	5	Nulla ut erat id mauris vulputate elementum. Nullam varius.
321	1	5	5821	9	483.72	OCUPADA	6	Maecenas tincidunt lacus at velit.
322	2	5	4822	9	62.28	OCUPADA	4	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
323	3	1	5423	6	315.67	MANTENIMIENTO	3	Suspendisse potenti.
325	2	9	5225	10	262.91	MANTENIMIENTO	7	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem. Duis aliquam convallis nunc.
326	3	3	4626	1	136.95	MANTENIMIENTO	4	Praesent blandit. Nam nulla.
328	2	5	6828	7	733.05	MANTENIMIENTO	3	Nullam varius. Nulla facilisi.
329	3	8	6129	9	55.40	DISPONIBLE	7	Sed vel enim sit amet nunc viverra dapibus.
333	1	2	7533	5	589.81	MANTENIMIENTO	7	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante. Nulla justo.
334	2	10	11334	4	403.24	DISPONIBLE	4	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus.
336	1	1	5436	10	389.08	MANTENIMIENTO	1	Duis ac nibh. Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus.
337	2	8	6137	1	119.86	MANTENIMIENTO	3	Nulla justo.
338	3	10	7338	4	516.39	DISPONIBLE	10	Aliquam sit amet diam in magna bibendum imperdiet. Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
339	1	7	11039	3	105.87	OCUPADA	6	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
341	3	6	4941	10	554.35	OCUPADA	1	Phasellus sit amet erat. Nulla tempus.
343	2	8	9143	4	308.06	OCUPADA	6	Duis consequat dui nec nisi volutpat eleifend.
344	3	10	5344	9	699.86	MANTENIMIENTO	9	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
345	1	2	9545	10	597.41	OCUPADA	9	Aliquam non mauris.
347	3	3	6647	7	730.57	DISPONIBLE	1	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
348	1	6	8948	9	539.69	DISPONIBLE	3	Suspendisse potenti. In eleifend quam a odio.
349	2	8	11149	5	146.04	OCUPADA	9	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique.
351	1	6	4951	5	681.49	DISPONIBLE	8	Ut tellus. Nulla ut erat id mauris vulputate elementum.
352	2	3	6652	2	116.90	DISPONIBLE	5	Vivamus vel nulla eget eros elementum pellentesque.
353	3	6	4953	1	348.60	MANTENIMIENTO	8	Nulla mollis molestie lorem.
354	1	9	5254	10	521.22	DISPONIBLE	6	Vestibulum ac est lacinia nisi venenatis tristique.
355	2	4	4755	9	456.27	DISPONIBLE	7	Nunc nisl.
356	3	5	5856	2	73.54	OCUPADA	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
358	2	8	7158	2	96.30	DISPONIBLE	8	Proin interdum mauris non ligula pellentesque ultrices.
288	1	8	5088	9	86.00	MANTENIMIENTO	9	Maecenas pulvinar lobortis est.
359	3	1	4459	1	453.89	OCUPADA	4	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
360	1	9	9260	9	211.60	DISPONIBLE	3	Nulla tellus.
689	3	6	5289	2	140.74	OCUPADA	7	Duis at velit eu est congue elementum.
363	1	1	5463	1	661.68	DISPONIBLE	1	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi. Integer ac neque.
364	2	10	9364	4	632.07	DISPONIBLE	1	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
367	2	9	9267	6	476.20	OCUPADA	5	Nulla tellus. In sagittis dui vel nisl.
368	3	7	5068	3	682.15	OCUPADA	7	Aenean sit amet justo. Morbi ut odio.
369	1	7	7069	6	724.91	MANTENIMIENTO	8	Donec quis orci eget orci vehicula condimentum.
371	3	2	6571	1	499.20	OCUPADA	1	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
373	2	5	6873	2	291.63	OCUPADA	9	Cras non velit nec nisi vulputate nonummy. Maecenas tincidunt lacus at velit.
374	3	4	5774	3	598.06	MANTENIMIENTO	4	Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
375	1	5	7875	8	443.17	MANTENIMIENTO	9	Etiam vel augue. Vestibulum rutrum rutrum neque.
376	2	6	4976	10	224.35	MANTENIMIENTO	5	Suspendisse potenti.
377	3	5	5877	2	544.32	MANTENIMIENTO	3	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique.
378	1	1	9478	6	571.83	MANTENIMIENTO	4	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est.
380	3	9	8280	2	190.39	DISPONIBLE	8	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
382	2	10	7382	4	259.27	OCUPADA	8	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
383	3	6	5983	9	170.44	OCUPADA	9	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante. Nulla justo.
387	1	6	7987	8	460.83	OCUPADA	8	Integer tincidunt ante vel ipsum. Praesent blandit lacinia erat.
388	2	7	11088	3	309.25	MANTENIMIENTO	8	Maecenas pulvinar lobortis est.
389	3	4	6789	3	259.64	DISPONIBLE	9	Aliquam erat volutpat.
390	1	7	5090	6	398.74	OCUPADA	10	Nulla ut erat id mauris vulputate elementum.
393	1	4	8793	9	608.13	MANTENIMIENTO	2	Duis at velit eu est congue elementum. In hac habitasse platea dictumst.
395	3	8	6195	7	318.54	MANTENIMIENTO	2	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
396	1	6	7996	4	560.39	MANTENIMIENTO	10	Nulla ac enim. In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
397	2	3	10697	3	116.01	MANTENIMIENTO	3	Nullam varius.
400	2	9	7300	1	391.37	MANTENIMIENTO	5	Pellentesque eget nunc.
402	1	5	9902	6	621.00	MANTENIMIENTO	2	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
403	2	9	8303	5	200.86	DISPONIBLE	9	Aenean fermentum. Donec ut mauris eget massa tempor convallis.
404	3	2	6604	5	86.12	MANTENIMIENTO	9	Phasellus sit amet erat. Nulla tempus.
405	1	2	6605	5	578.35	OCUPADA	7	Nulla justo. Aliquam quis turpis eget elit sodales scelerisque.
408	1	7	5108	5	625.12	MANTENIMIENTO	9	Donec posuere metus vitae ipsum.
409	2	4	5809	1	655.47	DISPONIBLE	5	Proin risus.
412	2	5	8912	3	430.19	OCUPADA	2	Morbi a ipsum. Integer a nibh.
413	3	4	5813	6	737.20	MANTENIMIENTO	7	Quisque porta volutpat erat.
414	1	7	7114	3	172.92	DISPONIBLE	10	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus.
416	3	2	8616	7	105.94	DISPONIBLE	8	Quisque ut erat. Curabitur gravida nisi at nibh.
419	3	5	8919	1	366.54	OCUPADA	6	Cras pellentesque volutpat dui.
420	1	3	4720	7	373.97	MANTENIMIENTO	10	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
421	2	2	7621	2	641.40	OCUPADA	1	Aenean fermentum.
422	3	9	5322	2	280.60	DISPONIBLE	1	Aliquam quis turpis eget elit sodales scelerisque. Mauris sit amet eros.
423	1	4	6823	7	55.93	MANTENIMIENTO	1	Nulla ut erat id mauris vulputate elementum.
424	2	5	8924	5	528.46	MANTENIMIENTO	3	Duis at velit eu est congue elementum. In hac habitasse platea dictumst.
425	3	3	5725	2	563.27	DISPONIBLE	3	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
426	1	4	7826	9	271.44	MANTENIMIENTO	4	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
427	2	10	8427	1	473.23	DISPONIBLE	1	Integer a nibh. In quis justo.
428	3	7	5128	2	530.51	OCUPADA	9	Proin at turpis a pede posuere nonummy.
429	1	10	7429	4	575.66	MANTENIMIENTO	2	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
432	1	4	5832	1	240.52	OCUPADA	9	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo. Pellentesque viverra pede ac diam.
433	2	4	10833	3	355.54	MANTENIMIENTO	9	Morbi quis tortor id nulla ultrices aliquet.
434	3	7	6134	6	533.15	MANTENIMIENTO	6	Praesent blandit. Nam nulla.
435	1	9	9335	6	120.67	DISPONIBLE	8	Vestibulum sed magna at nunc commodo placerat.
437	3	10	5437	6	147.59	DISPONIBLE	5	Integer non velit.
438	1	3	6738	9	684.96	MANTENIMIENTO	2	Morbi non lectus. Aliquam sit amet diam in magna bibendum imperdiet.
439	2	10	5439	1	489.17	OCUPADA	9	Etiam justo. Etiam pretium iaculis justo.
440	3	1	4540	3	136.66	DISPONIBLE	8	Vestibulum rutrum rutrum neque. Aenean auctor gravida sem.
441	1	5	4941	8	372.95	MANTENIMIENTO	3	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin interdum mauris non ligula pellentesque ultrices.
442	2	1	6542	8	226.58	DISPONIBLE	6	Nulla justo.
444	1	2	6644	8	724.64	OCUPADA	10	Nulla ac enim. In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
445	2	1	6545	2	53.02	DISPONIBLE	3	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
446	3	6	5046	8	644.51	OCUPADA	6	Quisque ut erat.
448	2	6	7048	7	654.84	OCUPADA	2	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
450	1	6	6050	4	405.00	MANTENIMIENTO	7	Cras in purus eu magna vulputate luctus. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
452	3	8	6252	10	447.73	DISPONIBLE	4	In eleifend quam a odio. In hac habitasse platea dictumst.
454	2	7	6154	10	663.76	MANTENIMIENTO	1	Nulla facilisi.
455	3	7	8155	4	601.81	MANTENIMIENTO	8	Maecenas pulvinar lobortis est.
456	1	6	7056	3	744.84	DISPONIBLE	4	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus.
457	2	6	5057	8	253.03	DISPONIBLE	1	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
459	1	4	6859	1	182.99	MANTENIMIENTO	5	Sed accumsan felis. Ut at dolor quis odio consequat varius.
460	2	3	8760	4	506.55	DISPONIBLE	1	Suspendisse potenti.
461	3	7	5161	10	603.16	OCUPADA	6	Morbi non quam nec dui luctus rutrum. Nulla tellus.
462	1	8	7262	6	569.62	DISPONIBLE	3	Nulla tempus.
463	2	6	9063	8	665.51	MANTENIMIENTO	9	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
464	3	7	7164	10	600.28	DISPONIBLE	6	Donec quis orci eget orci vehicula condimentum.
466	2	10	10466	7	250.56	MANTENIMIENTO	7	Nullam porttitor lacus at turpis.
467	3	6	7067	1	322.79	DISPONIBLE	1	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
468	1	7	6168	5	194.03	OCUPADA	1	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
470	3	2	10670	5	212.57	OCUPADA	9	Suspendisse potenti. In eleifend quam a odio.
472	2	3	6772	4	484.28	DISPONIBLE	1	Quisque ut erat. Curabitur gravida nisi at nibh.
475	2	7	5175	4	354.13	OCUPADA	9	Proin at turpis a pede posuere nonummy. Integer non velit.
479	3	1	8579	8	370.53	DISPONIBLE	7	Nullam porttitor lacus at turpis.
481	2	8	6281	2	203.99	OCUPADA	4	Pellentesque ultrices mattis odio.
482	3	1	4582	2	357.28	DISPONIBLE	4	Etiam faucibus cursus urna.
483	1	10	8483	5	720.26	DISPONIBLE	10	Sed ante.
484	2	4	6884	2	199.35	DISPONIBLE	1	Nulla suscipit ligula in lacus.
485	3	1	9585	1	88.73	MANTENIMIENTO	1	Duis mattis egestas metus. Aenean fermentum.
486	1	8	6286	10	402.88	MANTENIMIENTO	2	Nulla nisl. Nunc nisl.
487	2	3	4787	9	658.47	OCUPADA	3	Proin eu mi. Nulla ac enim.
490	2	2	4690	9	246.47	OCUPADA	3	Proin interdum mauris non ligula pellentesque ultrices.
491	3	1	8591	1	353.26	OCUPADA	4	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
493	2	1	5593	4	346.28	MANTENIMIENTO	4	Praesent blandit. Nam nulla.
497	3	3	6797	10	736.62	MANTENIMIENTO	10	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
498	1	3	4798	10	199.60	OCUPADA	5	Etiam justo.
499	2	3	4799	8	507.31	MANTENIMIENTO	9	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem. Duis aliquam convallis nunc.
503	3	8	5303	8	455.37	DISPONIBLE	7	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
505	2	8	10305	10	697.66	DISPONIBLE	3	Aenean lectus. Pellentesque eget nunc.
506	3	6	7106	7	613.97	OCUPADA	6	Duis bibendum.
507	1	9	7407	2	101.26	OCUPADA	7	Pellentesque ultrices mattis odio. Donec vitae nisi.
509	3	7	11209	1	700.37	DISPONIBLE	6	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
510	1	3	8810	7	579.54	MANTENIMIENTO	10	Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus.
511	2	9	8411	2	97.92	MANTENIMIENTO	10	Nullam molestie nibh in lectus.
512	3	5	10012	3	463.60	MANTENIMIENTO	1	Nulla tellus.
513	1	5	7013	1	387.68	DISPONIBLE	2	Praesent id massa id nisl venenatis lacinia.
514	2	6	5114	1	485.18	DISPONIBLE	6	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
515	3	6	7115	10	379.31	DISPONIBLE	6	Morbi non lectus.
516	1	1	4616	7	176.78	DISPONIBLE	4	Sed ante.
517	2	10	7517	7	178.71	MANTENIMIENTO	3	Donec semper sapien a libero. Nam dui.
518	3	7	7218	9	400.95	DISPONIBLE	1	Duis aliquam convallis nunc. Proin at turpis a pede posuere nonummy.
520	2	6	5120	9	169.63	MANTENIMIENTO	9	Aliquam erat volutpat.
521	3	4	6921	7	489.48	DISPONIBLE	1	Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
522	1	5	6022	4	460.36	MANTENIMIENTO	3	Vestibulum rutrum rutrum neque.
524	3	2	5724	2	636.09	OCUPADA	7	Nulla tempus.
525	1	1	6625	5	79.45	OCUPADA	6	Donec ut dolor.
526	2	7	6226	2	495.95	DISPONIBLE	5	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
528	1	10	8528	10	721.11	OCUPADA	8	Maecenas pulvinar lobortis est.
529	2	7	10229	4	281.63	MANTENIMIENTO	8	Suspendisse potenti. Cras in purus eu magna vulputate luctus.
530	3	4	6930	2	448.45	MANTENIMIENTO	6	Maecenas rhoncus aliquam lacus.
533	3	4	8933	8	362.25	MANTENIMIENTO	3	Nulla facilisi. Cras non velit nec nisi vulputate nonummy.
540	1	6	10140	7	53.95	MANTENIMIENTO	9	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
542	3	4	7942	10	701.96	MANTENIMIENTO	10	Etiam justo. Etiam pretium iaculis justo.
543	1	4	7943	6	156.62	DISPONIBLE	10	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci.
544	2	3	10844	6	529.17	OCUPADA	4	Suspendisse ornare consequat lectus.
546	1	1	4646	9	540.54	MANTENIMIENTO	3	Donec dapibus. Duis at velit eu est congue elementum.
549	1	3	9849	9	586.43	MANTENIMIENTO	6	Praesent blandit. Nam nulla.
550	2	1	5650	5	473.43	DISPONIBLE	3	Curabitur convallis. Duis consequat dui nec nisi volutpat eleifend.
552	1	2	6752	9	57.78	MANTENIMIENTO	5	Duis ac nibh. Fusce lacus purus, aliquet at, feugiat non, pretium quis, lectus.
553	2	2	6753	6	538.07	OCUPADA	6	Donec posuere metus vitae ipsum.
556	2	8	7356	8	124.83	OCUPADA	9	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo. Pellentesque viverra pede ac diam.
558	1	7	9258	8	109.75	DISPONIBLE	7	Integer ac leo. Pellentesque ultrices mattis odio.
559	2	3	8859	3	252.82	MANTENIMIENTO	3	Etiam faucibus cursus urna.
561	1	5	6061	2	473.37	MANTENIMIENTO	8	Fusce consequat. Nulla nisl.
562	2	7	7262	2	560.13	MANTENIMIENTO	1	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
564	1	1	8664	4	442.47	MANTENIMIENTO	8	Aenean fermentum. Donec ut mauris eget massa tempor convallis.
567	1	7	6267	2	322.28	DISPONIBLE	5	Curabitur at ipsum ac tellus semper interdum.
569	3	5	11069	6	184.30	MANTENIMIENTO	9	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
570	1	3	4870	5	224.96	MANTENIMIENTO	8	Suspendisse ornare consequat lectus.
571	2	7	10271	8	711.65	OCUPADA	3	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
572	3	9	7472	8	421.90	MANTENIMIENTO	3	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
574	2	4	6974	8	603.30	OCUPADA	2	Sed sagittis. Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
576	1	2	6776	5	723.00	MANTENIMIENTO	10	Morbi non quam nec dui luctus rutrum.
577	2	10	8577	5	471.99	MANTENIMIENTO	7	Curabitur gravida nisi at nibh.
578	3	7	9278	7	515.72	MANTENIMIENTO	7	Mauris sit amet eros.
580	2	1	4680	9	653.53	OCUPADA	7	Integer a nibh.
581	3	3	4881	10	701.52	DISPONIBLE	1	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
583	2	6	7183	5	636.49	OCUPADA	4	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
584	3	9	9484	8	388.50	DISPONIBLE	7	Fusce consequat.
585	1	1	4685	5	308.92	MANTENIMIENTO	9	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
587	3	2	10787	10	641.44	DISPONIBLE	6	Donec ut dolor. Morbi vel lectus in quam fringilla rhoncus.
588	1	2	4788	7	195.52	MANTENIMIENTO	6	Morbi non lectus. Aliquam sit amet diam in magna bibendum imperdiet.
589	2	9	10489	4	728.69	MANTENIMIENTO	10	Duis consequat dui nec nisi volutpat eleifend. Donec ut dolor.
590	3	5	6090	6	559.88	DISPONIBLE	5	Quisque id justo sit amet sapien dignissim vestibulum.
591	1	7	7291	4	158.29	MANTENIMIENTO	3	Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue. Aliquam erat volutpat.
592	2	6	6192	9	304.24	MANTENIMIENTO	3	Nam dui. Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
657	1	2	7857	9	703.20	DISPONIBLE	4	Nullam varius. Nulla facilisi.
593	3	3	5893	8	746.86	MANTENIMIENTO	9	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
594	1	2	6794	4	634.89	MANTENIMIENTO	1	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
595	2	2	6795	3	609.16	MANTENIMIENTO	8	Aliquam sit amet diam in magna bibendum imperdiet. Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
596	3	9	6496	3	454.42	MANTENIMIENTO	1	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi. Integer ac neque.
598	2	6	9198	8	91.68	MANTENIMIENTO	9	Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
599	3	3	9899	2	551.66	MANTENIMIENTO	6	Nulla suscipit ligula in lacus.
600	1	8	5400	3	118.10	OCUPADA	6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
601	2	7	5301	3	592.44	DISPONIBLE	10	Aliquam quis turpis eget elit sodales scelerisque. Mauris sit amet eros.
602	3	7	8302	2	413.76	MANTENIMIENTO	4	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
603	1	2	6803	5	615.68	MANTENIMIENTO	1	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
604	2	10	9604	4	87.54	DISPONIBLE	4	Vivamus vel nulla eget eros elementum pellentesque.
605	3	9	7505	1	585.47	MANTENIMIENTO	1	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
606	1	4	5006	3	595.74	DISPONIBLE	7	Suspendisse accumsan tortor quis turpis.
607	2	7	10307	5	470.08	DISPONIBLE	7	Suspendisse ornare consequat lectus.
609	1	5	5109	10	185.15	DISPONIBLE	1	Quisque porta volutpat erat.
610	2	3	4910	9	208.48	OCUPADA	6	Curabitur in libero ut massa volutpat convallis.
611	3	2	5811	7	459.27	MANTENIMIENTO	10	Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
613	2	5	5113	7	554.50	MANTENIMIENTO	7	In hac habitasse platea dictumst. Etiam faucibus cursus urna.
614	3	7	6314	5	657.79	MANTENIMIENTO	4	Quisque ut erat.
615	1	1	6715	2	128.83	DISPONIBLE	9	Nulla tempus. Vivamus in felis eu sapien cursus vestibulum.
617	3	3	8917	10	104.89	MANTENIMIENTO	2	Maecenas rhoncus aliquam lacus.
619	2	4	11019	2	600.33	MANTENIMIENTO	7	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
620	3	10	10620	6	197.30	OCUPADA	8	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
621	1	9	7521	10	237.63	DISPONIBLE	5	Suspendisse potenti. Nullam porttitor lacus at turpis.
622	2	6	11222	6	371.07	OCUPADA	3	Donec posuere metus vitae ipsum.
623	3	4	5023	2	358.75	DISPONIBLE	6	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa.
624	1	1	6724	5	123.00	MANTENIMIENTO	4	Cras pellentesque volutpat dui.
625	2	10	8625	9	642.15	MANTENIMIENTO	9	Maecenas rhoncus aliquam lacus.
626	3	6	8226	2	746.09	DISPONIBLE	6	Cras pellentesque volutpat dui. Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
627	1	2	6827	10	137.38	DISPONIBLE	6	Proin risus.
628	2	10	9628	9	75.26	DISPONIBLE	2	Quisque id justo sit amet sapien dignissim vestibulum.
629	3	8	8429	9	326.98	DISPONIBLE	6	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
633	1	10	6633	8	736.71	OCUPADA	7	Nam dui.
634	2	1	6734	4	112.76	DISPONIBLE	8	Nulla facilisi. Cras non velit nec nisi vulputate nonummy.
635	3	10	9635	4	234.37	OCUPADA	5	Nulla tellus. In sagittis dui vel nisl.
637	2	3	6937	9	168.17	MANTENIMIENTO	8	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
638	3	6	7238	2	146.56	DISPONIBLE	9	Maecenas ut massa quis augue luctus tincidunt. Nulla mollis molestie lorem.
639	1	1	8739	10	327.57	MANTENIMIENTO	7	Phasellus in felis.
641	3	2	4841	10	111.25	DISPONIBLE	7	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante. Nulla justo.
642	1	10	7642	5	88.33	DISPONIBLE	7	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
643	2	7	9343	4	673.31	MANTENIMIENTO	1	Morbi ut odio. Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo.
644	3	7	9344	3	543.64	OCUPADA	6	Sed accumsan felis.
646	2	10	7646	7	441.45	OCUPADA	1	Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
647	3	10	11647	8	403.25	OCUPADA	6	Nulla ac enim.
648	1	7	9348	7	746.18	MANTENIMIENTO	7	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
650	3	8	7450	7	462.43	DISPONIBLE	3	Nulla ut erat id mauris vulputate elementum.
651	1	8	5451	8	452.97	DISPONIBLE	1	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
652	2	1	8752	2	138.34	DISPONIBLE	6	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
653	3	10	6653	7	404.93	OCUPADA	10	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
654	1	5	7154	1	263.04	OCUPADA	7	Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat.
656	3	1	6756	8	207.29	DISPONIBLE	2	Nam tristique tortor eu pede.
658	2	4	7058	6	252.34	DISPONIBLE	4	Donec posuere metus vitae ipsum.
659	3	8	9459	7	284.01	DISPONIBLE	5	Curabitur in libero ut massa volutpat convallis.
660	1	3	7960	3	440.45	DISPONIBLE	7	Phasellus id sapien in sapien iaculis congue.
661	2	1	5761	3	525.56	MANTENIMIENTO	5	Nulla suscipit ligula in lacus.
662	3	7	7362	10	135.83	OCUPADA	3	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem. Integer tincidunt ante vel ipsum.
663	1	2	6863	2	106.27	DISPONIBLE	5	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
665	3	2	6865	9	731.87	DISPONIBLE	9	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
666	1	7	6366	4	548.50	OCUPADA	8	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
667	2	4	5067	2	446.58	MANTENIMIENTO	10	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
670	2	3	8970	7	143.71	OCUPADA	7	Duis at velit eu est congue elementum. In hac habitasse platea dictumst.
671	3	3	7971	5	717.09	MANTENIMIENTO	4	Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
672	1	1	5772	9	700.99	MANTENIMIENTO	8	Nulla ut erat id mauris vulputate elementum.
674	3	8	5474	1	602.12	DISPONIBLE	5	Vivamus vel nulla eget eros elementum pellentesque. Quisque porta volutpat erat.
675	1	3	10975	2	721.64	MANTENIMIENTO	10	Quisque porta volutpat erat. Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
677	3	8	9477	2	358.35	DISPONIBLE	1	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
679	2	4	5079	7	662.47	DISPONIBLE	5	Duis at velit eu est congue elementum.
682	2	8	5482	4	77.12	MANTENIMIENTO	4	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem.
686	3	5	11186	1	351.57	MANTENIMIENTO	9	Pellentesque viverra pede ac diam. Cras pellentesque volutpat dui.
690	1	5	10190	7	435.21	MANTENIMIENTO	10	Proin leo odio, porttitor id, consequat in, consequat ut, nulla. Sed accumsan felis.
691	2	10	6691	3	224.16	OCUPADA	3	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
692	3	2	7892	6	365.41	DISPONIBLE	10	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
693	1	3	6993	2	241.16	OCUPADA	9	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
694	2	6	5294	4	172.26	MANTENIMIENTO	1	Vestibulum rutrum rutrum neque. Aenean auctor gravida sem.
696	1	8	7496	6	320.87	MANTENIMIENTO	6	Duis mattis egestas metus.
700	2	8	7500	7	327.73	OCUPADA	6	Donec dapibus. Duis at velit eu est congue elementum.
701	3	9	9601	8	545.86	MANTENIMIENTO	3	Vestibulum sed magna at nunc commodo placerat.
702	1	1	6802	2	413.15	DISPONIBLE	5	Pellentesque ultrices mattis odio.
704	3	4	7104	8	645.08	DISPONIBLE	7	Quisque porta volutpat erat. Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
706	2	8	6506	2	478.55	MANTENIMIENTO	9	Donec semper sapien a libero. Nam dui.
707	3	5	7207	7	655.01	OCUPADA	4	In hac habitasse platea dictumst.
708	1	1	8808	10	173.68	OCUPADA	9	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
710	3	9	7610	10	692.35	DISPONIBLE	9	Sed accumsan felis. Ut at dolor quis odio consequat varius.
711	1	4	7111	3	80.54	OCUPADA	10	Vivamus in felis eu sapien cursus vestibulum.
712	2	9	7612	2	411.04	DISPONIBLE	6	In hac habitasse platea dictumst.
714	1	3	7014	5	398.23	DISPONIBLE	9	Vestibulum sed magna at nunc commodo placerat.
715	2	3	7015	9	424.08	MANTENIMIENTO	5	Donec quis orci eget orci vehicula condimentum. Curabitur in libero ut massa volutpat convallis.
716	3	4	5116	6	456.03	OCUPADA	8	Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
717	1	6	7317	2	595.60	MANTENIMIENTO	3	Aliquam non mauris.
718	2	3	7018	4	323.44	OCUPADA	7	Vestibulum sed magna at nunc commodo placerat. Praesent blandit.
719	3	5	11219	3	52.72	OCUPADA	4	Fusce consequat. Nulla nisl.
720	1	2	4920	8	174.33	OCUPADA	3	Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
723	1	3	5023	1	315.66	DISPONIBLE	4	Maecenas tincidunt lacus at velit.
724	2	4	5124	9	552.42	OCUPADA	6	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
725	3	1	4825	2	331.79	OCUPADA	7	Suspendisse potenti.
727	2	7	7427	3	198.62	MANTENIMIENTO	4	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
728	3	8	11528	1	518.03	MANTENIMIENTO	1	Nulla facilisi.
731	3	9	7631	7	82.49	OCUPADA	3	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
733	2	6	7333	8	101.42	DISPONIBLE	5	Ut at dolor quis odio consequat varius. Integer ac leo.
734	3	3	11034	10	574.51	DISPONIBLE	7	Quisque ut erat.
736	2	3	7036	3	747.60	MANTENIMIENTO	9	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi. Integer ac neque.
738	1	6	6338	2	129.00	MANTENIMIENTO	5	Duis consequat dui nec nisi volutpat eleifend. Donec ut dolor.
740	3	5	6240	10	543.16	MANTENIMIENTO	7	In hac habitasse platea dictumst.
741	1	2	6941	8	529.31	DISPONIBLE	6	Integer non velit. Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
742	2	5	6242	10	541.55	DISPONIBLE	4	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
743	3	6	11343	1	719.59	MANTENIMIENTO	7	Sed sagittis.
745	2	10	7745	6	79.37	OCUPADA	6	Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem. Integer tincidunt ante vel ipsum.
749	3	5	5249	4	101.82	OCUPADA	3	Nulla suscipit ligula in lacus.
750	1	9	6650	9	549.66	DISPONIBLE	5	In hac habitasse platea dictumst.
751	2	5	8251	3	394.43	DISPONIBLE	8	Sed sagittis. Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
753	1	6	7353	4	215.89	OCUPADA	4	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
755	3	3	9055	7	486.10	MANTENIMIENTO	9	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus.
756	1	5	5256	8	292.90	OCUPADA	4	Nulla suscipit ligula in lacus.
760	2	1	9860	7	619.12	OCUPADA	6	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
761	3	9	7661	5	495.23	OCUPADA	4	In eleifend quam a odio.
762	1	6	9362	5	207.61	DISPONIBLE	7	Aliquam quis turpis eget elit sodales scelerisque. Mauris sit amet eros.
767	3	9	5667	8	170.93	MANTENIMIENTO	9	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
768	1	1	4868	5	217.63	MANTENIMIENTO	7	Suspendisse accumsan tortor quis turpis. Sed ante.
771	1	2	6971	4	692.69	DISPONIBLE	7	Nam tristique tortor eu pede.
772	2	9	6672	10	524.33	MANTENIMIENTO	4	Maecenas rhoncus aliquam lacus.
773	3	6	7373	1	397.23	MANTENIMIENTO	9	Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo. In blandit ultrices enim.
775	2	3	7075	4	78.45	OCUPADA	1	Nulla tellus. In sagittis dui vel nisl.
776	3	1	5876	10	299.88	MANTENIMIENTO	8	Phasellus id sapien in sapien iaculis congue.
777	1	7	9477	6	445.13	OCUPADA	1	Mauris sit amet eros.
778	2	9	6678	4	163.16	MANTENIMIENTO	6	Curabitur in libero ut massa volutpat convallis.
779	3	6	6379	8	539.11	MANTENIMIENTO	6	Nulla mollis molestie lorem.
781	2	6	6381	10	567.50	MANTENIMIENTO	8	Nam dui.
782	3	8	5582	10	324.31	DISPONIBLE	7	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
783	1	2	7983	9	707.31	OCUPADA	4	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
786	1	1	10886	5	324.61	MANTENIMIENTO	3	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
788	3	8	5588	5	334.41	OCUPADA	5	Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
791	3	5	7291	7	117.00	MANTENIMIENTO	6	Nullam varius.
792	1	7	10492	1	627.61	MANTENIMIENTO	5	Curabitur convallis.
793	2	4	6193	5	439.40	DISPONIBLE	5	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante.
794	3	5	5294	7	350.36	DISPONIBLE	8	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
795	1	8	9595	3	532.91	DISPONIBLE	7	Cras pellentesque volutpat dui. Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
798	1	8	11598	4	555.16	OCUPADA	2	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
800	3	10	7800	9	462.47	MANTENIMIENTO	1	In hac habitasse platea dictumst.
804	1	3	7104	8	125.99	OCUPADA	2	Integer ac leo.
805	2	5	5305	8	633.65	DISPONIBLE	3	Cras pellentesque volutpat dui.
806	3	4	5206	10	117.18	OCUPADA	10	Sed accumsan felis. Ut at dolor quis odio consequat varius.
807	1	7	9507	7	291.43	OCUPADA	6	Ut tellus. Nulla ut erat id mauris vulputate elementum.
808	2	9	8708	7	437.80	OCUPADA	10	Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa. Donec dapibus.
810	1	5	10310	3	573.31	MANTENIMIENTO	2	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus.
811	2	5	5311	10	401.37	MANTENIMIENTO	4	Aliquam erat volutpat. In congue.
812	3	5	6312	3	476.02	OCUPADA	4	Morbi a ipsum.
813	1	1	6913	8	650.21	MANTENIMIENTO	6	In sagittis dui vel nisl.
814	2	6	8414	9	583.10	OCUPADA	1	Curabitur convallis. Duis consequat dui nec nisi volutpat eleifend.
815	3	1	8915	7	274.15	OCUPADA	3	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio. Curabitur convallis.
816	1	10	5816	10	237.26	DISPONIBLE	7	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
818	3	6	7418	5	215.28	DISPONIBLE	5	Pellentesque ultrices mattis odio. Donec vitae nisi.
822	1	4	7222	10	662.54	MANTENIMIENTO	6	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
825	1	7	5525	6	64.19	DISPONIBLE	8	Cras in purus eu magna vulputate luctus. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
826	2	7	5526	7	210.03	DISPONIBLE	9	Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
827	3	2	6027	4	342.43	OCUPADA	6	Nam tristique tortor eu pede.
829	2	10	6829	7	457.85	MANTENIMIENTO	1	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
830	3	8	5630	1	309.94	MANTENIMIENTO	5	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam. Suspendisse potenti.
832	2	8	9632	2	329.02	DISPONIBLE	3	Cras in purus eu magna vulputate luctus. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
833	3	5	9333	4	366.57	DISPONIBLE	4	Quisque porta volutpat erat.
835	2	9	5735	9	466.90	MANTENIMIENTO	10	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
836	3	3	6136	2	529.56	OCUPADA	2	Morbi vel lectus in quam fringilla rhoncus.
837	1	2	5037	8	543.90	DISPONIBLE	10	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
840	1	9	9740	7	149.59	MANTENIMIENTO	6	Etiam justo. Etiam pretium iaculis justo.
842	3	3	7142	1	631.65	OCUPADA	2	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
843	1	5	7343	4	280.06	MANTENIMIENTO	1	Nam dui. Proin leo odio, porttitor id, consequat in, consequat ut, nulla.
845	3	3	5145	6	310.27	DISPONIBLE	1	Nunc purus.
846	1	9	10746	4	569.98	OCUPADA	4	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
847	2	9	6747	1	259.88	MANTENIMIENTO	4	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
848	3	5	11348	3	131.86	MANTENIMIENTO	4	Pellentesque ultrices mattis odio. Donec vitae nisi.
849	1	2	11049	8	117.30	OCUPADA	1	Integer ac neque. Duis bibendum.
852	1	3	6152	7	408.84	DISPONIBLE	9	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
854	3	8	5654	9	85.11	MANTENIMIENTO	3	Aenean sit amet justo. Morbi ut odio.
856	2	5	7356	3	277.32	MANTENIMIENTO	7	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
857	3	9	10757	7	162.45	MANTENIMIENTO	4	Integer ac leo. Pellentesque ultrices mattis odio.
858	1	10	7858	9	469.66	OCUPADA	8	Quisque id justo sit amet sapien dignissim vestibulum. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est.
859	2	5	6359	6	567.12	OCUPADA	5	Proin at turpis a pede posuere nonummy. Integer non velit.
860	3	3	6160	9	522.26	MANTENIMIENTO	6	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
861	1	7	8561	4	700.55	MANTENIMIENTO	7	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
863	3	10	9863	3	439.11	DISPONIBLE	5	Praesent lectus.
864	1	4	7264	7	583.95	DISPONIBLE	9	In est risus, auctor sed, tristique in, tempus sit amet, sem.
865	2	2	5065	5	128.21	DISPONIBLE	9	Praesent blandit.
868	2	6	10468	5	171.08	MANTENIMIENTO	1	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
869	3	6	5469	8	529.84	DISPONIBLE	4	Phasellus in felis.
870	1	10	5870	3	730.05	DISPONIBLE	5	Cras pellentesque volutpat dui.
873	1	8	5673	8	419.41	OCUPADA	3	Nunc nisl. Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa.
877	2	7	11577	7	250.72	OCUPADA	7	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
878	3	5	5378	10	398.95	MANTENIMIENTO	7	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros.
880	2	4	10280	4	686.54	MANTENIMIENTO	6	Quisque porta volutpat erat.
881	3	9	6781	6	352.84	OCUPADA	7	Vestibulum ac est lacinia nisi venenatis tristique.
883	2	1	9983	3	704.93	OCUPADA	8	Morbi vel lectus in quam fringilla rhoncus.
884	3	8	9684	2	317.37	OCUPADA	6	Pellentesque eget nunc. Donec quis orci eget orci vehicula condimentum.
887	3	8	7687	2	404.73	MANTENIMIENTO	6	Aliquam non mauris. Morbi non lectus.
888	1	10	6888	2	689.38	DISPONIBLE	1	Cras non velit nec nisi vulputate nonummy. Maecenas tincidunt lacus at velit.
889	2	2	11089	8	522.59	MANTENIMIENTO	1	Aenean auctor gravida sem.
890	3	8	10690	10	594.03	DISPONIBLE	1	Nullam varius. Nulla facilisi.
892	2	5	8392	3	616.69	MANTENIMIENTO	10	Fusce posuere felis sed lacus.
893	3	5	7393	7	374.24	DISPONIBLE	5	Nullam varius. Nulla facilisi.
895	2	5	5395	6	111.72	DISPONIBLE	2	Mauris ullamcorper purus sit amet nulla. Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
896	3	3	7196	1	699.26	DISPONIBLE	8	Nulla mollis molestie lorem. Quisque ut erat.
897	1	5	8397	8	518.77	OCUPADA	5	Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
898	2	2	5098	10	314.31	MANTENIMIENTO	7	Integer tincidunt ante vel ipsum.
899	3	4	10299	2	187.51	OCUPADA	10	Curabitur convallis.
900	1	10	7900	6	164.99	DISPONIBLE	4	Curabitur at ipsum ac tellus semper interdum.
901	2	7	10601	2	640.77	MANTENIMIENTO	8	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
902	3	6	5502	6	253.15	OCUPADA	2	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi.
904	2	3	11204	7	87.75	DISPONIBLE	10	Etiam faucibus cursus urna.
905	3	2	7105	8	680.92	OCUPADA	3	Nunc nisl.
907	2	7	11607	6	146.83	MANTENIMIENTO	3	Morbi vestibulum, velit id pretium iaculis, diam erat fermentum justo, nec condimentum neque sapien placerat ante. Nulla justo.
908	3	5	7408	2	433.14	DISPONIBLE	6	Cras in purus eu magna vulputate luctus. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
909	1	8	9709	10	638.92	MANTENIMIENTO	9	Morbi vel lectus in quam fringilla rhoncus.
913	2	2	7113	4	599.43	DISPONIBLE	10	In est risus, auctor sed, tristique in, tempus sit amet, sem.
914	3	3	8214	2	164.50	DISPONIBLE	4	Integer non velit.
916	2	1	7016	9	145.35	OCUPADA	9	Nulla ac enim. In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
917	3	1	8017	6	278.43	DISPONIBLE	8	Nullam varius.
918	1	10	8918	10	57.73	OCUPADA	6	Mauris sit amet eros.
919	2	3	7219	7	244.27	MANTENIMIENTO	6	Aliquam erat volutpat.
920	3	5	9420	6	635.95	DISPONIBLE	10	Ut at dolor quis odio consequat varius. Integer ac leo.
921	1	5	5421	7	171.26	DISPONIBLE	8	In eleifend quam a odio.
922	2	8	5722	7	162.70	DISPONIBLE	3	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Mauris viverra diam vitae quam.
923	3	6	5523	2	234.57	DISPONIBLE	8	Pellentesque viverra pede ac diam. Cras pellentesque volutpat dui.
927	1	1	7027	6	588.63	DISPONIBLE	7	Pellentesque at nulla.
929	3	8	7729	9	636.46	DISPONIBLE	5	Nullam sit amet turpis elementum ligula vehicula consequat.
930	1	3	5230	1	676.82	OCUPADA	1	Sed vel enim sit amet nunc viverra dapibus.
931	2	4	7331	4	397.78	DISPONIBLE	4	In quis justo. Maecenas rhoncus aliquam lacus.
932	3	1	9032	8	725.56	MANTENIMIENTO	2	Etiam pretium iaculis justo.
933	1	8	10733	8	485.18	OCUPADA	1	Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
934	2	8	8734	7	311.78	MANTENIMIENTO	2	Vestibulum ac est lacinia nisi venenatis tristique. Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue.
935	3	3	11235	5	740.62	OCUPADA	7	Aliquam quis turpis eget elit sodales scelerisque.
938	3	2	7138	6	291.02	DISPONIBLE	7	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
939	1	9	9839	8	256.09	OCUPADA	6	Donec ut mauris eget massa tempor convallis.
940	2	9	8840	9	298.33	DISPONIBLE	7	Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
941	3	4	5341	9	684.32	DISPONIBLE	7	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo. Maecenas pulvinar lobortis est.
943	2	9	6843	9	162.35	MANTENIMIENTO	8	In eleifend quam a odio.
944	3	3	10244	10	357.06	MANTENIMIENTO	3	Proin interdum mauris non ligula pellentesque ultrices.
946	2	7	7646	7	730.24	MANTENIMIENTO	2	Ut tellus.
948	1	2	9148	10	536.22	DISPONIBLE	6	Proin interdum mauris non ligula pellentesque ultrices.
950	3	1	7050	2	626.44	DISPONIBLE	2	Morbi a ipsum.
951	1	10	5951	5	721.90	OCUPADA	1	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
952	2	4	6352	2	465.32	OCUPADA	10	In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
953	3	1	8053	4	449.77	MANTENIMIENTO	10	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
954	1	8	9754	1	616.98	DISPONIBLE	10	Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
955	2	5	11455	10	298.35	OCUPADA	6	Proin interdum mauris non ligula pellentesque ultrices. Phasellus id sapien in sapien iaculis congue.
906	1	1	6006	7	88.00	OCUPADA	6	In quis justo.
910	2	1	5010	1	98.00	DISPONIBLE	1	Vivamus tortor. Duis mattis egestas metus.
\.


--
-- TOC entry 5350 (class 0 OID 31108)
-- Dependencies: 229
-- Data for Name: hotel; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.hotel (id_hotel, nombre, direccion, niveles_edificios, calificacion, descripcion) FROM stdin;
1	Hotel Costa Azul	Playa El Tunco, La Libertad	4	3.2	Resort frente a la playa con piscina infinita
2	Mirador San Salvador	Colonia Escal??n, San Salvador	10	3.1	Hotel de lujo con vista panor??mica a la ciudad
3	Posada del Volc??n	Parque Nacional El Boquer??n	2	3.2	Caba??as r??sticas inmersas en la naturaleza
\.


--
-- TOC entry 5362 (class 0 OID 31170)
-- Dependencies: 242
-- Data for Name: huesped; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.huesped (id_huesped, nombre, correo, telefono, documento, tipo_documento) FROM stdin;
1	Celisse	cmishaw0@mtv.com	+503 7839-5005	61184475-9	DUI
2	Rikki	rtrevance1@over-blog.com	+503 7321-7439	88144014-0	DUI
3	Phyllys	pklus2@mysql.com	+503 2722-4817	59864233-2	DUI
4	Margery	mtrusdale3@shutterfly.com	+503 7969-8755	81532540-3	DUI
5	Wendy	wobell4@ca.gov	+503 2821-0844	43284281-0	DUI
6	Brenda	bisaaksohn5@usatoday.com	+503 2971-4831	35545176-8	DUI
7	Jackqueline	jboerderman6@tripadvisor.com	+503 6960-9032	09430129-7	DUI
8	Boyce	bdurban7@sohu.com	+503 6249-9752	60726915-6	DUI
9	Haily	hcockshott8@vimeo.com	+503 6902-5922	48259740-3	DUI
10	Darnell	dtibb9@com.com	+503 6626-7193	80981753-0	DUI
11	Lynnett	lscrowtona@flickr.com	+503 2019-6979	84459559-8	DUI
12	Solomon	slawlesb@freewebs.com	+503 6123-3827	85584688-5	DUI
13	Lynett	lbattmanc@telegraph.co.uk	+503 2598-9959	34093147-8	DUI
14	Laurie	lbirdseyd@aol.com	+503 2882-3043	80883169-1	DUI
15	Dalila	dkeerse@symantec.com	+503 6212-9754	10891157-4	DUI
16	Gaspar	ghymorf@vinaora.com	+503 2854-0598	79008416-7	DUI
17	Leena	lyesening@wikia.com	+503 7909-6942	79299143-3	DUI
18	Aylmer	anettleh@nature.com	+503 7917-8134	56906659-3	DUI
19	Mareah	mmiliusi@vistaprint.com	+503 6393-6961	36108113-8	DUI
20	Andrea	achannerj@ow.ly	+503 7452-0784	23448400-6	DUI
21	Wendye	whaytok@upenn.edu	+503 6092-7183	93471097-8	DUI
22	Janek	jtourryl@cargocollective.com	+503 7432-4981	87489183-0	DUI
23	Irina	igrzegorzewskim@latimes.com	+503 7874-2886	13186243-7	DUI
24	Sue	sleperen@shop-pro.jp	+503 2733-9453	91204417-8	DUI
25	Mendy	mscurlocko@e-recht24.de	+503 7691-8680	45844301-4	DUI
26	Latrena	ldonnep@opensource.org	+503 2677-5966	18652386-2	DUI
27	Remington	rreelyq@sfgate.com	+503 2608-3717	62201926-1	DUI
28	Rockie	rreecer@geocities.com	+503 2853-4406	35943223-9	DUI
29	Tan	tcowplands@redcross.org	+503 2667-9839	78583556-5	DUI
30	Ewen	ecawseyt@miitbeian.gov.cn	+503 7809-4138	83069879-4	DUI
31	Allister	aharrapu@quantcast.com	+503 2501-4947	41301990-1	DUI
32	Agretha	ajeyesv@cbsnews.com	+503 2231-2953	32220343-5	DUI
33	Inglis	ibraffingtonw@naver.com	+503 2643-6078	59291939-9	DUI
34	Augustina	atattersdillx@google.ru	+503 7997-0413	40863665-6	DUI
35	Barby	bshurmorey@cargocollective.com	+503 6364-1038	38349429-5	DUI
36	Garnette	gjankuz@imdb.com	+503 7149-8176	71823029-8	DUI
37	Zerk	zteodorski10@tinyurl.com	+503 6264-5926	80308323-4	DUI
38	Karry	kmaccoll11@ebay.com	+503 2977-5278	74817997-8	DUI
39	Trstram	tbrockhouse12@nhs.uk	+503 2252-1410	91981804-6	DUI
40	Reuben	rdrains13@wordpress.org	+503 2208-3103	78295465-9	DUI
41	Isabelita	igamlyn14@imgur.com	+503 2022-7324	40551263-6	DUI
42	Junina	jmattingley15@slate.com	+503 6313-8809	47939373-8	DUI
43	Riordan	rbielfelt16@technorati.com	+503 7729-0168	69911858-5	DUI
44	Roscoe	rpeekevout17@home.pl	+503 7723-9993	30228817-2	DUI
45	Corty	calans18@ed.gov	+503 2902-6940	00679904-8	DUI
46	Maddy	maynold19@live.com	+503 2136-0788	60548731-6	DUI
47	Pru	ptrime1a@moonfruit.com	+503 6778-9461	26377879-2	DUI
48	Ives	irasch1b@linkedin.com	+503 2687-6470	00781455-8	DUI
49	Debora	dmcreedy1c@ameblo.jp	+503 6627-3750	58914853-1	DUI
50	Salomo	smohan1d@phoca.cz	+503 2524-4891	45848812-9	DUI
51	Tammi	tmclurg1e@stumbleupon.com	+503 7144-2513	49323864-5	DUI
52	Willabella	wcornew1f@washingtonpost.com	+503 6052-9382	25287647-6	DUI
53	Fiorenze	fcomino1g@goo.ne.jp	+503 7090-9111	13624629-0	DUI
54	Pepita	pizatson1h@blinklist.com	+503 2081-0129	97809473-2	DUI
55	Vasili	vecclestone1i@npr.org	+503 7197-3950	57497273-9	DUI
56	Salem	sdransfield1j@bloomberg.com	+503 2246-0279	41628760-9	DUI
57	Margaret	mhulbert1k@pcworld.com	+503 7871-4776	81546798-1	DUI
58	Barnard	bmckellen1l@yellowpages.com	+503 2688-1447	90437657-0	DUI
59	Cosette	cpask1m@mapquest.com	+503 6048-7825	44268248-4	DUI
60	Emmit	ecoulthard1n@dyndns.org	+503 2207-0521	20886146-2	DUI
61	Sharl	smottershaw1o@gnu.org	+503 2103-6265	44814038-4	DUI
62	Jermayne	jsousa1p@geocities.com	+503 7994-5612	37425322-1	DUI
63	Had	hcarp1q@sun.com	+503 6395-5962	30215403-0	DUI
64	Saundra	sruppert1r@myspace.com	+503 6017-9221	77171111-0	DUI
65	Francois	fdyble1s@prweb.com	+503 7204-9906	59045675-9	DUI
66	Cesaro	cfanti1t@so-net.ne.jp	+503 7108-3101	37792682-5	DUI
67	Emlyn	ecaldes1u@stanford.edu	+503 7382-6030	24556013-3	DUI
68	Agnesse	afould1v@nytimes.com	+503 2045-0832	83996074-7	DUI
69	Hilary	hwalenta1w@elpais.com	+503 2185-3553	18107192-4	DUI
70	Dominique	dstuddert1x@theglobeandmail.com	+503 2293-0439	59825541-5	DUI
71	Romain	rgommowe1y@macromedia.com	+503 6877-1416	87883834-8	DUI
72	Beauregard	bcripin1z@hao123.com	+503 2066-1790	92534129-5	DUI
73	Marjie	mpragnell20@slideshare.net	+503 6219-6723	08172174-5	DUI
74	Dyanna	ddelacoste21@google.it	+503 6026-8675	71111601-7	DUI
75	Sabrina	sdougher22@symantec.com	+503 7952-7574	46649435-1	DUI
76	Myrilla	mnaire23@dagondesign.com	+503 7727-6959	06372390-0	DUI
77	Korrie	kmussilli24@unicef.org	+503 7173-1718	35741305-3	DUI
78	Florence	fumney25@nifty.com	+503 2168-6773	22148954-1	DUI
79	Janey	jclaybourne26@hhs.gov	+503 2167-6236	78870114-1	DUI
80	Desiri	dchesters27@quantcast.com	+503 7892-5528	99207098-2	DUI
81	Jase	jpedrick28@samsung.com	+503 2602-3162	27430158-6	DUI
82	Channa	cblance29@godaddy.com	+503 7263-2462	15372504-2	DUI
83	Aldrich	anoke2a@histats.com	+503 6726-2893	21152372-1	DUI
84	Jourdain	jconachy2b@nhs.uk	+503 2857-4842	55314704-4	DUI
85	Melicent	mcamier2c@fc2.com	+503 7572-1223	88609154-5	DUI
86	Gerald	glibreros2d@blinklist.com	+503 6343-5265	95083155-4	DUI
87	Mikel	mwayne2e@blogger.com	+503 7153-1299	31825075-2	DUI
88	Timmie	twallsworth2f@ovh.net	+503 6886-8038	28358594-3	DUI
89	Nathan	nlindro2g@dot.gov	+503 6290-1503	34222136-6	DUI
90	Laurella	lleggis2h@sohu.com	+503 7837-3399	06934543-7	DUI
91	Bailey	benstone2i@addthis.com	+503 7705-0359	08468489-4	DUI
92	Margalit	mkilby2j@mit.edu	+503 2828-6382	36143827-1	DUI
93	Alexi	aadiscot2k@a8.net	+503 6734-3555	26955562-7	DUI
94	Rube	rstibbs2l@diigo.com	+503 6360-9924	47433028-5	DUI
95	Cyrillus	ccastelyn2m@intel.com	+503 7549-4378	12551541-5	DUI
96	Herbert	htolworthy2n@cargocollective.com	+503 2697-0943	64912459-7	DUI
97	Faydra	fcyphus2o@prlog.org	+503 2804-0783	81414451-6	DUI
98	Arthur	arosenzwig2p@google.de	+503 7574-7465	12951895-7	DUI
99	Marchall	mkingswood2q@cdbaby.com	+503 7887-7125	25361161-7	DUI
100	Mauricio	mkitteringham2r@noaa.gov	+503 6465-7830	45407225-9	DUI
101	Vale	vcomi2s@youku.com	+503 6645-8965	14433600-2	DUI
102	Willa	wellam2t@wp.com	+503 7630-4227	85554912-0	DUI
103	Lawry	lstapels2u@census.gov	+503 2318-5365	33908698-1	DUI
104	Sib	swistance2v@businessinsider.com	+503 2039-6702	77438781-3	DUI
105	Costanza	cnewband2w@senate.gov	+503 2276-6311	72364787-4	DUI
106	Ardelle	amedlar2x@alibaba.com	+503 6334-2945	81383984-0	DUI
107	Glen	gmcterlagh2y@i2i.jp	+503 6697-0819	77347115-7	DUI
108	Sondra	slevesque2z@yelp.com	+503 7929-6702	59379899-8	DUI
109	Bobbe	bseamark30@pen.io	+503 7149-7574	61964707-5	DUI
110	Junia	jbarme31@usgs.gov	+503 6221-0766	72975264-2	DUI
111	Terry	tlago32@youku.com	+503 7899-8379	24110131-4	DUI
112	Idell	ikerans33@sciencedaily.com	+503 7620-9030	04238694-6	DUI
113	Malanie	mkarpol34@nba.com	+503 6539-7213	47467887-2	DUI
114	Ericha	erylett35@youku.com	+503 7840-3116	67844401-3	DUI
115	Pamella	pcawthery36@blogs.com	+503 7936-0975	42901634-0	DUI
116	Harmonie	hcoultard37@studiopress.com	+503 7440-0105	95009162-7	DUI
117	Dacia	dneat38@time.com	+503 6257-1500	51898977-9	DUI
118	Adan	adudeney39@nymag.com	+503 7172-2121	73708799-8	DUI
119	Witty	wpyett3a@dailymail.co.uk	+503 2919-2100	81175176-9	DUI
120	Angelico	abarsam3b@techcrunch.com	+503 2112-3659	77204750-3	DUI
121	Chrisse	ctsar3c@phpbb.com	+503 2974-2428	71576808-0	DUI
122	Tybalt	tblackett3d@purevolume.com	+503 7999-4372	05490683-9	DUI
123	Finley	fespinoza3e@scientificamerican.com	+503 2661-3868	59370277-4	DUI
124	Iain	ibirnie3f@cargocollective.com	+503 6092-7086	22713705-0	DUI
125	Florence	fwethey3g@usa.gov	+503 6883-7403	40831871-0	DUI
126	Des	dcartmel3h@indiegogo.com	+503 7902-8757	13872675-1	DUI
127	Holden	hmcneillie3i@usnews.com	+503 6884-8339	93933565-9	DUI
128	Raven	rpendrey3j@google.fr	+503 7801-7705	58281815-1	DUI
129	Ransell	rsanpere3k@furl.net	+503 2908-5679	60289329-7	DUI
130	Catina	ccory3l@un.org	+503 6567-3044	97987070-3	DUI
131	Gerta	gaikenhead3m@theatlantic.com	+503 6214-8849	08797413-8	DUI
132	Nora	nbufton3n@squidoo.com	+503 7616-8574	27453536-2	DUI
133	Caprice	chattrick3o@netscape.com	+503 6539-8825	67125576-9	DUI
134	Franni	fpontain3p@tamu.edu	+503 2355-5742	05655633-5	DUI
135	Brion	bcaustick3q@bing.com	+503 2095-1681	70499350-9	DUI
136	Thaddus	truff3r@vinaora.com	+503 7210-3122	28127472-5	DUI
137	Beckie	bmahmood3s@simplemachines.org	+503 6355-9136	52368858-4	DUI
138	Rollie	rgraham3t@amazon.de	+503 6400-2644	18876551-5	DUI
139	Gigi	gwaker3u@theguardian.com	+503 2042-8889	33124464-9	DUI
140	Rubia	rbabalola3v@cnet.com	+503 7523-7721	50851686-5	DUI
141	Clay	ctommaseo3w@nsw.gov.au	+503 2160-5603	49905028-7	DUI
142	Sosanna	skrammer3x@admin.ch	+503 2527-7878	41823588-3	DUI
143	Krishnah	ktinsley3y@nifty.com	+503 7737-5194	63199393-3	DUI
144	Margarethe	mbretherton3z@histats.com	+503 6502-6296	02835654-3	DUI
145	Minda	mstacey40@stanford.edu	+503 6200-7157	93559665-9	DUI
146	Dal	dpeyro41@howstuffworks.com	+503 7931-1818	72453854-8	DUI
147	Gerri	ghaslehurst42@dailymail.co.uk	+503 2414-2482	39687236-4	DUI
148	Allen	amacloughlin43@soundcloud.com	+503 2350-5388	58781118-8	DUI
149	Mort	mohern44@stumbleupon.com	+503 7776-1234	50112297-3	DUI
150	Marty	mforrest45@diigo.com	+503 6626-5449	68068384-9	DUI
151	Harmon	hmulderrig46@ebay.com	+503 2671-2823	68534016-9	DUI
152	Frederic	fcoleyshaw47@networkadvertising.org	+503 7386-7079	34601237-9	DUI
153	Jessamyn	jcarpenter48@msu.edu	+503 2877-0857	06819185-6	DUI
154	Gabbey	gblackader49@sciencedaily.com	+503 6841-4354	70441553-9	DUI
155	Sib	scoultass4a@opensource.org	+503 6612-8525	26480383-3	DUI
156	Evita	echampkins4b@angelfire.com	+503 2507-0194	01997877-7	DUI
157	Ellery	eunger4c@imdb.com	+503 7039-0819	97301893-4	DUI
158	Janina	jdomeney4d@zdnet.com	+503 6937-4745	74787824-8	DUI
159	Gwenneth	ggianninotti4e@canalblog.com	+503 2191-2978	35209714-8	DUI
160	Lynette	lowlner4f@hp.com	+503 6008-6437	77194273-7	DUI
161	Barbaraanne	bblakebrough4g@guardian.co.uk	+503 7247-3689	81274076-7	DUI
162	Rubetta	rmatiashvili4h@vistaprint.com	+503 6022-7114	60952567-9	DUI
163	Birdie	bmartt4i@spiegel.de	+503 7735-1502	16619775-2	DUI
164	Raffaello	rkings4j@squarespace.com	+503 2340-6862	06291432-1	DUI
165	Norton	nlabusquiere4k@cornell.edu	+503 7183-6377	11118469-1	DUI
166	Christoforo	cnannoni4l@pcworld.com	+503 7865-0895	29329838-7	DUI
167	Parsifal	pmackenney4m@chronoengine.com	+503 6603-8595	39181231-2	DUI
168	Cirstoforo	ccapaldi4n@jigsy.com	+503 2966-6394	53848377-8	DUI
169	Kayley	kfredi4o@fc2.com	+503 7593-7744	06191226-0	DUI
170	Tully	tteresia4p@wikimedia.org	+503 2428-5578	70842347-4	DUI
171	Anderea	amurrow4q@discuz.net	+503 7650-3800	37990971-8	DUI
172	Dianne	dkingsnod4r@printfriendly.com	+503 6472-1313	31099003-5	DUI
173	Casper	cjeannard4s@t.co	+503 6515-1303	48105895-2	DUI
174	Berrie	bhallgough4t@cdc.gov	+503 7545-8866	44854741-1	DUI
175	Saudra	sghidotti4u@nba.com	+503 6168-9109	69683823-3	DUI
176	Glynnis	gcornish4v@dagondesign.com	+503 7232-9657	01079660-5	DUI
177	Gisella	gupjohn4w@twitter.com	+503 7063-5592	30169614-9	DUI
178	Theodore	tgiacobbinijacob4x@epa.gov	+503 6788-3218	58861266-7	DUI
179	Vidovik	vbert4y@columbia.edu	+503 6287-1507	66472524-0	DUI
180	Clayborne	csimondson4z@miitbeian.gov.cn	+503 7220-0342	64014917-5	DUI
181	Florinda	fwye50@mozilla.com	+503 7660-3964	28129092-5	DUI
182	Charmine	cmarlow51@eventbrite.com	+503 6781-1640	77496479-5	DUI
183	Hilliard	htingley52@xrea.com	+503 6356-7940	50081147-5	DUI
184	Jolie	jbeynke53@cdc.gov	+503 6071-0428	89480837-0	DUI
185	Moina	mfeathers54@admin.ch	+503 2865-1469	79788516-0	DUI
186	Hillie	htreswell55@sourceforge.net	+503 6417-3122	10881590-7	DUI
187	Meryl	mchelley56@symantec.com	+503 2256-3330	85060267-5	DUI
188	Carlin	cnoden57@myspace.com	+503 6767-3404	26707176-3	DUI
189	Ivar	iocarney58@wikipedia.org	+503 2852-1779	75820790-6	DUI
190	Nelie	nmaccaughey59@un.org	+503 2341-2012	79390316-5	DUI
191	Brigid	bvarey5a@facebook.com	+503 7095-2059	12114524-0	DUI
192	Alejandra	aallibon5b@vistaprint.com	+503 6125-4033	85653546-9	DUI
193	Adiana	akellar5c@amazon.co.jp	+503 6731-8570	52119642-5	DUI
194	Shelby	sboarer5d@hubpages.com	+503 6837-8122	32921670-2	DUI
195	Ragnar	rhumbey5e@cisco.com	+503 7158-5269	24423388-3	DUI
196	Farlee	fdigges5f@alexa.com	+503 2323-7003	77943140-6	DUI
197	Carree	ccheevers5g@wikispaces.com	+503 2946-5552	42092265-3	DUI
198	Nataniel	nstockill5h@sourceforge.net	+503 6723-5669	73815456-4	DUI
199	Darb	dhanford5i@utexas.edu	+503 7669-3660	31528545-8	DUI
200	Jemimah	jewan5j@kickstarter.com	+503 6937-7132	07916629-3	DUI
201	Dre	dgadman5k@theglobeandmail.com	+503 2173-7112	03843396-2	DUI
202	Raina	rgregson5l@telegraph.co.uk	+503 6794-0746	18771033-2	DUI
203	Nerita	ndanton5m@google.co.uk	+503 2821-2248	19132050-0	DUI
204	Chandler	ckahn5n@vkontakte.ru	+503 2828-0236	24667642-6	DUI
205	Jake	jtertre5o@sciencedaily.com	+503 2156-5242	99821265-0	DUI
206	Linda	lpehrsson5p@businessweek.com	+503 2884-3126	60276073-3	DUI
207	Aggie	agreedy5q@forbes.com	+503 7575-6541	62003314-7	DUI
208	Mirilla	mnaptin5r@webnode.com	+503 6440-5501	85045750-3	DUI
209	Lindon	lwheelband5s@army.mil	+503 6757-5012	64281822-1	DUI
210	Goddard	gkeller5t@latimes.com	+503 7675-9595	64711714-7	DUI
211	Kimberlee	kskullet5u@guardian.co.uk	+503 6382-3919	26738017-8	DUI
212	Roselle	rsainter5v@barnesandnoble.com	+503 6099-1697	10433712-7	DUI
213	Napoleon	nlysaght5w@issuu.com	+503 7849-5026	16320274-9	DUI
214	Alisha	akmieciak5x@ning.com	+503 2332-5702	69668068-8	DUI
215	Elysia	ejakobsson5y@wordpress.com	+503 6518-0296	55071183-8	DUI
216	Helen-elizabeth	hmceniry5z@youku.com	+503 2091-7410	17077553-8	DUI
217	Gerrilee	gcaneo60@nbcnews.com	+503 7108-3113	51293268-0	DUI
218	Berti	bradage61@foxnews.com	+503 6824-5134	55331196-1	DUI
219	Jean	jrichfield62@army.mil	+503 7476-1469	60177637-8	DUI
220	Aileen	ataffs63@jalbum.net	+503 2789-6663	13811878-7	DUI
221	Bernice	bbannester64@nifty.com	+503 7689-0620	46075892-2	DUI
222	Caria	cfotherby65@geocities.com	+503 7656-7066	19647201-9	DUI
223	Erek	efreezor66@si.edu	+503 6105-9318	50371945-3	DUI
224	Galven	gthew67@shop-pro.jp	+503 6676-2581	86075578-0	DUI
225	Cristobal	clorenc68@etsy.com	+503 7618-8255	76404290-0	DUI
226	Aurelea	aaxby69@cdbaby.com	+503 6130-4558	51457338-8	DUI
227	Giffer	gduggary6a@issuu.com	+503 7764-2395	85750295-4	DUI
228	Quent	qmingard6b@soundcloud.com	+503 7386-9335	39767555-0	DUI
229	Florette	fduding6c@cam.ac.uk	+503 2942-7690	18004179-8	DUI
230	Desiri	dzywicki6d@discuz.net	+503 7188-6188	35249349-7	DUI
231	Gwyneth	gkobiela6e@webs.com	+503 6672-7753	64062531-6	DUI
232	Estell	etidy6f@theglobeandmail.com	+503 7743-5105	57999185-1	DUI
233	Clovis	charvison6g@goodreads.com	+503 2571-5040	46284959-3	DUI
234	Jenifer	jtoal6h@google.nl	+503 6098-3622	04241743-6	DUI
235	Bar	bdurno6i@ocn.ne.jp	+503 6243-1363	75756084-6	DUI
236	Kellina	ktimeby6j@jigsy.com	+503 7366-6426	71715407-2	DUI
237	Lauren	lpoluzzi6k@artisteer.com	+503 6158-9229	28128182-3	DUI
238	Shandy	swhorf6l@symantec.com	+503 7028-7269	82448995-4	DUI
239	Donni	dshearman6m@fc2.com	+503 7139-8816	58778354-0	DUI
240	Mikey	mdorcey6n@goo.ne.jp	+503 7959-4833	65243292-4	DUI
241	Ruddy	rthirlwall6o@eepurl.com	+503 2330-0605	04333670-0	DUI
242	Freda	fjaffa6p@baidu.com	+503 7634-0257	57652950-9	DUI
243	Georg	gbartrop6q@cornell.edu	+503 2198-1021	91068619-2	DUI
244	Marion	mwaple6r@e-recht24.de	+503 6732-0815	31224305-1	DUI
245	Peggi	poscannill6s@vkontakte.ru	+503 6188-8365	11872667-1	DUI
246	Romeo	rdickerson6t@spiegel.de	+503 6982-8003	43827163-1	DUI
247	Winni	wburchfield6u@51.la	+503 6659-0357	50950339-7	DUI
248	Worden	wbraizier6v@seesaa.net	+503 6113-5657	75959146-7	DUI
249	Ezequiel	epoint6w@usgs.gov	+503 2173-9894	57704467-6	DUI
250	Kati	ktownrow6x@google.fr	+503 7042-2022	63552124-0	DUI
251	Caspar	choofe6y@usgs.gov	+503 7915-6438	46708087-2	DUI
252	Martie	mswalowe6z@newsvine.com	+503 6693-3167	89175045-1	DUI
253	Calley	cdelue70@51.la	+503 2791-7116	24272976-4	DUI
254	Norton	nhebblewaite71@wikimedia.org	+503 2004-1785	87728396-3	DUI
255	Justis	jquaife72@nhs.uk	+503 7764-5529	77972130-6	DUI
256	Carina	chadingham73@hc360.com	+503 2738-1125	61236823-1	DUI
257	Elsworth	ebulcroft74@ow.ly	+503 7988-2819	53645600-6	DUI
258	Lillian	ldana75@geocities.jp	+503 7452-0585	05759549-7	DUI
259	Lianna	llindup76@yahoo.co.jp	+503 2063-6930	21407988-4	DUI
260	Fiorenze	fculham77@salon.com	+503 2403-1712	36233719-7	DUI
261	Tedmund	table78@purevolume.com	+503 7001-9113	05234043-9	DUI
262	Clementia	cbabb79@zimbio.com	+503 2341-4300	80275645-4	DUI
263	Sheppard	sormond7a@lycos.com	+503 2867-8925	52559762-3	DUI
264	Garreth	gmantram7b@prnewswire.com	+503 6852-6463	70333733-9	DUI
265	Aili	abough7c@github.com	+503 6384-3890	97704935-7	DUI
266	Jere	jlavin7d@reference.com	+503 2035-7049	78274954-2	DUI
267	Roberto	rmackelworth7e@uiuc.edu	+503 6862-4995	54831970-4	DUI
268	Mureil	mgravy7f@marketwatch.com	+503 7956-0454	85334972-4	DUI
269	Tamarra	tchatin7g@myspace.com	+503 7598-7043	09154235-5	DUI
270	Jan	jbantock7h@telegraph.co.uk	+503 7883-8629	76946880-2	DUI
271	Cele	cravenhill7i@mapy.cz	+503 6801-8267	07724445-9	DUI
272	Jacques	jbeddard7j@cmu.edu	+503 2218-7549	26051169-9	DUI
273	Stormy	scavee7k@sfgate.com	+503 2160-9709	41811268-2	DUI
274	Wolf	wpurcell7l@ehow.com	+503 7343-4397	07923875-6	DUI
275	Vyky	vkeighly7m@deviantart.com	+503 6645-6109	49131490-9	DUI
276	Evelin	eshovlin7n@google.com.au	+503 2010-0490	25187528-8	DUI
277	Moore	mprivost7o@mysql.com	+503 7912-3592	57703208-1	DUI
278	Erin	estellino7p@blinklist.com	+503 7966-7040	94422774-4	DUI
279	Wilone	wfeldbrin7q@cocolog-nifty.com	+503 7205-9266	69039058-4	DUI
280	Westley	wskells7r@godaddy.com	+503 6521-4183	70510687-9	DUI
281	Towny	tbattin7s@wufoo.com	+503 6239-4160	68886735-4	DUI
282	Lishe	lguerrazzi7t@army.mil	+503 7472-0620	94693608-2	DUI
283	Rosalie	rrudeyeard7u@who.int	+503 6131-9027	02466263-0	DUI
284	Stella	schoke7v@slideshare.net	+503 2599-3804	04310244-3	DUI
285	Beverie	bpugsley7w@vistaprint.com	+503 2310-5885	53165416-8	DUI
286	Shelia	swriter7x@hao123.com	+503 7855-6770	30812512-0	DUI
287	Egor	estilly7y@businessweek.com	+503 6055-9155	69339654-6	DUI
288	Tressa	tkingswood7z@about.me	+503 2893-2139	09110903-0	DUI
289	Ida	iwinterson80@networkadvertising.org	+503 2248-3706	97700738-9	DUI
290	Andy	abamber81@illinois.edu	+503 7092-3595	89583845-1	DUI
291	Chic	clovstrom82@yelp.com	+503 2604-1157	81203910-7	DUI
292	Hoebart	hlewsey83@irs.gov	+503 7721-5931	89128463-0	DUI
293	Sophie	sblakesley84@typepad.com	+503 7541-5879	67937680-7	DUI
294	Taddeo	trosenberger85@hubpages.com	+503 2379-8892	08744058-6	DUI
295	Dmitri	dswiffen86@mozilla.org	+503 7670-3897	15011161-5	DUI
296	Finn	fwealleans87@miibeian.gov.cn	+503 2091-7113	98589088-0	DUI
297	Kipp	kmawdsley88@goo.ne.jp	+503 7006-2490	71847103-3	DUI
298	Blane	bdrable89@tinyurl.com	+503 7510-4605	02591762-1	DUI
299	Gideon	galldred8a@zdnet.com	+503 6318-0283	75504840-5	DUI
300	Zarah	zclee8b@umn.edu	+503 7732-7822	48189422-3	DUI
301	Hermina	hpeirazzi8c@blogspot.com	+503 6423-5252	54993317-5	DUI
302	Clarinda	cchipp8d@dyndns.org	+503 7881-2991	36986992-3	DUI
303	Eduino	ekintzel8e@nba.com	+503 2150-6415	72250104-4	DUI
304	Feodor	fivanisov8f@washingtonpost.com	+503 2356-3332	71004240-5	DUI
305	Adorne	aprobey8g@dagondesign.com	+503 7655-7598	67823014-1	DUI
306	Mitch	mbohlens8h@uol.com.br	+503 2779-2758	46199274-6	DUI
307	Evy	ebentham8i@tmall.com	+503 2255-0440	76106944-4	DUI
308	Deni	ddikes8j@npr.org	+503 7601-3692	79868006-2	DUI
309	Trude	tmocquer8k@wired.com	+503 2138-4043	23400379-9	DUI
310	Brenna	bcalderon8l@wired.com	+503 6558-8166	24773925-1	DUI
311	Kristi	kdelaspee8m@accuweather.com	+503 2840-0218	65655108-0	DUI
312	Katrinka	kcosley8n@phoca.cz	+503 7630-4940	77124742-6	DUI
313	Barris	bprobbings8o@edublogs.org	+503 2418-0331	78542250-8	DUI
314	Ingeborg	isharpin8p@constantcontact.com	+503 6592-7553	16100298-5	DUI
315	Leeann	lmundwell8q@sakura.ne.jp	+503 6373-9929	03257382-0	DUI
316	Waly	wgalpen8r@drupal.org	+503 7452-1530	37633589-1	DUI
317	Lorita	lkedwell8s@reddit.com	+503 7474-2562	02203604-3	DUI
318	Karola	kmcowan8t@merriam-webster.com	+503 6066-7280	67375411-3	DUI
319	Bernardo	bpinney8u@eventbrite.com	+503 6017-1182	60075758-9	DUI
320	Laurice	lgiveen8v@godaddy.com	+503 6411-7418	19461664-6	DUI
321	Morris	mscard8w@google.nl	+503 7685-1948	70946276-1	DUI
322	Raynell	rluchelli8x@yolasite.com	+503 7775-4589	10098812-9	DUI
323	Pru	pvasilyevski8y@liveinternet.ru	+503 6356-4559	35684764-2	DUI
324	Dyana	depton8z@naver.com	+503 6937-0671	77342878-5	DUI
325	Mufi	mvelte90@sphinn.com	+503 2609-2227	25851522-2	DUI
326	Clemente	cgransden91@dailymotion.com	+503 2222-2409	66151660-8	DUI
327	Caroline	cellson92@reverbnation.com	+503 7308-2485	48880203-9	DUI
328	Conchita	cblanpein93@loc.gov	+503 6427-1497	86395892-1	DUI
329	Marcelia	mgyrgorcewicx94@bluehost.com	+503 2256-5000	81148940-4	DUI
330	Eugenie	ehubbins95@yelp.com	+503 7599-5189	92623783-6	DUI
331	Theresina	tbrecknell96@bloglines.com	+503 2190-9738	40865792-6	DUI
332	Roch	rbahls97@npr.org	+503 6752-9434	56047031-1	DUI
333	Vivianna	vstiell98@joomla.org	+503 6314-6909	70496227-1	DUI
334	Cazzie	cdow99@nyu.edu	+503 2595-6120	91527503-5	DUI
335	Onofredo	oridel9a@google.pl	+503 7976-1629	97513150-6	DUI
336	Tammy	tmillican9b@time.com	+503 2061-0660	77487257-7	DUI
337	Waldo	wbriereton9c@edublogs.org	+503 2757-9973	52918078-8	DUI
338	Ambrose	aambrosio9d@tamu.edu	+503 6849-1132	12463458-8	DUI
339	Georgianne	gkubek9e@godaddy.com	+503 2074-3323	31900097-3	DUI
340	Brand	bbortolini9f@squidoo.com	+503 6920-6314	85942257-5	DUI
341	Brit	bsiward9g@uol.com.br	+503 2117-0404	10285397-0	DUI
342	Rachel	rskipsey9h@hp.com	+503 7817-7298	82904878-1	DUI
343	Kimball	kairton9i@domainmarket.com	+503 2823-2827	72285066-7	DUI
344	Gratiana	gguly9j@jigsy.com	+503 2338-1424	58854226-1	DUI
345	Concettina	cswanne9k@miitbeian.gov.cn	+503 7581-8298	44797321-1	DUI
346	Rana	rbraiden9l@is.gd	+503 7039-7142	47550404-8	DUI
347	Ara	astrathe9m@nyu.edu	+503 2213-7944	27228073-5	DUI
348	Cosetta	cdownham9n@addtoany.com	+503 6631-1335	87750582-6	DUI
349	Ted	tsayward9o@nps.gov	+503 6575-7170	97117070-7	DUI
350	Lavinia	lcoker9p@slate.com	+503 2910-7791	00311914-8	DUI
351	Jeni	jmabbe9q@phoca.cz	+503 2895-5480	92963777-9	DUI
352	Selig	sbrocket9r@amazon.co.jp	+503 7345-4461	55801317-7	DUI
353	Floria	fprudham9s@edublogs.org	+503 6722-2709	89448590-5	DUI
354	Gert	gblackster9t@microsoft.com	+503 2697-4220	16656503-3	DUI
355	Kaine	kmateu9u@shinystat.com	+503 2303-8763	90248241-6	DUI
356	Andris	avines9v@cdc.gov	+503 7216-3737	22621860-0	DUI
357	Travus	tkaindl9w@paypal.com	+503 6910-5399	38041112-3	DUI
358	Lida	lwilcher9x@friendfeed.com	+503 7449-3135	42298465-5	DUI
359	Elyse	ekimmins9y@skyrock.com	+503 7938-5593	72681062-9	DUI
360	Sauveur	shurtic9z@mapquest.com	+503 2928-7120	70002287-6	DUI
361	Claudina	cscoatesa0@com.com	+503 6932-0623	36694606-6	DUI
362	Shantee	shurseya1@psu.edu	+503 6658-6779	99145198-7	DUI
363	Delcine	dmarrinera2@sogou.com	+503 7016-4925	52095497-8	DUI
364	Gretta	gbernardeaua3@auda.org.au	+503 2816-8963	94230934-7	DUI
365	Solomon	sgladdora4@purevolume.com	+503 2272-3973	97480502-1	DUI
366	Sergent	sgregora5@histats.com	+503 7479-7056	88381343-5	DUI
367	Thibaud	tduddridgea6@reference.com	+503 7301-3288	66129521-3	DUI
368	Ninetta	nbowyera7@bluehost.com	+503 7447-2408	10159232-2	DUI
369	Ravid	rvinicka8@constantcontact.com	+503 7976-6991	40668770-8	DUI
370	Morry	mbrillemana9@msn.com	+503 2367-2080	82758037-4	DUI
371	Christoforo	cgillaniaa@bigcartel.com	+503 2355-5879	30620518-5	DUI
372	Jamey	jhonnicottab@opensource.org	+503 7318-7314	86995803-8	DUI
373	Felipe	fstockleac@4shared.com	+503 2197-5206	99112637-6	DUI
374	Delora	dprettjohnad@washingtonpost.com	+503 6500-2822	30478993-5	DUI
375	Gregg	ggavahanae@addthis.com	+503 7092-2846	24268895-9	DUI
376	Dayna	dwestwateraf@smugmug.com	+503 7871-7016	10075605-0	DUI
377	Dav	dpundyag@bandcamp.com	+503 7660-8969	02635087-5	DUI
378	Beitris	bstuckah@engadget.com	+503 7565-4687	75029214-1	DUI
379	Norah	ncancellerai@cyberchimps.com	+503 7079-6493	71626557-9	DUI
380	Starr	sverrieraj@craigslist.org	+503 7740-8365	07302073-2	DUI
381	Cthrine	cwrenchak@nsw.gov.au	+503 6684-0681	62221805-5	DUI
382	Lyda	lostrichal@dedecms.com	+503 7915-8448	32232026-9	DUI
383	Clint	cswindinam@cnbc.com	+503 7357-5249	38971941-3	DUI
384	Gwenni	ggallyhaockan@godaddy.com	+503 2902-6335	65377995-2	DUI
385	Arluene	agappao@yelp.com	+503 2305-0392	25567990-6	DUI
386	Arni	alewinsap@nps.gov	+503 7544-7099	91289484-2	DUI
387	Orlando	obackshillaq@posterous.com	+503 2501-1564	33928302-9	DUI
388	Rosalinda	rfraschiniar@studiopress.com	+503 7023-5040	94657668-8	DUI
389	Cleveland	chalmsas@free.fr	+503 7780-8379	57021364-0	DUI
390	Brynn	bethelstonat@cbsnews.com	+503 6831-6368	29270467-1	DUI
391	Megan	mzanettiniau@acquirethisname.com	+503 6524-5734	78807856-9	DUI
392	Dwayne	djiruav@rakuten.co.jp	+503 6628-2401	99685476-9	DUI
393	Rosaleen	rbrandenburgaw@skype.com	+503 2992-6181	00767572-2	DUI
394	Stanislaus	spestridgeax@hc360.com	+503 2401-8117	00952570-6	DUI
395	Jenny	jglennay@yale.edu	+503 2174-9899	94674083-2	DUI
396	Kent	kdifranceschiaz@amazon.co.uk	+503 7846-8632	42946934-5	DUI
397	Thom	ttwiggeb0@soup.io	+503 2922-6518	74974067-5	DUI
398	Lorilee	lnisbyb1@reuters.com	+503 6880-8637	72001825-0	DUI
399	Addi	ablaxtonb2@smh.com.au	+503 2280-3181	86786583-3	DUI
400	Thain	tphilb3@hibu.com	+503 6755-2872	58370178-3	DUI
401	Addie	amillsomb4@pbs.org	+503 7630-2031	42874248-5	DUI
402	Issie	ibengtsenb5@businessweek.com	+503 6574-0120	45410004-4	DUI
403	Brenda	bantoniob6@privacy.gov.au	+503 6251-5434	28054628-0	DUI
404	Reinwald	ronyonb7@huffingtonpost.com	+503 7978-7986	34082500-7	DUI
405	Gillian	gbarkasb8@ucsd.edu	+503 2768-7101	02744096-1	DUI
406	Kaspar	kdellabbateb9@amazon.com	+503 2275-5363	19208911-4	DUI
407	Rafferty	rbeadeba@mashable.com	+503 7407-0167	61847531-5	DUI
408	Fredia	fmacgianybb@cocolog-nifty.com	+503 7929-9902	21998503-1	DUI
409	Damita	dpoppletonbc@dell.com	+503 7874-5726	88624551-9	DUI
410	Falkner	ffuentebd@miitbeian.gov.cn	+503 6447-8639	61730151-1	DUI
411	Zilvia	zquantrellbe@123-reg.co.uk	+503 7032-3405	28176653-7	DUI
412	Rosemonde	rogarabf@google.com.br	+503 7099-6960	97288279-8	DUI
413	Tandie	tdemchenbg@ebay.com	+503 7758-4034	69731418-3	DUI
414	Robby	rbraunleinbh@narod.ru	+503 7875-8377	70495913-2	DUI
415	Maison	mclowserbi@miibeian.gov.cn	+503 2620-6599	63758316-9	DUI
416	Heidi	hbehrendsenbj@liveinternet.ru	+503 6747-6602	02709880-7	DUI
417	Angel	agrubbebk@i2i.jp	+503 6995-8169	49822518-6	DUI
418	Carling	cpittendreighbl@cpanel.net	+503 7850-0640	85657641-3	DUI
419	Smith	siamittiibm@creativecommons.org	+503 7736-7167	36364976-7	DUI
420	Pavel	pmcginleybn@4shared.com	+503 6463-1716	53010167-8	DUI
421	Lark	lwheildonbo@msn.com	+503 6254-5562	54706925-4	DUI
422	Tedda	torvissbp@va.gov	+503 6577-3992	87975272-1	DUI
423	Rosana	rlorrymanbq@cmu.edu	+503 7436-4029	21432657-6	DUI
424	Lockwood	lcarriagebr@webeden.co.uk	+503 7659-2050	30378706-5	DUI
425	Rosmunda	rdanickbs@fda.gov	+503 6297-4969	99815571-5	DUI
426	Tynan	trennickbt@etsy.com	+503 7142-8057	52083892-7	DUI
427	Early	eknoxbu@gmpg.org	+503 6784-3215	79133538-5	DUI
428	Danice	dcrosskillbv@domainmarket.com	+503 6901-3743	15706655-6	DUI
429	Fredrika	fgraundissonbw@harvard.edu	+503 2239-2733	40977797-0	DUI
430	Garrard	gdupreebx@weather.com	+503 2198-6728	06735800-0	DUI
431	Coraline	csummersby@springer.com	+503 6360-3406	16992751-6	DUI
432	Rodi	rprandybz@nytimes.com	+503 6566-1167	93539429-1	DUI
433	Babita	brodgersonc0@unesco.org	+503 2468-4952	15556904-4	DUI
434	Juliann	jjodrellecc1@slideshare.net	+503 7699-4847	14976299-2	DUI
435	Terrie	tdundinc2@furl.net	+503 7088-9613	15204291-4	DUI
436	Gaby	gfreschinic3@hexun.com	+503 7290-8923	54860109-4	DUI
437	Nevin	ntinklinc4@1688.com	+503 6694-3637	19430177-5	DUI
438	Ardra	atarquinioc5@theglobeandmail.com	+503 7332-4873	79646316-2	DUI
439	Madison	marrundalec6@nature.com	+503 7341-7217	21460373-6	DUI
440	Tania	thallutc7@themeforest.net	+503 7392-2440	31742405-1	DUI
441	Ennis	emamwellc8@un.org	+503 6071-1084	39266012-5	DUI
442	Nicky	nansettc9@so-net.ne.jp	+503 7682-9739	46798666-1	DUI
443	Wandie	wlyndsca@hugedomains.com	+503 6516-5743	52604383-1	DUI
444	Lynda	lfirkcb@meetup.com	+503 6135-0637	27008083-6	DUI
445	Keir	knuddscc@bing.com	+503 6363-3915	79437875-4	DUI
446	Abagail	agurrycd@vkontakte.ru	+503 2100-6373	01226581-4	DUI
447	Lovell	lglassmance@google.cn	+503 7052-8126	60724079-3	DUI
448	Adamo	adrakecf@miitbeian.gov.cn	+503 7274-3227	36388312-2	DUI
449	Daryle	dhaskeycg@sphinn.com	+503 7555-7066	08789101-1	DUI
450	Brooke	bbrattench@parallels.com	+503 2751-7286	86112441-8	DUI
451	Kylie	kmencoci@walmart.com	+503 7315-6340	67285512-8	DUI
452	Roda	rbergstrandcj@last.fm	+503 2219-1255	06333021-0	DUI
453	Abbye	abennionck@posterous.com	+503 2790-3461	12453069-8	DUI
454	Victoria	vtankuscl@google.it	+503 2437-4135	10204441-7	DUI
455	Alon	ablankocm@hp.com	+503 7574-9034	44294090-2	DUI
456	Algernon	adahlbergcn@arizona.edu	+503 6316-7344	29209943-6	DUI
457	Emelia	eloryco@wiley.com	+503 2507-1490	43745574-3	DUI
458	Cordula	cbrutycp@indiegogo.com	+503 6421-3000	84719370-4	DUI
459	Silvester	sglantzcq@eventbrite.com	+503 6535-0771	53997444-3	DUI
460	Cointon	cburdcr@flavors.me	+503 7866-1066	70470759-4	DUI
461	Marchelle	mcromackcs@reference.com	+503 2296-0802	38928773-3	DUI
462	Raf	rwaddellct@live.com	+503 7096-6721	91860811-5	DUI
463	Ealasaid	eciepluchcu@statcounter.com	+503 2435-8497	52877937-0	DUI
464	Monika	mwolstenholmecv@google.de	+503 7353-7225	62309768-9	DUI
465	Abby	acamplejohncw@weebly.com	+503 7636-2748	73913845-0	DUI
466	Carlynne	cianinotticx@facebook.com	+503 2097-0985	10229433-0	DUI
467	Bud	bpotzoldcy@soup.io	+503 7393-2620	39248527-9	DUI
468	Celle	cmadderscz@eventbrite.com	+503 6811-8294	88598355-4	DUI
469	Pat	pebdend0@paginegialle.it	+503 7845-5841	52028645-5	DUI
470	Aliza	areschked1@cnet.com	+503 2282-6532	50036283-1	DUI
471	Elvin	etonged2@sciencedirect.com	+503 6477-8793	80695399-8	DUI
472	Hanson	hlyburnd3@addthis.com	+503 7977-0595	85543785-1	DUI
473	Perren	pgusneyd4@rediff.com	+503 6911-9282	48115191-4	DUI
474	Hussein	hastleyd5@blogtalkradio.com	+503 2010-6757	84978704-7	DUI
475	Arnie	awhettletond6@ow.ly	+503 6444-6057	60011423-9	DUI
476	Vickie	vbattingd7@blogspot.com	+503 2163-8613	43104317-8	DUI
477	Rutherford	rchennellsd8@washingtonpost.com	+503 7129-0517	47606984-4	DUI
478	Pauli	pmarnaned9@google.ru	+503 6575-9055	02390666-4	DUI
479	Cecil	ckasparskida@netlog.com	+503 2240-2582	21842898-2	DUI
480	Tamas	thargessdb@dailymotion.com	+503 6023-4769	72804067-4	DUI
481	Hadrian	hbillsondc@auda.org.au	+503 7042-4876	36096543-5	DUI
482	Brynn	bhedindd@businesswire.com	+503 6563-3868	19158428-8	DUI
483	Roger	rdelagnesde@privacy.gov.au	+503 7558-1721	11592425-0	DUI
484	Mamie	mpowedf@sciencedirect.com	+503 7719-4676	11935607-3	DUI
485	Granger	gshinedg@twitter.com	+503 6573-3804	35124486-6	DUI
486	Caryl	ccourceydh@domainmarket.com	+503 7440-7163	43352644-6	DUI
487	Korrie	kbogaysdi@ucsd.edu	+503 2514-2837	43906726-7	DUI
488	Nara	nfinkledj@freewebs.com	+503 2983-6053	95857223-0	DUI
489	Cyndy	csabaterdk@sciencedaily.com	+503 7182-6649	98936241-6	DUI
490	Ignazio	icreekdl@seesaa.net	+503 7351-0040	69341742-6	DUI
491	Orazio	onelmdm@163.com	+503 2933-0757	13827918-7	DUI
492	Amalle	aghidettidn@addtoany.com	+503 7522-7406	99968749-1	DUI
493	Lacey	lhammerichdo@sbwire.com	+503 6152-6723	12183574-3	DUI
494	Sioux	smcpheatdp@yahoo.co.jp	+503 6522-0383	36758288-3	DUI
495	Magdaia	msiddledq@instagram.com	+503 2596-5914	69798500-6	DUI
496	Cornie	cgoodwyndr@twitpic.com	+503 6017-5581	80477881-3	DUI
497	Graig	gludovicids@omniture.com	+503 7763-9971	94831760-2	DUI
498	Randolph	rlynaghdt@storify.com	+503 7987-7781	74532945-3	DUI
499	Terencio	tgynnidu@huffingtonpost.com	+503 7399-7338	57862350-7	DUI
500	Dolf	dburstowdv@sbwire.com	+503 6018-9588	73235307-7	DUI
501	Yelena	ythomasen0@ning.com	+503 2574-9885	RES-SV-455762172	CONSTANCIA DE RESIDENCIA
502	Bil	bdudek1@europa.eu	+503 2062-8752	RES-SV-779085	CONSTANCIA DE RESIDENCIA
503	Gwenny	glindelof2@rediff.com	+503 2766-7273	RES-SV-774032	CONSTANCIA DE RESIDENCIA
504	Trudi	triddlesden3@bbc.co.uk	+503 7788-2148	RES-SV-29663245	CONSTANCIA DE RESIDENCIA
505	Steffane	slathom4@vkontakte.ru	+503 6250-9287	RES-SV-401762943	CONSTANCIA DE RESIDENCIA
506	Murdoch	mmawman5@smugmug.com	+503 7354-8883	RES-SV-940274310	CONSTANCIA DE RESIDENCIA
507	Mackenzie	mgrzelczyk6@buzzfeed.com	+503 6155-6301	RES-SV-759882538	CONSTANCIA DE RESIDENCIA
508	Dannye	dkrug7@statcounter.com	+503 6127-7219	RES-SV-820680	CONSTANCIA DE RESIDENCIA
509	Griffy	ggheraldi8@statcounter.com	+503 6858-8291	RES-SV-7037940	CONSTANCIA DE RESIDENCIA
510	Lorant	lvasyatkin9@netlog.com	+503 2324-7653	RES-SV-642104	CONSTANCIA DE RESIDENCIA
511	Tallie	tkuhlena@prlog.org	+503 7280-8075	RES-SV-822861	CONSTANCIA DE RESIDENCIA
512	Moore	mdanickb@wordpress.com	+503 2369-1880	RES-SV-2771991	CONSTANCIA DE RESIDENCIA
513	Libby	lyakebovitchc@usgs.gov	+503 7828-0118	RES-SV-114894675	CONSTANCIA DE RESIDENCIA
514	Marietta	msunnersd@furl.net	+503 6372-5420	RES-SV-151213758	CONSTANCIA DE RESIDENCIA
515	Bartlett	bbarczewskie@delicious.com	+503 7901-4993	RES-SV-2135158	CONSTANCIA DE RESIDENCIA
516	Katya	kandreolettif@surveymonkey.com	+503 2424-6683	RES-SV-3425454	CONSTANCIA DE RESIDENCIA
517	Sileas	ssailerg@reddit.com	+503 7876-1392	RES-SV-95132841	CONSTANCIA DE RESIDENCIA
518	Moses	mmcmurrughh@vimeo.com	+503 6785-0911	RES-SV-531828	CONSTANCIA DE RESIDENCIA
519	Chevalier	cgilfoylei@quantcast.com	+503 6696-5858	RES-SV-962792700	CONSTANCIA DE RESIDENCIA
520	Torin	tkieferj@smugmug.com	+503 2988-2030	RES-SV-278556276	CONSTANCIA DE RESIDENCIA
521	Galen	ggoodbodyk@merriam-webster.com	+503 6112-6590	RES-SV-827269	CONSTANCIA DE RESIDENCIA
522	Cliff	cisabelll@so-net.ne.jp	+503 6676-6275	RES-SV-2891911	CONSTANCIA DE RESIDENCIA
523	Pamelina	pcoppinm@google.com	+503 6318-2657	RES-SV-8228110	CONSTANCIA DE RESIDENCIA
524	Mendie	mcholdcroftn@gov.uk	+503 7418-4181	RES-SV-92022872	CONSTANCIA DE RESIDENCIA
525	Beverie	bheintzscho@chicagotribune.com	+503 2016-4892	RES-SV-2575820	CONSTANCIA DE RESIDENCIA
526	Luella	lummfreyp@twitter.com	+503 6584-7994	RES-SV-487342054	CONSTANCIA DE RESIDENCIA
527	Hatti	hsalkildq@blog.com	+503 7524-6721	RES-SV-673926894	CONSTANCIA DE RESIDENCIA
528	Maddie	mtottier@phoca.cz	+503 6914-9031	RES-SV-91439162	CONSTANCIA DE RESIDENCIA
529	Clim	crosentholers@unesco.org	+503 7669-5248	RES-SV-02124954	CONSTANCIA DE RESIDENCIA
530	Brocky	bthreadgouldt@over-blog.com	+503 6289-3436	RES-SV-7793251	CONSTANCIA DE RESIDENCIA
531	Matthaeus	mpeggremu@msu.edu	+503 6777-0035	RES-SV-704849	CONSTANCIA DE RESIDENCIA
532	Pail	pbelonev@hostgator.com	+503 2496-1656	RES-SV-042574	CONSTANCIA DE RESIDENCIA
533	Marleah	mjicklesw@earthlink.net	+503 6789-6912	RES-SV-7766405	CONSTANCIA DE RESIDENCIA
534	Vivyanne	vcouzensx@sitemeter.com	+503 2620-7898	RES-SV-622358	CONSTANCIA DE RESIDENCIA
535	Jedediah	jbuggy@nhs.uk	+503 2397-8107	RES-SV-5307734	CONSTANCIA DE RESIDENCIA
536	Bernie	bninehamz@odnoklassniki.ru	+503 2283-3180	RES-SV-443666979	CONSTANCIA DE RESIDENCIA
537	Kingsly	kminithorpe10@springer.com	+503 7595-7518	RES-SV-353761429	CONSTANCIA DE RESIDENCIA
538	Jewell	jwhyman11@booking.com	+503 2855-7156	RES-SV-830598	CONSTANCIA DE RESIDENCIA
539	Lutero	lsandcroft12@springer.com	+503 7319-9661	RES-SV-3560137	CONSTANCIA DE RESIDENCIA
540	Bone	bdelamere13@ow.ly	+503 6827-1297	RES-SV-6426437	CONSTANCIA DE RESIDENCIA
541	Charisse	cigonet14@usa.gov	+503 7762-9779	RES-SV-37421845	CONSTANCIA DE RESIDENCIA
542	Siana	scartmel15@seesaa.net	+503 2571-0770	RES-SV-8906773	CONSTANCIA DE RESIDENCIA
543	Jamesy	jwelham16@lycos.com	+503 2459-8380	RES-SV-2006608	CONSTANCIA DE RESIDENCIA
544	Egon	epavelin17@sourceforge.net	+503 7656-7883	RES-SV-256165	CONSTANCIA DE RESIDENCIA
545	Karla	khammonds18@apple.com	+503 7729-6712	RES-SV-32697168	CONSTANCIA DE RESIDENCIA
546	Fulton	fshall19@vinaora.com	+503 7428-8471	RES-SV-899785	CONSTANCIA DE RESIDENCIA
547	Susanetta	scanfield1a@msn.com	+503 6971-5106	RES-SV-04728369	CONSTANCIA DE RESIDENCIA
548	Tamas	tjozaitis1b@timesonline.co.uk	+503 6366-4143	RES-SV-08098824	CONSTANCIA DE RESIDENCIA
549	Allyn	atortice1c@oakley.com	+503 2253-7374	RES-SV-5709877	CONSTANCIA DE RESIDENCIA
550	Hebert	hhuyge1d@digg.com	+503 7161-0104	RES-SV-8386860	CONSTANCIA DE RESIDENCIA
551	Frants	fkleine1e@shop-pro.jp	+503 7316-5580	RES-SV-17700343	CONSTANCIA DE RESIDENCIA
552	Cammi	cdyble1f@netlog.com	+503 2155-1232	RES-SV-811169807	CONSTANCIA DE RESIDENCIA
553	Arleen	aantonellini1g@1und1.de	+503 7951-8337	RES-SV-367559833	CONSTANCIA DE RESIDENCIA
554	Buffy	bdinsell1h@nsw.gov.au	+503 7240-9698	RES-SV-61767986	CONSTANCIA DE RESIDENCIA
555	Kiley	kamesbury1i@nymag.com	+503 2776-4802	RES-SV-87544150	CONSTANCIA DE RESIDENCIA
994	Bryanty	bladdle85@wp.com	+503 7522-4296	A37395948	PASAPORTE
556	Marge	mtwyning1j@prweb.com	+503 6962-8844	RES-SV-1710489	CONSTANCIA DE RESIDENCIA
557	Augusta	ariquet1k@mac.com	+503 6239-8359	RES-SV-5400240	CONSTANCIA DE RESIDENCIA
558	Jarrett	jlyles1l@vk.com	+503 2990-2506	RES-SV-0524702	CONSTANCIA DE RESIDENCIA
559	Worden	wlatey1m@nytimes.com	+503 2357-6368	RES-SV-547347	CONSTANCIA DE RESIDENCIA
560	Shaine	srivett1n@liveinternet.ru	+503 6429-1222	RES-SV-154697	CONSTANCIA DE RESIDENCIA
561	Golda	gsnare1o@ehow.com	+503 7340-2760	RES-SV-394070806	CONSTANCIA DE RESIDENCIA
562	Damian	dfawcitt1p@drupal.org	+503 2423-9248	RES-SV-9134808	CONSTANCIA DE RESIDENCIA
563	Johnna	jmcilwain1q@admin.ch	+503 7365-4943	RES-SV-332562498	CONSTANCIA DE RESIDENCIA
564	Monro	mpetrillo1r@blinklist.com	+503 2798-4464	RES-SV-87842357	CONSTANCIA DE RESIDENCIA
565	Nollie	nmarris1s@1688.com	+503 7188-4159	RES-SV-338778	CONSTANCIA DE RESIDENCIA
566	Sunny	sandrault1t@1688.com	+503 6670-8648	RES-SV-4176110	CONSTANCIA DE RESIDENCIA
567	Nadean	nsterte1u@i2i.jp	+503 6398-7408	RES-SV-6441851	CONSTANCIA DE RESIDENCIA
568	Dickie	ddelacroux1v@patch.com	+503 2282-3146	RES-SV-879532	CONSTANCIA DE RESIDENCIA
569	Kellina	kpuckham1w@reddit.com	+503 6840-6893	RES-SV-0967354	CONSTANCIA DE RESIDENCIA
570	Merwin	mbohl1x@senate.gov	+503 6983-9536	RES-SV-453305	CONSTANCIA DE RESIDENCIA
571	Harcourt	hcopins1y@myspace.com	+503 2603-6836	RES-SV-694471508	CONSTANCIA DE RESIDENCIA
572	Natasha	nroughey1z@xrea.com	+503 2301-8462	RES-SV-561578595	CONSTANCIA DE RESIDENCIA
573	Bart	bbaxster20@patch.com	+503 6259-8799	RES-SV-7739697	CONSTANCIA DE RESIDENCIA
574	Robin	rbonhan21@ca.gov	+503 7481-5926	RES-SV-3748699	CONSTANCIA DE RESIDENCIA
575	Yale	yderry22@wufoo.com	+503 2707-7972	RES-SV-535640713	CONSTANCIA DE RESIDENCIA
576	Enrique	ejenkison23@ed.gov	+503 6998-4321	RES-SV-506240202	CONSTANCIA DE RESIDENCIA
577	Durward	dmariel24@wordpress.com	+503 7819-2104	RES-SV-0513892	CONSTANCIA DE RESIDENCIA
578	Alard	alongmead25@bravesites.com	+503 2533-0667	RES-SV-66223334	CONSTANCIA DE RESIDENCIA
579	Gan	gdreschler26@forbes.com	+503 2152-2582	RES-SV-4865675	CONSTANCIA DE RESIDENCIA
580	Odie	opetrushka27@toplist.cz	+503 2163-5427	RES-SV-005465	CONSTANCIA DE RESIDENCIA
581	Cayla	cshout28@blogger.com	+503 2293-8630	RES-SV-011181	CONSTANCIA DE RESIDENCIA
582	Ardys	achapelhow29@bluehost.com	+503 6682-2887	RES-SV-757095895	CONSTANCIA DE RESIDENCIA
583	Yoko	yreubens2a@foxnews.com	+503 6123-9661	RES-SV-593523	CONSTANCIA DE RESIDENCIA
584	Loraine	llobell2b@amazon.com	+503 2944-5016	RES-SV-63220856	CONSTANCIA DE RESIDENCIA
585	Pearline	pkitchen2c@spiegel.de	+503 6385-6527	RES-SV-57360410	CONSTANCIA DE RESIDENCIA
586	Yasmeen	yyashunin2d@digg.com	+503 2265-0700	RES-SV-592632766	CONSTANCIA DE RESIDENCIA
587	Neely	nstarking2e@alexa.com	+503 7823-4369	RES-SV-0525985	CONSTANCIA DE RESIDENCIA
588	Forbes	fcoyte2f@sfgate.com	+503 6201-8206	RES-SV-8626849	CONSTANCIA DE RESIDENCIA
589	Lorry	lsmallcomb2g@ihg.com	+503 7029-5736	RES-SV-6028539	CONSTANCIA DE RESIDENCIA
590	Hildagarde	hgraveney2h@digg.com	+503 2027-8368	RES-SV-973913780	CONSTANCIA DE RESIDENCIA
591	Henriette	hodoogan2i@jiathis.com	+503 6622-9336	RES-SV-47523837	CONSTANCIA DE RESIDENCIA
592	Candra	cbermingham2j@stumbleupon.com	+503 6364-2175	RES-SV-336170469	CONSTANCIA DE RESIDENCIA
593	Vivien	vaubry2k@nyu.edu	+503 7073-1708	RES-SV-617332472	CONSTANCIA DE RESIDENCIA
594	Dari	dstalman2l@e-recht24.de	+503 6242-0192	RES-SV-473374384	CONSTANCIA DE RESIDENCIA
595	Markos	mocodihie2m@gravatar.com	+503 7773-6360	RES-SV-284509	CONSTANCIA DE RESIDENCIA
596	Bennie	bgreenless2n@goodreads.com	+503 7344-6123	RES-SV-486665676	CONSTANCIA DE RESIDENCIA
597	Janeta	jscanes2o@t.co	+503 2299-5999	RES-SV-7489240	CONSTANCIA DE RESIDENCIA
598	Otho	ocoolahan2p@google.pl	+503 2765-3502	RES-SV-47385418	CONSTANCIA DE RESIDENCIA
599	Alf	aplowman2q@clickbank.net	+503 6795-3047	RES-SV-3077417	CONSTANCIA DE RESIDENCIA
600	Eldridge	etaphouse2r@phpbb.com	+503 2301-7161	RES-SV-022785156	CONSTANCIA DE RESIDENCIA
601	Noelle	nsivyour2s@about.com	+503 6171-3738	RES-SV-379462	CONSTANCIA DE RESIDENCIA
602	Hedvig	hollerearnshaw2t@mozilla.org	+503 2689-4430	RES-SV-186277	CONSTANCIA DE RESIDENCIA
603	Bettina	bbirkwood2u@miibeian.gov.cn	+503 7379-2228	RES-SV-823064149	CONSTANCIA DE RESIDENCIA
604	Kessiah	kcharley2v@macromedia.com	+503 6540-9330	RES-SV-575528	CONSTANCIA DE RESIDENCIA
605	Jarib	jhagger2w@tiny.cc	+503 2832-6245	RES-SV-579740	CONSTANCIA DE RESIDENCIA
606	Timotheus	tleate2x@squarespace.com	+503 2935-5855	RES-SV-516754291	CONSTANCIA DE RESIDENCIA
607	Consolata	cjakolevitch2y@nsw.gov.au	+503 6806-4674	RES-SV-53637492	CONSTANCIA DE RESIDENCIA
608	Charlean	cruffles2z@chicagotribune.com	+503 2246-0750	RES-SV-24389188	CONSTANCIA DE RESIDENCIA
609	Linnet	livanonko30@behance.net	+503 7365-3169	RES-SV-99734695	CONSTANCIA DE RESIDENCIA
610	Shannon	sdurbridge31@mail.ru	+503 7595-0421	RES-SV-751738963	CONSTANCIA DE RESIDENCIA
611	Carmita	cmeese32@qq.com	+503 7960-4107	RES-SV-23347514	CONSTANCIA DE RESIDENCIA
612	Simone	skibble33@cam.ac.uk	+503 2022-1706	RES-SV-236234475	CONSTANCIA DE RESIDENCIA
613	Mervin	mpendleberry34@feedburner.com	+503 2658-9222	RES-SV-284241168	CONSTANCIA DE RESIDENCIA
614	Hakeem	hagney35@usgs.gov	+503 7350-1364	RES-SV-226684247	CONSTANCIA DE RESIDENCIA
615	Callida	cawcock36@desdev.cn	+503 6732-7604	RES-SV-77051518	CONSTANCIA DE RESIDENCIA
616	Harlene	hreicharz37@bluehost.com	+503 7290-3329	RES-SV-048209	CONSTANCIA DE RESIDENCIA
617	Etty	egrimmett38@mysql.com	+503 2763-9907	RES-SV-13733275	CONSTANCIA DE RESIDENCIA
618	Floria	fcallar39@tripadvisor.com	+503 7406-9139	RES-SV-14188472	CONSTANCIA DE RESIDENCIA
619	Irvine	irawlins3a@sun.com	+503 6870-4086	RES-SV-140631	CONSTANCIA DE RESIDENCIA
620	Hilly	hdallander3b@naver.com	+503 2567-7869	RES-SV-540501461	CONSTANCIA DE RESIDENCIA
621	Gill	ghubbucke3c@vkontakte.ru	+503 2443-2281	RES-SV-708019	CONSTANCIA DE RESIDENCIA
622	Anissa	arankcom3d@arizona.edu	+503 6181-5239	RES-SV-563219390	CONSTANCIA DE RESIDENCIA
623	Kayle	kcurlis3e@google.cn	+503 2448-5838	RES-SV-9278260	CONSTANCIA DE RESIDENCIA
624	Jane	jcultcheth3f@census.gov	+503 7124-0216	RES-SV-134364	CONSTANCIA DE RESIDENCIA
625	Godiva	gmaffucci3g@youtube.com	+503 2733-7793	RES-SV-0931129	CONSTANCIA DE RESIDENCIA
626	Dory	dgerald3h@miibeian.gov.cn	+503 6827-2321	RES-SV-98161911	CONSTANCIA DE RESIDENCIA
627	Jerad	jgradon3i@businesswire.com	+503 7020-1567	RES-SV-4626426	CONSTANCIA DE RESIDENCIA
628	Kincaid	kfolomin3j@tumblr.com	+503 2231-2704	RES-SV-590651	CONSTANCIA DE RESIDENCIA
629	Selena	sgasnoll3k@hubpages.com	+503 6890-8339	RES-SV-330434718	CONSTANCIA DE RESIDENCIA
630	Fionna	felstow3l@chicagotribune.com	+503 2431-0289	RES-SV-2429362	CONSTANCIA DE RESIDENCIA
631	Hetty	hleavry3m@netvibes.com	+503 7053-2668	RES-SV-7618268	CONSTANCIA DE RESIDENCIA
632	Wolfgang	wnutter3n@spotify.com	+503 6356-1738	RES-SV-135835568	CONSTANCIA DE RESIDENCIA
633	Jack	jnorthen3o@scribd.com	+503 7720-0577	RES-SV-682228	CONSTANCIA DE RESIDENCIA
634	Patrizia	pmaro3p@constantcontact.com	+503 7498-2349	RES-SV-244019379	CONSTANCIA DE RESIDENCIA
635	Cassondra	cwillicott3q@sogou.com	+503 2371-5101	RES-SV-9943587	CONSTANCIA DE RESIDENCIA
636	Bel	bschultheiss3r@illinois.edu	+503 2390-4553	RES-SV-641037	CONSTANCIA DE RESIDENCIA
637	Lonnie	llorking3s@umn.edu	+503 2302-3579	RES-SV-405396168	CONSTANCIA DE RESIDENCIA
638	Cly	cnilles3t@va.gov	+503 6195-2658	RES-SV-699677	CONSTANCIA DE RESIDENCIA
639	Gav	ghalgarth3u@wp.com	+503 2171-5240	RES-SV-222768	CONSTANCIA DE RESIDENCIA
640	Fleming	fbaton3v@tripod.com	+503 2526-2687	RES-SV-48298719	CONSTANCIA DE RESIDENCIA
641	Arleen	ahalward3w@joomla.org	+503 7128-6975	RES-SV-9546472	CONSTANCIA DE RESIDENCIA
642	Gilbertine	gletertre3x@telegraph.co.uk	+503 6090-2102	RES-SV-19203622	CONSTANCIA DE RESIDENCIA
643	Quentin	qmouatt3y@mapy.cz	+503 7233-8973	RES-SV-02726067	CONSTANCIA DE RESIDENCIA
644	Lind	ltorres3z@va.gov	+503 2700-5444	RES-SV-283871	CONSTANCIA DE RESIDENCIA
645	Noah	nhover40@diigo.com	+503 6061-4540	RES-SV-041689260	CONSTANCIA DE RESIDENCIA
646	Nancee	nwooller41@ebay.com	+503 7525-2276	RES-SV-966189515	CONSTANCIA DE RESIDENCIA
647	Marianna	mdrust42@bigcartel.com	+503 6058-3756	RES-SV-53247580	CONSTANCIA DE RESIDENCIA
648	My	morgill43@nymag.com	+503 2154-5519	RES-SV-9434540	CONSTANCIA DE RESIDENCIA
649	Morna	mmellem44@un.org	+503 6985-3267	RES-SV-2789364	CONSTANCIA DE RESIDENCIA
650	Freeman	fpashba45@feedburner.com	+503 2169-4243	RES-SV-579647435	CONSTANCIA DE RESIDENCIA
651	Arda	adudderidge46@eventbrite.com	+503 6880-2929	RES-SV-30291493	CONSTANCIA DE RESIDENCIA
652	Florrie	fchalles47@squidoo.com	+503 6390-2973	RES-SV-25606496	CONSTANCIA DE RESIDENCIA
653	Susan	sgudgin48@bandcamp.com	+503 7576-0676	RES-SV-194194796	CONSTANCIA DE RESIDENCIA
654	Gilbert	gbrocks49@discovery.com	+503 2280-3137	RES-SV-547519817	CONSTANCIA DE RESIDENCIA
655	Zara	zheiner4a@jalbum.net	+503 7288-8142	RES-SV-791638092	CONSTANCIA DE RESIDENCIA
656	Staci	spardue4b@netlog.com	+503 2712-3287	RES-SV-333912783	CONSTANCIA DE RESIDENCIA
657	Birk	bgarnsworthy4c@va.gov	+503 7127-7029	RES-SV-3390429	CONSTANCIA DE RESIDENCIA
658	Bengt	bfateley4d@networkadvertising.org	+503 6323-8561	RES-SV-894482	CONSTANCIA DE RESIDENCIA
659	Charmain	ctitlow4e@senate.gov	+503 6563-6305	RES-SV-255510246	CONSTANCIA DE RESIDENCIA
660	Averill	abillam4f@deliciousdays.com	+503 6470-7520	RES-SV-23551277	CONSTANCIA DE RESIDENCIA
661	Rogerio	rgoudie4g@gravatar.com	+503 2840-8853	RES-SV-997173341	CONSTANCIA DE RESIDENCIA
662	Lisbeth	ledlin4h@vimeo.com	+503 6967-1568	RES-SV-88140843	CONSTANCIA DE RESIDENCIA
663	Regan	rlester4i@nyu.edu	+503 2562-1064	RES-SV-51549829	CONSTANCIA DE RESIDENCIA
664	Towney	tcaspell4j@hc360.com	+503 6543-4169	RES-SV-014211221	CONSTANCIA DE RESIDENCIA
665	Aggy	alaxston4k@ibm.com	+503 2481-3343	RES-SV-9379840	CONSTANCIA DE RESIDENCIA
666	Martainn	maspray4l@rediff.com	+503 6859-4138	RES-SV-1990545	CONSTANCIA DE RESIDENCIA
667	Fanni	fgueinn4m@wix.com	+503 2492-3002	RES-SV-64759349	CONSTANCIA DE RESIDENCIA
668	Othilie	ocours4n@archive.org	+503 7219-5049	RES-SV-3010982	CONSTANCIA DE RESIDENCIA
669	Zebulon	zdibatista4o@springer.com	+503 2206-4384	RES-SV-851644	CONSTANCIA DE RESIDENCIA
670	Erwin	ebillie4p@ucla.edu	+503 2665-0476	RES-SV-38272287	CONSTANCIA DE RESIDENCIA
671	Evaleen	ebangs4q@businessweek.com	+503 2831-5077	RES-SV-593860	CONSTANCIA DE RESIDENCIA
672	Fawn	fedney4r@mashable.com	+503 6588-5800	RES-SV-129307177	CONSTANCIA DE RESIDENCIA
673	Cissy	charragin4s@marketwatch.com	+503 6457-0640	RES-SV-933564808	CONSTANCIA DE RESIDENCIA
674	Trenna	troelofsen4t@i2i.jp	+503 6908-0391	RES-SV-43544985	CONSTANCIA DE RESIDENCIA
675	Julianna	jkerne4u@seesaa.net	+503 2821-0986	RES-SV-887178826	CONSTANCIA DE RESIDENCIA
676	Dacy	dmccloch4v@paypal.com	+503 6430-1892	RES-SV-281809	CONSTANCIA DE RESIDENCIA
677	Jasun	jschwant4w@irs.gov	+503 6497-7415	RES-SV-246996193	CONSTANCIA DE RESIDENCIA
678	Muriel	mhenricsson4x@privacy.gov.au	+503 7801-8937	RES-SV-268344	CONSTANCIA DE RESIDENCIA
679	Chris	cjowle4y@microsoft.com	+503 2223-0028	RES-SV-501237	CONSTANCIA DE RESIDENCIA
680	Gradey	gflancinbaum4z@woothemes.com	+503 2277-3668	RES-SV-037886	CONSTANCIA DE RESIDENCIA
681	Delly	dbere50@miitbeian.gov.cn	+503 6479-8509	RES-SV-882266	CONSTANCIA DE RESIDENCIA
682	Findlay	fscullion51@nytimes.com	+503 7673-5238	RES-SV-590502992	CONSTANCIA DE RESIDENCIA
683	Nerissa	nmacconchie52@shinystat.com	+503 6729-8971	RES-SV-534485	CONSTANCIA DE RESIDENCIA
684	Klara	klancley53@bloomberg.com	+503 6399-4277	RES-SV-352157	CONSTANCIA DE RESIDENCIA
685	Modestine	mrosingdall54@hibu.com	+503 7198-5184	RES-SV-5416724	CONSTANCIA DE RESIDENCIA
686	Kippar	kpledge55@soundcloud.com	+503 2394-5694	RES-SV-5317308	CONSTANCIA DE RESIDENCIA
687	Brad	bcorday56@multiply.com	+503 7925-4177	RES-SV-435156	CONSTANCIA DE RESIDENCIA
688	Patty	pfrantzen57@icio.us	+503 6187-1860	RES-SV-4272578	CONSTANCIA DE RESIDENCIA
689	Towney	tmillward58@over-blog.com	+503 6560-7381	RES-SV-071961	CONSTANCIA DE RESIDENCIA
690	Deedee	dlibbie59@usgs.gov	+503 6038-3204	RES-SV-46047530	CONSTANCIA DE RESIDENCIA
691	Carmina	chulburt5a@mashable.com	+503 6390-8750	RES-SV-509732381	CONSTANCIA DE RESIDENCIA
692	Alvan	adericot5b@microsoft.com	+503 2376-5093	RES-SV-50441627	CONSTANCIA DE RESIDENCIA
693	Manon	meskriet5c@histats.com	+503 7488-2794	RES-SV-55712187	CONSTANCIA DE RESIDENCIA
694	Milty	mucceli5d@upenn.edu	+503 2628-4159	RES-SV-6653050	CONSTANCIA DE RESIDENCIA
695	Raeann	rtaks5e@oakley.com	+503 6129-9877	RES-SV-00776544	CONSTANCIA DE RESIDENCIA
696	Etienne	estedell5f@gmpg.org	+503 6806-9582	RES-SV-60675988	CONSTANCIA DE RESIDENCIA
697	Kettie	kmuller5g@berkeley.edu	+503 6892-5768	RES-SV-953537	CONSTANCIA DE RESIDENCIA
698	Purcell	polcot5h@dion.ne.jp	+503 6993-9296	RES-SV-5085219	CONSTANCIA DE RESIDENCIA
699	Susi	spavinese5i@xinhuanet.com	+503 2971-3010	RES-SV-242845	CONSTANCIA DE RESIDENCIA
700	Cacilie	cennever5j@slashdot.org	+503 6569-3175	RES-SV-9159679	CONSTANCIA DE RESIDENCIA
701	Guglielma	gsandever0@hatena.ne.jp	+503 2652-5305	Y93999642	PASAPORTE
702	Maure	mbourke1@salon.com	+503 2160-0587	G04586867	PASAPORTE
703	Angeline	atruswell2@craigslist.org	+503 2785-9936	B41450826	PASAPORTE
704	Emera	estoggles3@telegraph.co.uk	+503 6114-0833	H96930998	PASAPORTE
705	Price	ploxdale4@google.com.au	+503 2465-2929	R94539870	PASAPORTE
706	Pattie	ptoseland5@fotki.com	+503 7660-4102	N34584658	PASAPORTE
707	Ole	ocroot6@sphinn.com	+503 2800-5488	K28761451	PASAPORTE
708	Carny	caggio7@last.fm	+503 6670-2066	N05548273	PASAPORTE
709	Wanids	wjoberne8@reddit.com	+503 6143-7951	O97436423	PASAPORTE
710	Christoffer	cwhitney9@cyberchimps.com	+503 7632-1547	D81304673	PASAPORTE
711	Nikos	nchristaeasa@scribd.com	+503 7785-3111	A54481233	PASAPORTE
712	Lem	lpoldingb@behance.net	+503 7643-8647	P55699498	PASAPORTE
713	Hunt	hdegenhardtc@studiopress.com	+503 7646-7104	B36453264	PASAPORTE
714	Ansley	aainslied@answers.com	+503 7911-8495	V35582285	PASAPORTE
715	Nedda	nransomee@hibu.com	+503 6632-7285	R04579485	PASAPORTE
716	Berri	bbaglinf@forbes.com	+503 6960-9140	Q68842815	PASAPORTE
717	Abie	amolineg@live.com	+503 7496-7151	S11441332	PASAPORTE
718	Franny	fblumireh@google.co.jp	+503 6905-6743	V55023357	PASAPORTE
719	Mozelle	mrubinlichti@dailymail.co.uk	+503 6070-0868	D30876000	PASAPORTE
720	Amberly	aswaitej@dedecms.com	+503 6592-6658	P77551398	PASAPORTE
721	Margaretta	mbrinkmank@hibu.com	+503 6395-4898	O76560298	PASAPORTE
722	Kari	kparrottl@berkeley.edu	+503 6643-6987	T23551313	PASAPORTE
723	Adham	awestellm@bravesites.com	+503 2951-5888	H91826165	PASAPORTE
724	Maddie	mbrotherickn@google.es	+503 7467-1964	E10636015	PASAPORTE
725	Abbot	aholsteino@moonfruit.com	+503 7241-8989	U85324167	PASAPORTE
726	Kelby	khicksp@ed.gov	+503 2481-1509	E50127621	PASAPORTE
727	Franny	fcockranq@51.la	+503 6889-5420	M17760888	PASAPORTE
728	Marian	mfaradayr@jimdo.com	+503 7031-7237	F32052385	PASAPORTE
729	Marlie	mmuzzis@instagram.com	+503 6860-2136	C18074550	PASAPORTE
730	Caryl	csamweyest@buzzfeed.com	+503 7430-0503	Q04987413	PASAPORTE
731	Susi	scollingwoodu@mac.com	+503 2801-5557	R10066033	PASAPORTE
732	Ruperta	rlorrainv@hubpages.com	+503 2641-4564	X58664404	PASAPORTE
733	Laryssa	ljewsburyw@xing.com	+503 2731-9918	T86405967	PASAPORTE
734	Demeter	dsillimanx@alibaba.com	+503 6603-6187	X35072449	PASAPORTE
735	Ragnar	rsnailhamy@home.pl	+503 7616-4107	A59195032	PASAPORTE
736	Pauli	phucksterz@prweb.com	+503 2601-5463	M82069433	PASAPORTE
737	Samuele	sollin10@adobe.com	+503 2026-6029	M05296440	PASAPORTE
738	Alexis	asoigoux11@prnewswire.com	+503 2440-3960	X10151650	PASAPORTE
739	Korry	kcooksey12@xrea.com	+503 6488-3408	O63367528	PASAPORTE
740	Jannel	jabelovitz13@baidu.com	+503 6513-1669	R41004252	PASAPORTE
741	Valma	vquaif14@blogger.com	+503 6991-7462	A89111195	PASAPORTE
742	David	ddemendoza15@taobao.com	+503 7804-2080	Z12519690	PASAPORTE
743	Rhoda	rbrehat16@webnode.com	+503 7620-0091	X35036624	PASAPORTE
744	Shaylyn	scolegrove17@ihg.com	+503 7901-5887	L15478074	PASAPORTE
745	Humfrid	hsare18@bizjournals.com	+503 2440-5780	K65078038	PASAPORTE
746	Geralda	gspurman19@usa.gov	+503 6553-1380	G45022631	PASAPORTE
747	Mariel	mhadcroft1a@wix.com	+503 2743-7497	M71187285	PASAPORTE
748	Adria	adalrymple1b@reddit.com	+503 6302-9567	E30768070	PASAPORTE
749	Amerigo	awackett1c@typepad.com	+503 2651-2224	Z78820942	PASAPORTE
750	Alisa	amaylin1d@moonfruit.com	+503 7815-1086	U72285250	PASAPORTE
751	Mirilla	mhuyge1e@bloomberg.com	+503 6042-1824	L41972308	PASAPORTE
752	Ninette	nkilliam1f@privacy.gov.au	+503 7253-8451	Y30109171	PASAPORTE
753	Natasha	nsirl1g@meetup.com	+503 6429-7201	Q05541687	PASAPORTE
754	Belia	bmanners1h@github.io	+503 2106-9991	X01311258	PASAPORTE
755	Kassandra	kjerwood1i@webmd.com	+503 2017-9803	T57984413	PASAPORTE
756	Carmel	ceglise1j@cocolog-nifty.com	+503 7908-3942	D67518748	PASAPORTE
757	Stinky	sryson1k@furl.net	+503 6232-8963	M24682109	PASAPORTE
758	Daile	dabsolon1l@nature.com	+503 6325-5430	W14337765	PASAPORTE
759	Madelena	msouthwell1m@twitter.com	+503 6317-8213	S31058521	PASAPORTE
760	Leia	lizchaki1n@etsy.com	+503 2152-6964	M33788954	PASAPORTE
761	Marlene	mdeeprose1o@studiopress.com	+503 6205-0344	L83245568	PASAPORTE
762	Pernell	pbarsam1p@wikipedia.org	+503 7972-1780	Z48253754	PASAPORTE
763	Lowrance	lhurlestone1q@dedecms.com	+503 2023-4619	M93895590	PASAPORTE
764	Odey	ostedson1r@springer.com	+503 2257-4630	E32335433	PASAPORTE
765	Ewen	elloyds1s@wired.com	+503 2435-6221	E79900679	PASAPORTE
766	Aldous	asygrove1t@vk.com	+503 6828-3048	W13801220	PASAPORTE
767	Fabe	fyeend1u@cbsnews.com	+503 2884-3182	G29885995	PASAPORTE
768	Lane	lmatura1v@sfgate.com	+503 7221-8862	I95227116	PASAPORTE
769	Fleming	fconerding1w@google.ca	+503 2270-3260	S44034191	PASAPORTE
770	Patrick	pdohms1x@si.edu	+503 2640-8934	C43881170	PASAPORTE
771	Ansley	asoppit1y@pinterest.com	+503 7712-4816	C06985193	PASAPORTE
772	Bartolemo	brockall1z@amazon.co.jp	+503 6893-0745	G55182572	PASAPORTE
773	Sammie	sdaughtery20@berkeley.edu	+503 6637-1604	K74617561	PASAPORTE
774	Heather	hsykora21@artisteer.com	+503 2860-8419	O76016980	PASAPORTE
775	Eddy	eearp22@google.cn	+503 7959-4304	Z25430478	PASAPORTE
776	Margot	mleathwood23@imgur.com	+503 7876-2643	F70169662	PASAPORTE
777	Isaak	igrieves24@gmpg.org	+503 2057-0147	L98873700	PASAPORTE
778	Addy	abachmann25@walmart.com	+503 6894-7274	P66125692	PASAPORTE
779	Isaiah	ichadburn26@intel.com	+503 6246-3004	E21423663	PASAPORTE
780	Constanta	ccinnamond27@usatoday.com	+503 7685-9167	R55909791	PASAPORTE
781	Boony	bfedoronko28@booking.com	+503 2682-9648	Y98377472	PASAPORTE
782	Fidole	fgilmore29@princeton.edu	+503 7380-3251	Q23820788	PASAPORTE
783	Donnie	dspittles2a@chicagotribune.com	+503 7049-2927	S56048316	PASAPORTE
784	Sanderson	sletherbury2b@ustream.tv	+503 6025-7033	C39905508	PASAPORTE
785	Lurlene	ldell2c@networksolutions.com	+503 7329-6440	S34227843	PASAPORTE
786	Raine	rgrut2d@usgs.gov	+503 2045-4723	Z23544747	PASAPORTE
787	Tabbitha	temanulsson2e@washingtonpost.com	+503 2039-8943	Q70597898	PASAPORTE
788	Geneva	garnaudin2f@freewebs.com	+503 7896-9720	W48306742	PASAPORTE
789	Darnall	dwhates2g@wix.com	+503 6504-5337	N08048938	PASAPORTE
790	Anni	aaustwick2h@mtv.com	+503 7553-2995	A21973323	PASAPORTE
791	Holli	hengelmann2i@sohu.com	+503 2944-1852	O52481209	PASAPORTE
792	Goldina	gcasaroli2j@tmall.com	+503 2762-5577	B94147452	PASAPORTE
793	Nikolia	nmcnee2k@google.co.jp	+503 6428-7559	N12221655	PASAPORTE
794	Vasili	vtincombe2l@booking.com	+503 7096-0254	U70610917	PASAPORTE
795	Alys	arahill2m@uiuc.edu	+503 7890-6230	X39994839	PASAPORTE
796	Vicki	vbourgourd2n@wired.com	+503 7730-2081	D82527524	PASAPORTE
797	Yvor	yperkins2o@reverbnation.com	+503 7094-1497	B67228129	PASAPORTE
798	Joana	jcambridge2p@dion.ne.jp	+503 7438-4249	S52691342	PASAPORTE
799	Terri	tmorant2q@google.co.uk	+503 2744-5249	J57443669	PASAPORTE
800	Giffard	grosenblatt2r@europa.eu	+503 7740-3686	K53798479	PASAPORTE
801	Bernardine	bsollime2s@oaic.gov.au	+503 7689-8200	M61334461	PASAPORTE
802	Katuscha	kdanielli2t@statcounter.com	+503 6328-7411	E29551388	PASAPORTE
803	Casey	cbrendeke2u@google.com.hk	+503 6811-4454	L95016369	PASAPORTE
804	Bruno	bmasseo2v@theglobeandmail.com	+503 6912-5595	T57291598	PASAPORTE
805	Madeline	mstillert2w@google.ru	+503 6661-4160	S18533013	PASAPORTE
806	Bellanca	bburree2x@shareasale.com	+503 6649-0698	B00447716	PASAPORTE
807	Mandie	mgremane2y@biblegateway.com	+503 7226-1868	E90551758	PASAPORTE
808	Kerby	kingham2z@mapy.cz	+503 7554-8319	X34496849	PASAPORTE
809	Alessandro	ahollows30@skype.com	+503 6300-1363	G13326475	PASAPORTE
810	Lodovico	lranaghan31@youtube.com	+503 6990-4939	N05444136	PASAPORTE
811	Rania	rbrane32@tmall.com	+503 7052-3362	G74735567	PASAPORTE
812	Welbie	wjutson33@myspace.com	+503 6537-5699	R94038954	PASAPORTE
813	Luella	ldumingo34@free.fr	+503 6483-5816	T43160725	PASAPORTE
814	Jeannine	jcumpton35@discovery.com	+503 6003-6683	C33049325	PASAPORTE
815	Leandra	lortas36@dion.ne.jp	+503 6221-6179	Y97970304	PASAPORTE
816	Cecil	cfarncomb37@lycos.com	+503 2342-7368	T74837609	PASAPORTE
817	Dyann	dstrangward38@bloglines.com	+503 2027-1266	L35670253	PASAPORTE
818	Rickard	rlogsdale39@umn.edu	+503 6819-6678	Y73523142	PASAPORTE
819	Gaspard	gbezzant3a@oaic.gov.au	+503 6464-4038	Y61646893	PASAPORTE
820	Idell	ipetroselli3b@ovh.net	+503 7199-3858	G97724907	PASAPORTE
821	Hoyt	hkinforth3c@businesswire.com	+503 2328-0395	P85589035	PASAPORTE
822	Frans	fpreshous3d@marriott.com	+503 6885-7380	U57205107	PASAPORTE
823	Elston	etunnadine3e@nhs.uk	+503 6871-1917	R08884988	PASAPORTE
824	Susanne	sgittins3f@1688.com	+503 7538-2802	Q61849586	PASAPORTE
825	Mallory	mrignall3g@google.com.au	+503 2384-7042	K37181858	PASAPORTE
826	Eddy	edraaisma3h@hc360.com	+503 6300-7180	K87014642	PASAPORTE
827	Gar	ghazelton3i@e-recht24.de	+503 7030-9439	N91614360	PASAPORTE
828	Christan	cneilands3j@twitpic.com	+503 2864-7505	P32805718	PASAPORTE
829	Vidovik	vmartinello3k@yellowpages.com	+503 7712-6128	Q20250609	PASAPORTE
830	Leandra	lredmell3l@nps.gov	+503 6102-6417	V38815708	PASAPORTE
831	Gene	ggeibel3m@cyberchimps.com	+503 7249-2266	S06667228	PASAPORTE
832	Rudolfo	rhamnet3n@amazon.co.jp	+503 6192-6910	O70950889	PASAPORTE
833	Darnall	dlekeux3o@mapquest.com	+503 7849-4180	U04354476	PASAPORTE
834	Fionnula	fpowelee3p@posterous.com	+503 7379-2303	Y83645439	PASAPORTE
835	Lucine	lgiabuzzi3q@scientificamerican.com	+503 7713-1686	N62547532	PASAPORTE
836	Shem	swestmancoat3r@furl.net	+503 7692-2479	W95885078	PASAPORTE
837	Tibold	twrangle3s@mozilla.org	+503 7678-7360	W98925202	PASAPORTE
838	Tierney	tgreenman3t@state.gov	+503 2114-1215	M55918388	PASAPORTE
839	Agata	apett3u@prweb.com	+503 2701-9736	V33449262	PASAPORTE
840	Elmo	esetford3v@upenn.edu	+503 6768-5946	A19756916	PASAPORTE
841	Berne	bfoulser3w@rediff.com	+503 7558-9885	E45359671	PASAPORTE
842	Nickie	ndevonish3x@nytimes.com	+503 6722-1650	D04012513	PASAPORTE
843	Gisele	gstripp3y@cornell.edu	+503 7816-8257	X01571035	PASAPORTE
844	Cirstoforo	cschwaiger3z@forbes.com	+503 7233-8832	R57064183	PASAPORTE
845	Bradley	bschurcke40@businessweek.com	+503 2990-2149	Y62727486	PASAPORTE
846	Shauna	sandrejs41@ask.com	+503 2935-3148	U07086749	PASAPORTE
847	Naoma	nbarnwell42@xrea.com	+503 6066-9918	G81606962	PASAPORTE
848	Laraine	llangworthy43@nationalgeographic.com	+503 6892-6067	H01686919	PASAPORTE
849	Rik	rmcallen44@slate.com	+503 6073-6345	Y00242971	PASAPORTE
850	Bobbe	btaffee45@miitbeian.gov.cn	+503 2565-4031	I08526513	PASAPORTE
851	Fancy	ffrandsen46@digg.com	+503 2742-2517	L87770735	PASAPORTE
852	Jaclin	jferraraccio47@amazon.com	+503 2327-5852	P37549989	PASAPORTE
853	Gabriello	gscotford48@twitpic.com	+503 6555-0271	O05510984	PASAPORTE
854	Ambros	aleggs49@washington.edu	+503 7955-7760	L87113520	PASAPORTE
855	Paolina	pewestace4a@stanford.edu	+503 2401-3420	R21049131	PASAPORTE
856	Bernetta	bambler4b@hostgator.com	+503 7646-5031	V74378856	PASAPORTE
857	Sileas	strunchion4c@histats.com	+503 7049-9263	M25280827	PASAPORTE
858	Janean	jtidball4d@army.mil	+503 2077-1152	Z87096387	PASAPORTE
859	Kelley	kclooney4e@geocities.com	+503 6366-0879	Q57034408	PASAPORTE
860	Rustin	relen4f@aboutads.info	+503 2643-1513	U17082433	PASAPORTE
861	Mureil	mhaugg4g@cpanel.net	+503 6843-1304	K50359746	PASAPORTE
862	Brook	bgrayley4h@un.org	+503 2608-6532	X06726459	PASAPORTE
863	Adelaide	acatt4i@amazon.co.uk	+503 2570-2034	J35028730	PASAPORTE
864	Bamby	bbonn4j@reddit.com	+503 7744-2175	H13065630	PASAPORTE
865	Torrie	tpetticrow4k@chron.com	+503 2681-0763	W97202434	PASAPORTE
866	Abbe	alorman4l@netvibes.com	+503 6591-4183	A09597906	PASAPORTE
867	Nancy	nkenyon4m@google.nl	+503 7459-8301	E88051641	PASAPORTE
868	Barb	bdelias4n@telegraph.co.uk	+503 2373-2001	J98642725	PASAPORTE
869	Norma	ntriggs4o@omniture.com	+503 6788-0163	R26057209	PASAPORTE
870	Nalani	nfritzer4p@hao123.com	+503 7031-2941	X66331365	PASAPORTE
871	Taddeo	tleel4q@simplemachines.org	+503 2745-9079	L82595921	PASAPORTE
872	Hunfredo	hduhig4r@nationalgeographic.com	+503 6479-7760	X33685450	PASAPORTE
873	Adair	ajillions4s@aol.com	+503 7240-0968	N81242328	PASAPORTE
874	Larissa	lpursehouse4t@artisteer.com	+503 2952-4293	T59825493	PASAPORTE
875	Kenyon	kgatcliff4u@wp.com	+503 2208-1387	P39278255	PASAPORTE
876	Shirlee	ssell4v@woothemes.com	+503 2149-8496	Y02682851	PASAPORTE
877	Davie	dwilcockes4w@t.co	+503 2808-8923	Y15752817	PASAPORTE
878	Melessa	mbernot4x@tamu.edu	+503 6351-2591	E35007016	PASAPORTE
879	Norby	ngrisard4y@noaa.gov	+503 6919-6468	S16413054	PASAPORTE
880	Costanza	ccrass4z@51.la	+503 7744-4717	F34629511	PASAPORTE
881	Bartel	bcanlin50@dropbox.com	+503 2527-0155	R11213089	PASAPORTE
882	Jessamyn	jrignall51@joomla.org	+503 6129-2456	O78231990	PASAPORTE
883	Georgi	gdellow52@cbslocal.com	+503 6638-8537	P91054147	PASAPORTE
884	Mar	mlowensohn53@aboutads.info	+503 6128-8815	O76664475	PASAPORTE
885	Dorry	dhouse54@ycombinator.com	+503 7085-8901	C92414239	PASAPORTE
886	Elyssa	emurrthum55@xrea.com	+503 2620-9061	H17351334	PASAPORTE
887	Powell	pbratch56@soup.io	+503 7449-1137	F06237173	PASAPORTE
888	Glenda	gfurness57@imdb.com	+503 6878-8608	K01574262	PASAPORTE
889	Charity	cbrussell58@craigslist.org	+503 2346-4704	I68225068	PASAPORTE
890	Isaiah	iredmore59@rambler.ru	+503 7096-2304	S22073402	PASAPORTE
891	Frances	flangfitt5a@unesco.org	+503 7321-7694	B22254814	PASAPORTE
892	Perri	pmorris5b@mediafire.com	+503 6143-3119	M17671821	PASAPORTE
893	Gina	glinkin5c@aol.com	+503 6380-0612	M95953236	PASAPORTE
894	Alexandra	amangin5d@quantcast.com	+503 2859-0628	O75466505	PASAPORTE
895	Carrie	csabatier5e@yellowbook.com	+503 7221-3153	X81576455	PASAPORTE
896	Murdoch	mmontgomery5f@sfgate.com	+503 6642-2968	F00731610	PASAPORTE
897	Peggy	pfrugier5g@google.co.jp	+503 6860-0457	I32080892	PASAPORTE
898	Willi	wkemball5h@people.com.cn	+503 6776-3735	G54244721	PASAPORTE
899	Demott	dmaclese5i@ibm.com	+503 2326-6277	Q96177845	PASAPORTE
900	Zola	zbrocket5j@paginegialle.it	+503 6503-8891	C94948416	PASAPORTE
901	Gerrie	ghansed5k@cbsnews.com	+503 7908-3280	E35195511	PASAPORTE
902	Merrill	mscargill5l@ehow.com	+503 2100-0915	H08240877	PASAPORTE
903	Glendon	gsymcoxe5m@go.com	+503 2602-7099	X99688011	PASAPORTE
904	Barthel	bdalzell5n@hp.com	+503 7071-5472	W62141043	PASAPORTE
905	Laurene	lbanker5o@linkedin.com	+503 2978-3021	K60648986	PASAPORTE
906	Waylon	wrougier5p@un.org	+503 6530-7109	H19834357	PASAPORTE
907	Nikki	ndebernardi5q@123-reg.co.uk	+503 7986-0791	E82809597	PASAPORTE
908	Klement	kwarwick5r@omniture.com	+503 7222-9288	I81590195	PASAPORTE
909	Everett	elunam5s@cdc.gov	+503 2194-1133	A24090878	PASAPORTE
910	Kare	kvanni5t@dot.gov	+503 2956-5781	Q13598496	PASAPORTE
911	Leonard	lbowater5u@mit.edu	+503 7975-3047	I15728353	PASAPORTE
912	Edlin	esarten5v@zdnet.com	+503 7625-5530	Q16606060	PASAPORTE
913	Taber	tladen5w@miitbeian.gov.cn	+503 6733-5986	C89031268	PASAPORTE
914	Lloyd	lforcer5x@cdc.gov	+503 6816-3040	K99143895	PASAPORTE
915	Batsheva	bwestbury5y@ebay.co.uk	+503 7973-5506	Y06390258	PASAPORTE
916	Bathsheba	bgheorghescu5z@linkedin.com	+503 2847-8310	P83629988	PASAPORTE
917	Tadeas	thadden60@tmall.com	+503 6608-7710	L72817584	PASAPORTE
918	Russell	rgrzegorczyk61@live.com	+503 2436-6801	V33150470	PASAPORTE
919	Molly	mfourmy62@g.co	+503 7287-1138	P54096619	PASAPORTE
920	Ynes	ycarnier63@uiuc.edu	+503 6815-5054	H00048934	PASAPORTE
921	Lockwood	lthormwell64@msu.edu	+503 2472-0890	U83509886	PASAPORTE
922	Maximilian	mdarko65@godaddy.com	+503 6231-2759	M80378288	PASAPORTE
923	Donovan	dlattka66@prweb.com	+503 6844-7630	S64085311	PASAPORTE
924	Dun	dgrealy67@time.com	+503 6232-5881	I58904025	PASAPORTE
925	Deerdre	dhawksley68@typepad.com	+503 7482-0048	S59826558	PASAPORTE
926	Whitman	whaggar69@europa.eu	+503 7198-6225	K99781339	PASAPORTE
927	Lucias	lvinick6a@bizjournals.com	+503 6176-8364	G71360159	PASAPORTE
928	Melony	mbearn6b@opensource.org	+503 2144-6001	F96016400	PASAPORTE
929	Roi	rboas6c@barnesandnoble.com	+503 6130-2112	X24038935	PASAPORTE
930	Marinna	mbeatens6d@deliciousdays.com	+503 6530-8891	K55525119	PASAPORTE
931	Flori	fmeasures6e@live.com	+503 2189-2139	R91307967	PASAPORTE
932	Norma	ngallager6f@pagesperso-orange.fr	+503 6979-9678	T85967467	PASAPORTE
933	Meir	misgate6g@discovery.com	+503 7237-2475	P26164512	PASAPORTE
934	Pooh	pscrane6h@pagesperso-orange.fr	+503 2173-6324	W57201514	PASAPORTE
935	Sallie	shawler6i@nbcnews.com	+503 2515-3362	T85804909	PASAPORTE
936	Halsey	hsolly6j@springer.com	+503 6599-4018	D85345770	PASAPORTE
937	Darb	ddenekamp6k@census.gov	+503 7561-5895	J63150372	PASAPORTE
938	Sharline	spittford6l@ebay.co.uk	+503 6615-2342	R32106395	PASAPORTE
939	Jarad	jsexten6m@quantcast.com	+503 6764-1289	Y76045600	PASAPORTE
940	Janetta	jmazella6n@tinypic.com	+503 6449-3085	S67052587	PASAPORTE
941	Maryanne	mdelieu6o@google.de	+503 2483-8162	A61791585	PASAPORTE
942	Alwin	ahaddleston6p@slate.com	+503 2818-4522	B87375591	PASAPORTE
943	Consuela	cantonnikov6q@comcast.net	+503 6947-9481	T54111616	PASAPORTE
944	Burg	bdeniske6r@nyu.edu	+503 7053-6788	S64206345	PASAPORTE
945	Mendie	mgiblin6s@wp.com	+503 2265-6644	N86259794	PASAPORTE
946	Cecelia	cmitchall6t@whitehouse.gov	+503 6166-3362	F44492881	PASAPORTE
947	Robinet	rbleibaum6u@va.gov	+503 2468-0143	R02514260	PASAPORTE
948	Rollie	rimorts6v@homestead.com	+503 7045-6570	I67194208	PASAPORTE
949	Patton	pmilius6w@phpbb.com	+503 6579-9523	P26542879	PASAPORTE
950	Hermione	hstqueintain6x@blogspot.com	+503 6483-8519	E08319708	PASAPORTE
951	Irvin	imcnamara6y@go.com	+503 2605-9149	A24208925	PASAPORTE
952	Dareen	dglowinski6z@parallels.com	+503 7198-4949	R05082775	PASAPORTE
953	Guenna	gexton70@marketwatch.com	+503 2388-1097	H50453585	PASAPORTE
954	Olly	oainley71@ftc.gov	+503 6925-6963	U46655488	PASAPORTE
955	Seumas	sbreward72@washingtonpost.com	+503 7418-8349	W90717399	PASAPORTE
956	Ranna	radamowicz73@technorati.com	+503 6753-5849	B91590286	PASAPORTE
957	Renaldo	rbradforth74@bbc.co.uk	+503 6662-9120	Q86355687	PASAPORTE
958	Ban	bbagge75@miitbeian.gov.cn	+503 6985-7012	W55048699	PASAPORTE
959	Pia	pmcquirter76@discovery.com	+503 2593-0444	G39576475	PASAPORTE
960	Enrica	evondra77@imgur.com	+503 7628-3050	I21719248	PASAPORTE
961	Edee	ehawksby78@myspace.com	+503 7449-5460	M71737127	PASAPORTE
962	Morty	mdevey79@sina.com.cn	+503 7562-1700	C28173271	PASAPORTE
963	Konstantine	kledgister7a@shinystat.com	+503 2589-7442	R50159395	PASAPORTE
964	Eddie	eblaymires7b@google.de	+503 6647-6903	O04848769	PASAPORTE
965	Pasquale	pjosipovic7c@vinaora.com	+503 2981-3050	U22293751	PASAPORTE
966	Marleah	meginton7d@walmart.com	+503 7010-7728	N57529255	PASAPORTE
967	Bibbie	bfinden7e@photobucket.com	+503 6615-7315	A16895148	PASAPORTE
968	Whitby	wtotterdell7f@themeforest.net	+503 7401-4963	Y47541534	PASAPORTE
969	Piggy	pshera7g@sciencedaily.com	+503 6801-1315	X69261728	PASAPORTE
970	Kathe	kbrigman7h@netlog.com	+503 7640-3374	N08776264	PASAPORTE
971	Mikey	mswadon7i@imgur.com	+503 6168-2278	S06561056	PASAPORTE
972	Quentin	qcallendar7j@hibu.com	+503 7603-9422	H93098451	PASAPORTE
973	Mata	mjoannet7k@phpbb.com	+503 7686-7438	A16183031	PASAPORTE
974	Gilburt	gmcmackin7l@deliciousdays.com	+503 2006-7290	U75576959	PASAPORTE
975	Alaster	amallett7m@vk.com	+503 7106-6626	Z38229124	PASAPORTE
976	Lesly	ldewes7n@opensource.org	+503 2845-0605	G21342768	PASAPORTE
977	Gabi	gottosen7o@instagram.com	+503 6799-2996	O25127641	PASAPORTE
978	Asa	amorbey7p@dell.com	+503 2636-9388	Q80259882	PASAPORTE
979	Prissie	pnyssen7q@4shared.com	+503 6957-8527	Q69054380	PASAPORTE
980	Valeria	vgurko7r@wordpress.com	+503 2207-9916	P89671712	PASAPORTE
981	Nicki	nbrownett7s@cbc.ca	+503 7674-8285	R42023560	PASAPORTE
982	Neill	nconnolly7t@ft.com	+503 2255-8187	J24844318	PASAPORTE
983	Kit	kperkis7u@vistaprint.com	+503 7615-6475	R59149371	PASAPORTE
984	Tony	tyarker7v@sphinn.com	+503 7973-6568	D62469467	PASAPORTE
985	Sherman	sstart7w@quantcast.com	+503 7552-8802	K05715786	PASAPORTE
986	Maiga	mhorwell7x@mozilla.org	+503 7149-0832	G44047395	PASAPORTE
987	Nevil	nebbers7y@sciencedirect.com	+503 7174-2163	F30705548	PASAPORTE
988	Lucretia	lrolfini7z@sun.com	+503 6825-9860	M67744926	PASAPORTE
989	Nanni	ngetty80@unblog.fr	+503 6924-2052	P71682564	PASAPORTE
990	Julie	jclaus81@forbes.com	+503 6449-8822	M16216918	PASAPORTE
991	Maud	mgudyer82@dedecms.com	+503 7677-2984	K78410746	PASAPORTE
992	Stephanus	sortet83@google.es	+503 7107-3349	Q60553623	PASAPORTE
993	Doll	dsparway84@ucla.edu	+503 2663-0424	L67234539	PASAPORTE
995	Darnall	dspinks86@themeforest.net	+503 2789-3648	I68526657	PASAPORTE
996	Powell	pkopecka87@marriott.com	+503 6782-9226	L15212720	PASAPORTE
997	Heindrick	hharber88@home.pl	+503 2011-5103	H02374773	PASAPORTE
998	Kynthia	kderricoat89@kickstarter.com	+503 6690-2736	E85976617	PASAPORTE
999	Karim	kfirmin8a@ning.com	+503 2240-1452	L36857589	PASAPORTE
1000	Dunc	diuorio8b@skyrock.com	+503 2132-8253	K67150409	PASAPORTE
\.


--
-- TOC entry 5364 (class 0 OID 31185)
-- Dependencies: 244
-- Data for Name: resenia; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.resenia (id_resenia, id_estadia, id_huesped, calificacion, comentario) FROM stdin;
9	9	685	2.7	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
11	11	53	2.0	Etiam pretium iaculis justo. In hac habitasse platea dictumst. Etiam faucibus cursus urna.
16	16	730	1.4	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
24	24	981	2.0	Vivamus tortor. Duis mattis egestas metus. Aenean fermentum.
25	25	979	1.9	Quisque ut erat.
27	27	220	3.4	Maecenas rhoncus aliquam lacus.
34	34	332	4.7	Pellentesque eget nunc.
47	47	811	4.2	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
43	43	563	3.2	Aliquam quis turpis eget elit sodales scelerisque. Mauris sit amet eros.
60	60	386	2.6	Aliquam non mauris. Morbi non lectus. Aliquam sit amet diam in magna bibendum imperdiet.
65	65	570	1.2	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
73	73	681	1.9	Etiam pretium iaculis justo. In hac habitasse platea dictumst.
979	979	925	3.5	Donec ut dolor. Morbi vel lectus in quam fringilla rhoncus.
75	75	12	2.8	Vestibulum ac est lacinia nisi venenatis tristique.
71	71	594	2.8	Integer tincidunt ante vel ipsum.
38	38	759	4.5	Nulla nisl. Nunc nisl. Duis bibendum, felis sed interdum venenatis, turpis enim blandit mi, in porttitor pede justo eu massa.
92	92	257	4.7	Pellentesque viverra pede ac diam. Cras pellentesque volutpat dui. Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
96	96	446	2.0	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus. Praesent lectus.
99	99	214	2.0	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero.
120	120	256	2.3	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
118	118	915	4.6	In quis justo.
124	124	814	2.0	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
126	126	491	4.9	Etiam vel augue. Vestibulum rutrum rutrum neque. Aenean auctor gravida sem.
129	129	475	1.1	Proin at turpis a pede posuere nonummy. Integer non velit. Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue.
134	134	640	2.4	Praesent blandit. Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
140	140	576	1.1	In blandit ultrices enim.
148	148	179	1.2	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus.
153	153	473	4.0	Morbi quis tortor id nulla ultrices aliquet.
121	121	266	4.5	Sed accumsan felis. Ut at dolor quis odio consequat varius. Integer ac leo.
164	164	316	4.0	Nam dui. Proin leo odio, porttitor id, consequat in, consequat ut, nulla. Sed accumsan felis.
168	168	75	2.5	Phasellus sit amet erat. Nulla tempus. Vivamus in felis eu sapien cursus vestibulum.
214	214	54	3.2	Maecenas ut massa quis augue luctus tincidunt.
221	221	8	4.8	Curabitur in libero ut massa volutpat convallis. Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
223	223	660	2.7	Proin risus.
226	226	787	2.4	Praesent blandit. Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
228	228	492	4.8	Maecenas pulvinar lobortis est. Phasellus sit amet erat.
233	233	968	1.9	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam.
163	163	32	4.5	Integer ac leo.
206	206	609	4.5	Curabitur convallis.
243	243	295	2.7	Aenean fermentum.
246	246	3	3.4	Maecenas rhoncus aliquam lacus.
251	251	225	3.4	Phasellus in felis. Donec semper sapien a libero. Nam dui.
259	259	312	4.2	Duis bibendum. Morbi non quam nec dui luctus rutrum. Nulla tellus.
268	268	448	1.4	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
281	281	190	4.3	Suspendisse potenti. Nullam porttitor lacus at turpis.
283	283	11	3.6	Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
285	285	170	4.5	Donec ut mauris eget massa tempor convallis. Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh. Quisque id justo sit amet sapien dignissim vestibulum.
293	293	104	2.3	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
289	289	905	2.0	Praesent id massa id nisl venenatis lacinia. Aenean sit amet justo. Morbi ut odio.
295	295	726	2.3	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst.
294	294	920	4.5	Fusce consequat. Nulla nisl. Nunc nisl.
284	284	256	2.8	Proin risus. Praesent lectus.
266	266	519	4.5	Aliquam erat volutpat. In congue. Etiam justo.
317	317	334	4.6	Morbi vel lectus in quam fringilla rhoncus.
321	321	228	3.5	Integer non velit. Donec diam neque, vestibulum eget, vulputate ut, ultrices vel, augue. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
323	323	740	4.5	Suspendisse potenti. Nullam porttitor lacus at turpis. Donec posuere metus vitae ipsum.
326	326	841	1.9	Integer ac leo. Pellentesque ultrices mattis odio. Donec vitae nisi.
334	334	402	4.9	In quis justo. Maecenas rhoncus aliquam lacus.
341	341	912	1.2	Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla. Sed vel enim sit amet nunc viverra dapibus. Nulla suscipit ligula in lacus.
350	350	858	1.9	In quis justo. Maecenas rhoncus aliquam lacus. Morbi quis tortor id nulla ultrices aliquet.
309	309	76	2.8	Aenean auctor gravida sem.
330	330	431	2.8	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est. Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros.
332	332	211	2.8	Morbi a ipsum. Integer a nibh. In quis justo.
318	318	285	4.5	Morbi quis tortor id nulla ultrices aliquet. Maecenas leo odio, condimentum id, luctus nec, molestie sed, justo.
370	370	414	4.5	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh. Quisque id justo sit amet sapien dignissim vestibulum.
322	322	579	4.5	Donec quis orci eget orci vehicula condimentum.
374	374	424	1.9	Praesent blandit. Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
375	375	462	4.2	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
385	385	338	1.7	Morbi porttitor lorem id ligula. Suspendisse ornare consequat lectus.
391	391	189	3.2	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
380	380	406	2.3	Suspendisse ornare consequat lectus. In est risus, auctor sed, tristique in, tempus sit amet, sem. Fusce consequat.
404	404	515	2.4	Donec dapibus. Duis at velit eu est congue elementum. In hac habitasse platea dictumst.
434	434	855	3.4	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque.
443	443	716	4.0	Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Proin risus.
451	451	350	1.9	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh.
449	449	213	2.8	Aenean sit amet justo.
447	447	549	2.8	Integer ac leo.
452	452	502	2.8	Cras non velit nec nisi vulputate nonummy.
405	405	804	4.5	Aliquam quis turpis eget elit sodales scelerisque.
430	430	316	4.5	Curabitur at ipsum ac tellus semper interdum. Mauris ullamcorper purus sit amet nulla.
457	457	143	4.6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Donec pharetra, magna vestibulum aliquet ultrices, erat tortor sollicitudin mi, sit amet lobortis sapien sapien non mi.
458	458	235	1.7	Sed sagittis. Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci. Nullam molestie nibh in lectus.
454	454	84	2.3	Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
469	469	529	3.5	Quisque arcu libero, rutrum ac, lobortis vel, dapibus at, diam. Nam tristique tortor eu pede.
475	475	33	4.4	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
485	485	717	3.6	Aliquam sit amet diam in magna bibendum imperdiet.
490	490	444	3.5	Proin interdum mauris non ligula pellentesque ultrices.
516	516	17	1.1	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus.
518	518	677	2.6	Duis aliquam convallis nunc. Proin at turpis a pede posuere nonummy. Integer non velit.
522	522	88	3.2	Praesent blandit.
523	523	446	4.4	Integer non velit.
488	488	5	2.8	Ut at dolor quis odio consequat varius. Integer ac leo.
534	534	670	1.7	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci. Nullam molestie nibh in lectus. Pellentesque at nulla.
539	539	3	3.2	Donec semper sapien a libero.
545	545	556	3.2	Morbi non quam nec dui luctus rutrum. Nulla tellus. In sagittis dui vel nisl.
546	546	932	4.7	Nulla suscipit ligula in lacus. Curabitur at ipsum ac tellus semper interdum.
566	566	749	1.1	Aliquam erat volutpat.
581	581	192	4.6	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis.
587	587	79	2.7	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis.
602	602	102	4.4	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci.
537	537	164	2.8	Curabitur convallis. Duis consequat dui nec nisi volutpat eleifend.
544	544	783	2.8	Nulla facilisi.
593	593	752	4.5	Nullam orci pede, venenatis non, sodales sed, tincidunt eu, felis. Fusce posuere felis sed lacus. Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
613	613	931	4.5	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus.
616	616	684	4.6	Ut tellus. Nulla ut erat id mauris vulputate elementum. Nullam varius.
630	630	783	4.7	Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede. Morbi porttitor lorem id ligula.
634	634	341	4.5	Donec ut dolor.
643	643	146	1.2	Vivamus in felis eu sapien cursus vestibulum. Proin eu mi. Nulla ac enim.
645	645	232	1.1	Curabitur gravida nisi at nibh. In hac habitasse platea dictumst. Aliquam augue quam, sollicitudin vitae, consectetuer eget, rutrum at, lorem.
668	668	578	2.8	Aliquam sit amet diam in magna bibendum imperdiet.
671	671	475	4.8	Proin eu mi. Nulla ac enim. In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem.
677	677	917	3.5	Curabitur in libero ut massa volutpat convallis. Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo. Maecenas pulvinar lobortis est.
678	678	925	2.8	Ut tellus. Nulla ut erat id mauris vulputate elementum.
618	618	243	4.5	Curabitur in libero ut massa volutpat convallis. Morbi odio odio, elementum eu, interdum eu, tincidunt in, leo.
684	684	89	2.8	Duis consequat dui nec nisi volutpat eleifend.
694	694	902	4.0	Quisque erat eros, viverra eget, congue eget, semper rutrum, nulla.
708	708	645	2.8	Mauris sit amet eros. Suspendisse accumsan tortor quis turpis. Sed ante.
723	723	5	1.2	Morbi vel lectus in quam fringilla rhoncus. Mauris enim leo, rhoncus sed, vestibulum sit amet, cursus id, turpis.
731	731	734	4.4	Praesent lectus.
742	742	738	4.0	Vestibulum quam sapien, varius ut, blandit non, interdum in, ante. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio. Curabitur convallis.
751	751	376	4.6	Donec vitae nisi. Nam ultrices, libero non mattis pulvinar, nulla pede ullamcorper augue, a suscipit nulla elit ac nulla.
740	740	485	2.8	Donec ut dolor. Morbi vel lectus in quam fringilla rhoncus.
755	755	227	2.8	Duis aliquam convallis nunc. Proin at turpis a pede posuere nonummy. Integer non velit.
747	747	492	2.8	Proin risus. Praesent lectus.
763	763	669	2.6	Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Nulla dapibus dolor vel est. Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique.
764	764	786	2.7	Suspendisse ornare consequat lectus.
767	767	36	1.4	Proin eu mi. Nulla ac enim.
796	796	329	3.2	Maecenas tincidunt lacus at velit. Vivamus vel nulla eget eros elementum pellentesque. Quisque porta volutpat erat.
824	824	583	2.3	Vestibulum rutrum rutrum neque.
783	783	228	3.2	Pellentesque viverra pede ac diam.
786	786	571	3.5	Aenean sit amet justo. Morbi ut odio. Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo.
789	789	295	4.9	Sed sagittis. Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci.
807	807	802	1.3	Phasellus id sapien in sapien iaculis congue. Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
827	827	172	2.5	Quisque ut erat.
776	776	18	2.8	Praesent blandit. Nam nulla. Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
809	809	871	2.8	Morbi sem mauris, laoreet ut, rhoncus aliquet, pulvinar sed, nisl.
790	790	394	4.5	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique. Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue.
838	838	561	4.2	Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat. Morbi a ipsum.
850	850	254	4.0	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl. Aenean lectus. Pellentesque eget nunc.
854	854	591	4.3	Morbi ut odio. Cras mi pede, malesuada in, imperdiet et, commodo vulputate, justo. In blandit ultrices enim.
873	873	458	2.6	Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
887	887	28	4.2	Donec ut mauris eget massa tempor convallis.
890	890	98	1.1	Cras pellentesque volutpat dui. Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
891	891	157	1.9	Phasellus in felis. Donec semper sapien a libero. Nam dui.
899	899	709	2.8	Sed ante. Vivamus tortor. Duis mattis egestas metus.
900	900	469	2.7	Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat.
834	834	957	2.8	Donec ut mauris eget massa tempor convallis.
852	852	652	2.8	Vivamus tortor.
926	926	610	2.4	Vivamus vestibulum sagittis sapien. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Etiam vel augue.
927	927	448	1.1	Quisque ut erat.
934	934	367	2.8	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Duis faucibus accumsan odio.
945	945	304	4.5	Sed ante.
948	948	15	2.7	Nullam molestie nibh in lectus.
963	963	494	2.5	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat.
978	978	230	3.5	Nam congue, risus semper porta volutpat, quam pede lobortis ligula, sit amet eleifend pede libero quis orci. Nullam molestie nibh in lectus. Pellentesque at nulla.
912	912	186	2.8	In blandit ultrices enim. Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
960	960	775	4.5	Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
985	985	819	4.2	Maecenas tristique, est et tempus semper, est quam pharetra magna, ac consequat metus sapien ut nunc.
991	991	943	1.4	Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue.
992	992	632	2.8	Morbi ut odio.
989	989	682	2.8	Integer pede justo, lacinia eget, tincidunt eget, tempus vel, pede.
995	995	823	4.5	Donec ut mauris eget massa tempor convallis.
30	30	281	4.5	Morbi vel lectus in quam fringilla rhoncus.
122	122	810	4.5	Nulla neque libero, convallis eget, eleifend luctus, ultricies eu, nibh. Quisque id justo sit amet sapien dignissim vestibulum.
603	603	438	4.5	Sed ante. Vivamus tortor. Duis mattis egestas metus.
267	267	932	2.8	Pellentesque eget nunc.
227	227	560	2.8	Nulla ut erat id mauris vulputate elementum. Nullam varius.
196	196	629	2.8	Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Vivamus vestibulum sagittis sapien.
263	263	644	2.8	Praesent lectus. Vestibulum quam sapien, varius ut, blandit non, interdum in, ante.
387	387	107	2.8	Quisque ut erat. Curabitur gravida nisi at nibh.
637	637	655	2.8	Praesent id massa id nisl venenatis lacinia.
676	676	726	2.8	In tempor, turpis nec euismod scelerisque, quam turpis adipiscing lorem, vitae mattis nibh ligula nec sem. Duis aliquam convallis nunc.
712	712	634	2.8	Phasellus id sapien in sapien iaculis congue. Vivamus metus arcu, adipiscing molestie, hendrerit at, vulputate vitae, nisl.
810	810	146	2.8	Etiam vel augue.
907	907	42	2.8	Integer tincidunt ante vel ipsum. Praesent blandit lacinia erat. Vestibulum sed magna at nunc commodo placerat.
794	794	943	2.8	Pellentesque viverra pede ac diam.
957	957	725	2.8	Donec odio justo, sollicitudin ut, suscipit a, feugiat et, eros. Vestibulum ac est lacinia nisi venenatis tristique. Fusce congue, diam id ornare imperdiet, sapien urna pretium nisl, ut volutpat sapien arcu sed augue.
780	780	540	2.8	Integer aliquet, massa id lobortis convallis, tortor risus dapibus augue, vel accumsan tellus nisi eu orci. Mauris lacinia sapien quis libero. Nullam sit amet turpis elementum ligula vehicula consequat.
851	851	322	2.8	In blandit ultrices enim. Lorem ipsum dolor sit amet, consectetuer adipiscing elit.
468	468	914	2.8	Integer ac neque. Duis bibendum. Morbi non quam nec dui luctus rutrum.
\.


--
-- TOC entry 5366 (class 0 OID 31195)
-- Dependencies: 246
-- Data for Name: reservacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.reservacion (id_reservacion, id_empleado, id_huesped, cant_huespedes_totales, estado) FROM stdin;
3	253	443	4	RECHAZADA
4	96	149	6	CANCELADA
5	215	867	6	CANCELADA
6	467	584	7	RECHAZADA
7	168	440	3	CANCELADA
8	273	145	1	RECHAZADA
9	210	169	3	CONFIRMADA
11	528	254	8	CONFIRMADA
12	507	672	2	PENDIENTE
13	441	440	8	RECHAZADA
17	72	281	3	RECHAZADA
18	263	4	9	CANCELADA
19	13	230	4	CANCELADA
20	288	121	9	CANCELADA
21	292	601	6	CANCELADA
24	129	760	2	CONFIRMADA
25	404	120	2	CONFIRMADA
27	317	911	3	CONFIRMADA
28	182	941	9	RECHAZADA
29	535	572	1	PENDIENTE
30	143	784	6	CONFIRMADA
31	344	462	10	CANCELADA
32	420	808	3	RECHAZADA
33	32	168	9	RECHAZADA
34	27	630	6	CONFIRMADA
35	411	140	10	RECHAZADA
37	427	691	2	RECHAZADA
38	33	205	2	CONFIRMADA
39	371	765	7	CANCELADA
41	545	846	2	CANCELADA
42	33	503	5	RECHAZADA
43	243	920	10	CONFIRMADA
44	403	419	5	CANCELADA
46	176	589	5	RECHAZADA
47	111	703	3	CONFIRMADA
49	469	612	10	RECHAZADA
50	182	222	2	PENDIENTE
51	91	35	5	CANCELADA
52	304	926	3	CANCELADA
54	33	815	6	CANCELADA
56	484	156	9	CONFIRMADA
57	99	767	2	CONFIRMADA
58	446	630	9	CANCELADA
60	358	224	5	CONFIRMADA
62	445	354	7	CANCELADA
64	316	303	4	CANCELADA
65	487	494	7	CONFIRMADA
66	274	957	6	RECHAZADA
67	397	298	8	RECHAZADA
68	283	687	4	CONFIRMADA
69	106	554	10	RECHAZADA
72	358	210	5	CANCELADA
74	167	150	4	PENDIENTE
75	222	399	4	CONFIRMADA
77	113	25	10	PENDIENTE
78	114	608	5	RECHAZADA
79	242	50	4	CONFIRMADA
81	155	836	10	CANCELADA
82	519	338	10	CANCELADA
84	87	223	10	CANCELADA
85	133	125	2	CANCELADA
86	127	574	4	CANCELADA
87	180	636	4	PENDIENTE
88	89	769	4	CANCELADA
89	54	449	1	RECHAZADA
90	64	948	4	PENDIENTE
91	419	452	6	CANCELADA
92	433	316	4	CONFIRMADA
93	319	279	8	RECHAZADA
94	64	482	5	RECHAZADA
95	528	517	8	RECHAZADA
97	369	121	4	CANCELADA
98	537	777	10	RECHAZADA
99	192	706	5	CONFIRMADA
103	137	587	10	CANCELADA
104	293	806	4	CANCELADA
105	533	117	9	PENDIENTE
106	479	90	4	RECHAZADA
107	380	545	4	CANCELADA
108	231	526	2	CANCELADA
109	436	759	9	PENDIENTE
111	111	476	8	CANCELADA
112	49	688	5	PENDIENTE
113	364	486	1	CANCELADA
114	267	992	6	RECHAZADA
115	1	765	5	CANCELADA
117	493	16	6	CANCELADA
118	180	267	6	CONFIRMADA
119	317	782	6	CANCELADA
120	65	587	3	CONFIRMADA
123	246	230	1	CONFIRMADA
125	139	959	4	RECHAZADA
126	360	812	1	CONFIRMADA
127	130	297	1	RECHAZADA
128	451	733	4	RECHAZADA
129	488	889	9	CONFIRMADA
130	322	827	4	CANCELADA
131	409	432	6	CANCELADA
133	156	433	5	CANCELADA
135	472	613	10	CONFIRMADA
136	135	681	8	PENDIENTE
138	265	98	9	RECHAZADA
139	143	861	3	CANCELADA
141	202	743	10	CANCELADA
142	31	268	10	RECHAZADA
144	75	57	3	RECHAZADA
145	491	261	7	PENDIENTE
146	82	22	6	RECHAZADA
147	203	350	7	CANCELADA
149	419	219	9	CANCELADA
150	138	891	8	CANCELADA
151	98	195	8	CANCELADA
152	139	992	4	CANCELADA
153	525	363	2	CONFIRMADA
155	409	371	3	RECHAZADA
156	404	766	5	RECHAZADA
157	141	963	9	RECHAZADA
158	127	41	1	CANCELADA
159	377	421	6	PENDIENTE
160	302	217	10	CANCELADA
162	500	851	3	RECHAZADA
163	522	753	8	CONFIRMADA
164	390	934	2	CONFIRMADA
165	217	99	3	CANCELADA
166	170	810	5	CANCELADA
167	324	158	4	RECHAZADA
169	319	202	3	CANCELADA
170	278	33	9	CANCELADA
171	43	739	1	CONFIRMADA
172	176	277	10	CANCELADA
173	540	738	4	RECHAZADA
174	444	968	6	RECHAZADA
175	103	927	6	CANCELADA
176	419	103	1	CANCELADA
177	515	165	6	CANCELADA
178	410	615	1	CANCELADA
180	332	500	3	RECHAZADA
181	124	385	7	CANCELADA
182	456	71	5	CANCELADA
183	260	195	5	RECHAZADA
184	500	929	4	RECHAZADA
185	55	585	7	CONFIRMADA
187	493	867	6	CANCELADA
188	35	440	1	RECHAZADA
189	27	459	10	RECHAZADA
190	92	488	8	RECHAZADA
191	77	202	7	CANCELADA
192	139	526	6	CANCELADA
193	158	320	9	CANCELADA
194	504	271	7	CANCELADA
195	479	244	3	PENDIENTE
196	61	941	9	CONFIRMADA
197	17	475	6	CANCELADA
198	26	328	6	RECHAZADA
199	318	276	3	CANCELADA
201	77	62	2	RECHAZADA
202	319	278	4	RECHAZADA
203	251	433	4	RECHAZADA
204	127	926	7	PENDIENTE
205	290	409	6	RECHAZADA
206	436	107	9	CONFIRMADA
207	131	39	10	CANCELADA
208	409	517	3	CANCELADA
210	379	88	7	RECHAZADA
211	82	180	2	CANCELADA
212	366	825	9	RECHAZADA
213	435	795	5	CANCELADA
216	550	462	9	PENDIENTE
217	344	449	3	RECHAZADA
218	200	255	7	CONFIRMADA
219	304	569	4	CANCELADA
220	131	353	10	RECHAZADA
222	420	935	9	RECHAZADA
223	355	575	7	CONFIRMADA
225	5	707	8	RECHAZADA
227	35	783	10	CONFIRMADA
229	73	57	5	PENDIENTE
230	508	747	5	CANCELADA
232	166	840	5	RECHAZADA
236	532	150	1	RECHAZADA
237	522	49	3	RECHAZADA
238	360	585	7	CANCELADA
239	124	481	3	CANCELADA
240	246	2	6	RECHAZADA
241	482	518	7	CANCELADA
242	229	694	3	RECHAZADA
244	176	744	2	CONFIRMADA
245	40	24	8	CONFIRMADA
246	524	16	3	CONFIRMADA
247	223	81	6	RECHAZADA
248	147	32	1	CANCELADA
249	24	636	7	RECHAZADA
250	82	924	9	CANCELADA
251	278	597	6	CONFIRMADA
252	517	27	3	RECHAZADA
255	91	670	7	CANCELADA
256	222	749	7	RECHAZADA
257	8	950	5	PENDIENTE
258	20	611	7	RECHAZADA
259	113	959	10	CONFIRMADA
262	123	698	6	RECHAZADA
263	135	67	8	CONFIRMADA
264	101	257	7	RECHAZADA
265	108	100	6	PENDIENTE
267	522	819	2	CONFIRMADA
268	374	266	10	CONFIRMADA
269	296	791	3	CANCELADA
270	402	141	2	RECHAZADA
271	324	271	10	RECHAZADA
272	17	952	3	RECHAZADA
273	426	528	9	RECHAZADA
274	109	473	3	RECHAZADA
275	537	15	7	CANCELADA
276	181	202	1	CANCELADA
277	59	671	2	CANCELADA
278	194	536	9	RECHAZADA
279	528	933	8	CANCELADA
280	196	938	8	RECHAZADA
282	5	985	4	CANCELADA
285	51	919	6	CONFIRMADA
287	253	787	8	PENDIENTE
290	276	698	3	CANCELADA
291	451	560	6	PENDIENTE
292	536	540	7	PENDIENTE
293	214	134	5	CONFIRMADA
295	224	283	8	CONFIRMADA
296	352	611	2	CANCELADA
297	48	972	3	RECHAZADA
298	476	831	3	PENDIENTE
299	73	979	2	PENDIENTE
301	472	742	9	RECHAZADA
302	175	989	5	CANCELADA
303	17	821	5	CONFIRMADA
304	201	830	6	CANCELADA
305	45	93	2	RECHAZADA
306	503	252	9	RECHAZADA
307	390	185	8	CANCELADA
308	304	454	3	RECHAZADA
309	290	990	6	CONFIRMADA
310	475	35	1	CANCELADA
311	168	994	10	CONFIRMADA
312	121	63	3	RECHAZADA
313	5	58	9	CONFIRMADA
314	519	565	6	CANCELADA
315	12	476	1	PENDIENTE
316	300	240	4	CANCELADA
320	44	259	7	PENDIENTE
324	516	728	4	CANCELADA
325	343	463	1	PENDIENTE
326	433	679	6	CONFIRMADA
329	136	175	10	CONFIRMADA
330	300	127	8	CONFIRMADA
331	38	998	4	CONFIRMADA
332	49	982	2	CONFIRMADA
333	252	787	8	CANCELADA
334	4	127	9	CONFIRMADA
335	259	38	3	PENDIENTE
336	239	68	2	RECHAZADA
337	355	529	5	CONFIRMADA
338	308	601	1	PENDIENTE
339	256	733	3	CANCELADA
340	352	789	10	PENDIENTE
343	385	201	10	CANCELADA
345	11	111	3	CANCELADA
346	3	905	6	PENDIENTE
347	112	488	1	CANCELADA
349	487	136	10	PENDIENTE
353	64	720	7	CANCELADA
355	391	755	4	RECHAZADA
356	69	387	4	RECHAZADA
357	478	646	2	PENDIENTE
358	34	718	10	RECHAZADA
359	381	561	3	CANCELADA
360	403	636	2	PENDIENTE
361	16	717	10	CANCELADA
362	249	738	8	RECHAZADA
363	180	202	4	RECHAZADA
364	483	700	6	PENDIENTE
365	305	487	4	CANCELADA
367	348	405	8	CANCELADA
368	281	963	3	RECHAZADA
369	189	291	6	CANCELADA
370	46	732	3	CONFIRMADA
371	473	329	9	RECHAZADA
372	346	988	8	PENDIENTE
373	215	290	2	CANCELADA
374	361	977	1	CONFIRMADA
375	301	670	6	CONFIRMADA
377	368	134	7	CANCELADA
378	151	849	9	CANCELADA
379	547	791	5	RECHAZADA
380	305	225	6	CONFIRMADA
381	469	252	3	CANCELADA
382	277	411	8	RECHAZADA
384	512	985	3	RECHAZADA
386	6	789	1	PENDIENTE
387	121	207	9	CONFIRMADA
388	340	113	10	RECHAZADA
389	453	319	10	CANCELADA
390	178	176	6	CANCELADA
391	112	452	4	CONFIRMADA
393	542	763	3	CANCELADA
394	249	554	2	RECHAZADA
397	451	182	6	RECHAZADA
398	43	298	9	CANCELADA
399	271	192	3	CANCELADA
401	157	609	8	CANCELADA
403	313	717	3	CANCELADA
406	341	124	3	CANCELADA
407	414	114	4	RECHAZADA
408	73	606	7	CANCELADA
409	3	711	1	RECHAZADA
410	343	586	8	PENDIENTE
411	380	112	9	PENDIENTE
413	227	7	2	CANCELADA
414	81	467	3	RECHAZADA
415	416	781	4	CANCELADA
416	523	761	1	RECHAZADA
417	382	847	9	PENDIENTE
418	389	62	10	CANCELADA
419	363	883	7	RECHAZADA
420	293	50	6	CANCELADA
422	276	853	7	RECHAZADA
423	406	919	5	CANCELADA
424	201	311	4	PENDIENTE
427	18	84	5	PENDIENTE
428	456	856	9	PENDIENTE
429	269	538	1	CANCELADA
432	170	766	4	PENDIENTE
433	23	296	8	CANCELADA
434	126	371	10	CONFIRMADA
436	101	620	2	RECHAZADA
437	47	664	9	RECHAZADA
439	453	403	6	CANCELADA
440	417	612	10	RECHAZADA
443	31	193	5	CONFIRMADA
444	529	322	6	CANCELADA
445	244	363	10	CANCELADA
448	225	644	9	PENDIENTE
450	374	170	8	RECHAZADA
452	215	387	4	CONFIRMADA
453	165	133	9	RECHAZADA
455	201	11	9	RECHAZADA
456	138	747	10	RECHAZADA
459	207	417	8	RECHAZADA
460	317	730	9	CANCELADA
461	202	795	1	PENDIENTE
463	250	327	7	PENDIENTE
464	225	31	6	RECHAZADA
465	88	750	6	CANCELADA
466	285	457	5	RECHAZADA
467	14	171	2	PENDIENTE
469	126	552	1	CONFIRMADA
472	232	554	3	CANCELADA
473	488	508	7	RECHAZADA
474	323	797	1	CANCELADA
476	522	90	7	PENDIENTE
477	387	706	10	RECHAZADA
478	537	129	10	CANCELADA
479	392	120	8	PENDIENTE
481	7	13	2	RECHAZADA
483	356	917	6	RECHAZADA
484	88	355	4	CANCELADA
485	33	650	6	CONFIRMADA
486	105	632	5	PENDIENTE
487	341	405	3	PENDIENTE
489	233	279	10	CANCELADA
491	456	469	6	CANCELADA
492	259	717	6	PENDIENTE
493	9	383	3	RECHAZADA
494	495	986	1	PENDIENTE
495	426	122	4	CANCELADA
496	345	661	8	CANCELADA
497	373	348	9	CANCELADA
498	379	977	5	CANCELADA
499	98	823	8	RECHAZADA
500	303	195	8	CANCELADA
501	113	918	2	RECHAZADA
502	450	216	9	CANCELADA
504	154	980	8	PENDIENTE
505	41	534	9	PENDIENTE
506	206	326	7	RECHAZADA
507	486	813	2	RECHAZADA
508	324	194	10	CANCELADA
512	355	255	3	RECHAZADA
513	311	338	1	RECHAZADA
514	440	181	7	CANCELADA
515	47	425	2	CONFIRMADA
516	208	913	4	CONFIRMADA
519	92	151	10	RECHAZADA
521	519	690	5	CANCELADA
522	257	594	2	CONFIRMADA
523	466	710	10	CONFIRMADA
524	84	8	7	CANCELADA
526	60	225	4	PENDIENTE
527	329	436	10	CANCELADA
528	499	677	1	PENDIENTE
529	131	560	5	CANCELADA
530	253	114	9	CANCELADA
531	218	2	5	RECHAZADA
533	212	186	10	PENDIENTE
535	4	312	10	RECHAZADA
538	468	28	10	PENDIENTE
540	18	783	1	CANCELADA
541	170	831	4	RECHAZADA
542	78	954	7	PENDIENTE
543	436	486	3	CANCELADA
546	319	763	5	CONFIRMADA
548	164	69	8	PENDIENTE
549	332	970	9	RECHAZADA
550	235	966	10	CANCELADA
551	397	91	6	RECHAZADA
552	292	940	8	CANCELADA
554	207	605	4	RECHAZADA
556	349	338	8	CANCELADA
558	550	54	1	CANCELADA
559	276	331	6	RECHAZADA
560	540	700	3	RECHAZADA
561	117	660	2	RECHAZADA
562	230	145	3	CANCELADA
563	157	134	3	CANCELADA
564	365	519	6	CANCELADA
565	251	500	2	RECHAZADA
567	448	538	10	RECHAZADA
568	365	299	9	RECHAZADA
569	212	883	6	CONFIRMADA
570	220	81	5	PENDIENTE
572	193	599	8	CANCELADA
573	359	714	8	RECHAZADA
575	518	493	8	PENDIENTE
576	529	303	5	RECHAZADA
577	131	201	6	RECHAZADA
578	212	274	7	PENDIENTE
580	106	6	5	CANCELADA
582	8	477	9	CANCELADA
584	319	19	10	CANCELADA
585	27	175	3	CANCELADA
586	6	819	3	CANCELADA
587	442	325	9	CONFIRMADA
589	392	127	2	PENDIENTE
590	544	863	7	PENDIENTE
591	475	864	5	PENDIENTE
592	341	552	10	CANCELADA
593	128	443	3	CONFIRMADA
594	418	217	1	CANCELADA
595	309	828	2	PENDIENTE
596	463	258	3	PENDIENTE
597	43	714	2	RECHAZADA
598	332	308	6	CANCELADA
601	439	537	8	CANCELADA
603	370	892	7	CONFIRMADA
604	64	887	8	RECHAZADA
605	170	285	7	PENDIENTE
607	49	262	3	CANCELADA
608	2	598	1	RECHAZADA
609	240	996	6	PENDIENTE
610	10	381	5	RECHAZADA
611	130	13	10	RECHAZADA
612	467	498	4	RECHAZADA
613	315	631	1	CONFIRMADA
614	184	51	9	RECHAZADA
615	77	292	9	RECHAZADA
617	358	811	7	PENDIENTE
618	520	653	5	CONFIRMADA
619	63	184	10	RECHAZADA
620	542	888	6	RECHAZADA
621	112	712	2	CANCELADA
623	522	518	7	RECHAZADA
624	266	113	4	RECHAZADA
625	218	102	5	CANCELADA
626	182	428	8	RECHAZADA
628	152	692	8	CANCELADA
629	85	2	10	CANCELADA
630	486	280	8	CONFIRMADA
631	162	255	6	CANCELADA
632	500	720	5	PENDIENTE
633	208	742	3	PENDIENTE
634	302	241	6	CONFIRMADA
635	503	566	2	CANCELADA
636	515	758	4	CANCELADA
639	191	999	7	PENDIENTE
640	326	788	2	RECHAZADA
641	219	893	8	RECHAZADA
643	24	45	6	CONFIRMADA
644	115	293	1	CONFIRMADA
645	439	800	5	CONFIRMADA
646	424	321	8	RECHAZADA
648	522	884	5	RECHAZADA
649	528	603	10	PENDIENTE
653	487	826	7	RECHAZADA
654	260	508	5	RECHAZADA
655	311	482	4	RECHAZADA
656	20	75	1	CANCELADA
657	214	319	10	RECHAZADA
658	449	947	9	CANCELADA
659	431	778	1	PENDIENTE
660	362	204	10	PENDIENTE
661	287	401	2	PENDIENTE
663	238	413	4	CANCELADA
664	226	400	10	RECHAZADA
665	396	582	2	CANCELADA
667	88	59	6	CANCELADA
670	136	440	7	CANCELADA
671	19	405	2	CONFIRMADA
672	18	304	5	RECHAZADA
673	211	3	2	PENDIENTE
674	440	454	10	CONFIRMADA
675	262	421	6	CANCELADA
676	258	857	8	CONFIRMADA
677	480	217	1	CONFIRMADA
678	224	537	6	CONFIRMADA
679	157	607	7	RECHAZADA
680	132	627	7	CANCELADA
681	320	770	6	CANCELADA
682	403	640	8	RECHAZADA
683	468	900	9	PENDIENTE
685	143	833	7	RECHAZADA
686	249	262	7	CANCELADA
687	133	16	4	CONFIRMADA
688	423	543	4	RECHAZADA
689	545	76	2	RECHAZADA
690	473	106	3	PENDIENTE
691	492	523	2	CANCELADA
692	437	759	7	RECHAZADA
694	174	457	10	CONFIRMADA
695	364	960	9	RECHAZADA
696	88	418	6	RECHAZADA
697	286	541	6	CANCELADA
698	29	713	7	PENDIENTE
701	202	402	1	PENDIENTE
703	465	785	5	CANCELADA
705	307	632	1	CANCELADA
706	30	621	7	PENDIENTE
707	149	12	5	RECHAZADA
709	75	306	1	RECHAZADA
710	452	374	2	PENDIENTE
712	258	827	7	CONFIRMADA
713	263	986	5	CANCELADA
714	180	50	3	CANCELADA
715	461	671	7	CANCELADA
716	469	934	4	CANCELADA
717	273	259	9	PENDIENTE
718	475	116	8	CONFIRMADA
720	449	621	5	RECHAZADA
722	165	923	7	CANCELADA
723	95	830	8	CONFIRMADA
724	483	80	8	CANCELADA
725	292	931	8	RECHAZADA
726	485	505	4	CANCELADA
727	431	619	2	RECHAZADA
729	429	850	4	CONFIRMADA
730	249	531	7	PENDIENTE
731	241	545	3	CONFIRMADA
733	492	490	10	PENDIENTE
735	430	754	6	RECHAZADA
736	405	584	10	RECHAZADA
737	81	867	4	CANCELADA
738	199	894	10	CANCELADA
739	461	527	2	RECHAZADA
741	404	764	8	RECHAZADA
742	263	851	6	CONFIRMADA
743	417	707	5	CANCELADA
745	29	869	2	CONFIRMADA
746	468	254	4	CONFIRMADA
747	487	356	3	CONFIRMADA
748	169	655	7	PENDIENTE
749	40	824	7	RECHAZADA
750	296	162	6	CANCELADA
751	250	216	2	CONFIRMADA
752	44	328	2	CANCELADA
753	19	226	6	CANCELADA
754	104	408	5	RECHAZADA
756	188	597	3	RECHAZADA
758	262	444	4	CANCELADA
759	71	410	3	CANCELADA
761	189	679	10	PENDIENTE
762	16	377	4	CANCELADA
765	228	697	6	RECHAZADA
766	504	312	1	RECHAZADA
768	244	648	1	CANCELADA
769	53	342	8	CONFIRMADA
770	408	381	2	PENDIENTE
771	101	82	7	CONFIRMADA
772	407	971	9	PENDIENTE
773	134	173	3	CANCELADA
775	523	45	2	RECHAZADA
777	18	546	9	CANCELADA
778	515	975	3	CANCELADA
779	534	763	7	CONFIRMADA
781	537	801	1	CANCELADA
782	108	134	7	CANCELADA
785	502	340	7	RECHAZADA
787	483	630	2	CANCELADA
788	492	910	10	CANCELADA
789	86	279	2	CONFIRMADA
792	74	44	4	PENDIENTE
793	250	760	5	RECHAZADA
795	90	585	8	CANCELADA
797	51	674	3	CANCELADA
800	256	773	7	CANCELADA
801	313	243	6	RECHAZADA
802	172	29	2	RECHAZADA
803	505	146	9	CANCELADA
804	375	531	5	PENDIENTE
805	364	595	9	RECHAZADA
806	492	10	1	RECHAZADA
808	146	848	5	CANCELADA
809	148	816	1	CONFIRMADA
812	4	991	9	CANCELADA
813	152	305	4	RECHAZADA
815	485	710	8	CANCELADA
818	392	507	8	RECHAZADA
819	151	52	10	RECHAZADA
821	463	521	4	RECHAZADA
822	420	7	6	CANCELADA
824	35	126	10	CONFIRMADA
826	437	313	7	PENDIENTE
828	516	62	2	RECHAZADA
829	294	208	9	RECHAZADA
830	152	554	9	PENDIENTE
831	396	846	7	RECHAZADA
832	34	551	2	RECHAZADA
833	479	419	6	RECHAZADA
834	465	303	7	CONFIRMADA
835	516	989	4	RECHAZADA
836	345	795	9	PENDIENTE
837	48	663	1	RECHAZADA
839	270	863	10	PENDIENTE
840	72	743	4	RECHAZADA
841	24	737	7	CANCELADA
842	529	61	10	CANCELADA
843	276	915	10	PENDIENTE
844	154	339	2	PENDIENTE
847	234	229	10	RECHAZADA
849	82	164	6	CANCELADA
850	416	139	9	CONFIRMADA
853	166	291	2	RECHAZADA
856	250	700	2	CANCELADA
857	8	723	7	RECHAZADA
860	250	355	5	CANCELADA
864	221	899	1	CANCELADA
866	418	560	8	RECHAZADA
867	357	747	6	RECHAZADA
868	302	797	7	PENDIENTE
869	177	246	6	CANCELADA
871	346	127	7	CANCELADA
872	159	311	1	RECHAZADA
873	23	603	4	CONFIRMADA
874	304	213	7	RECHAZADA
875	192	167	7	RECHAZADA
876	235	721	2	CANCELADA
877	10	768	2	CANCELADA
878	170	371	9	PENDIENTE
879	11	831	7	PENDIENTE
880	109	329	6	PENDIENTE
881	235	260	8	CANCELADA
882	352	15	8	RECHAZADA
883	493	294	7	RECHAZADA
885	109	579	7	RECHAZADA
886	520	319	9	PENDIENTE
888	44	366	1	CANCELADA
889	147	225	5	RECHAZADA
890	374	754	8	CONFIRMADA
892	301	716	5	RECHAZADA
893	383	170	4	CANCELADA
894	127	228	7	PENDIENTE
897	375	739	7	PENDIENTE
898	38	961	6	CANCELADA
899	491	427	9	CONFIRMADA
900	89	221	8	CONFIRMADA
902	200	273	6	CANCELADA
904	140	948	2	CANCELADA
905	7	61	5	RECHAZADA
906	393	947	9	RECHAZADA
908	387	221	8	CANCELADA
909	441	239	9	CANCELADA
911	191	525	8	RECHAZADA
912	168	97	2	CONFIRMADA
913	115	68	9	RECHAZADA
914	393	651	2	RECHAZADA
915	296	925	10	CANCELADA
916	319	669	6	CANCELADA
917	189	86	7	PENDIENTE
918	211	97	7	PENDIENTE
919	470	929	1	CANCELADA
920	247	331	3	CANCELADA
923	253	291	4	RECHAZADA
924	167	372	6	CANCELADA
925	245	575	2	RECHAZADA
926	84	638	7	CONFIRMADA
928	476	165	1	CONFIRMADA
929	326	484	1	RECHAZADA
930	151	532	1	CANCELADA
932	250	302	5	CANCELADA
933	522	975	3	CANCELADA
935	158	10	10	CANCELADA
938	146	56	4	CANCELADA
939	492	740	3	RECHAZADA
941	186	426	6	RECHAZADA
942	243	751	9	CONFIRMADA
943	440	569	9	CANCELADA
944	28	935	10	RECHAZADA
947	231	121	10	CANCELADA
948	369	284	7	CONFIRMADA
950	98	96	3	CANCELADA
951	181	210	1	CANCELADA
952	355	1000	4	RECHAZADA
953	20	708	7	RECHAZADA
954	375	11	2	PENDIENTE
955	313	516	3	CANCELADA
956	98	865	9	RECHAZADA
959	88	717	3	CANCELADA
960	536	965	8	CONFIRMADA
961	328	767	4	PENDIENTE
962	398	915	9	CANCELADA
968	46	201	8	CANCELADA
969	468	732	2	RECHAZADA
971	212	139	8	CANCELADA
972	6	262	6	PENDIENTE
973	472	163	1	CANCELADA
974	236	615	2	PENDIENTE
975	472	729	4	RECHAZADA
976	509	188	7	CANCELADA
977	165	150	8	RECHAZADA
978	263	371	8	CONFIRMADA
979	409	563	1	CONFIRMADA
980	247	38	4	RECHAZADA
982	300	786	1	RECHAZADA
983	380	953	6	PENDIENTE
984	367	469	6	RECHAZADA
985	517	745	1	CONFIRMADA
987	511	504	1	RECHAZADA
988	284	698	5	PENDIENTE
989	136	450	4	CONFIRMADA
990	356	432	5	CANCELADA
991	271	991	3	CONFIRMADA
992	411	651	6	CONFIRMADA
993	255	233	4	CANCELADA
994	549	430	3	CANCELADA
995	431	197	7	CONFIRMADA
996	267	542	3	RECHAZADA
997	473	114	1	CANCELADA
999	288	601	8	RECHAZADA
1000	86	284	9	RECHAZADA
934	403	661	7	COMPLETADA
780	109	609	9	COMPLETADA
967	234	861	3	COMPLETADA
544	109	605	9	COMPLETADA
284	69	999	3	COMPLETADA
318	81	899	10	COMPLETADA
235	391	329	10	COMPLETADA
700	522	112	6	COMPLETADA
708	411	480	5	COMPLETADA
887	22	822	10	COMPLETADA
261	249	451	8	COMPLETADA
61	159	422	9	COMPLETADA
209	284	377	5	COMPLETADA
827	199	838	4	COMPLETADA
581	361	16	5	COMPLETADA
783	346	867	8	COMPLETADA
740	228	71	8	COMPLETADA
462	49	114	8	COMPLETADA
96	410	527	2	COMPLETADA
341	28	924	6	COMPLETADA
168	297	209	1	COMPLETADA
545	399	944	5	COMPLETADA
957	511	91	6	COMPLETADA
517	307	828	6	COMPLETADA
786	532	375	8	COMPLETADA
776	143	266	7	COMPLETADA
63	383	38	5	COMPLETADA
970	191	877	3	COMPLETADA
342	415	980	1	COMPLETADA
454	164	423	10	COMPLETADA
283	36	258	10	COMPLETADA
148	175	123	5	COMPLETADA
396	324	992	7	COMPLETADA
981	46	781	4	COMPLETADA
451	360	232	2	COMPLETADA
958	243	740	2	COMPLETADA
405	148	398	4	COMPLETADA
536	76	758	4	COMPLETADA
281	195	905	4	COMPLETADA
539	348	616	4	COMPLETADA
16	149	143	10	COMPLETADA
134	164	151	4	COMPLETADA
927	110	477	2	COMPLETADA
430	91	827	6	COMPLETADA
470	8	355	8	COMPLETADA
858	179	784	9	COMPLETADA
851	419	959	8	COMPLETADA
55	512	103	6	COMPLETADA
221	174	562	8	COMPLETADA
321	426	403	1	COMPLETADA
668	191	106	3	COMPLETADA
243	236	39	8	COMPLETADA
602	312	28	2	COMPLETADA
845	412	152	9	COMPLETADA
124	345	136	6	COMPLETADA
490	43	26	10	COMPLETADA
763	86	554	6	COMPLETADA
266	389	935	3	COMPLETADA
383	483	303	3	COMPLETADA
637	241	929	1	COMPLETADA
534	147	18	8	COMPLETADA
964	335	873	1	COMPLETADA
963	524	389	5	COMPLETADA
907	364	80	5	COMPLETADA
228	476	262	7	COMPLETADA
764	313	347	6	COMPLETADA
121	113	534	10	COMPLETADA
200	490	765	10	COMPLETADA
711	117	685	1	COMPLETADA
566	19	439	7	COMPLETADA
73	538	621	4	COMPLETADA
945	92	971	2	COMPLETADA
719	471	29	1	COMPLETADA
322	186	628	1	COMPLETADA
71	103	868	4	COMPLETADA
350	437	621	7	COMPLETADA
791	452	820	5	COMPLETADA
865	508	462	3	COMPLETADA
721	226	355	2	COMPLETADA
468	327	472	5	COMPLETADA
796	161	441	4	COMPLETADA
10	19	409	10	COMPLETADA
684	34	136	4	COMPLETADA
179	379	580	7	COMPLETADA
854	356	519	1	COMPLETADA
161	261	893	5	COMPLETADA
810	204	642	3	COMPLETADA
642	466	230	6	COMPLETADA
122	268	415	1	COMPLETADA
794	347	76	3	COMPLETADA
475	13	842	2	COMPLETADA
488	441	8	1	COMPLETADA
816	314	592	3	COMPLETADA
385	355	500	5	COMPLETADA
438	401	178	7	COMPLETADA
537	248	600	3	COMPLETADA
1	524	887	9	COMPLETADA
253	136	288	10	COMPLETADA
807	429	741	6	COMPLETADA
317	508	928	4	COMPLETADA
518	303	532	1	COMPLETADA
457	5	87	3	COMPLETADA
755	435	386	7	COMPLETADA
449	22	155	6	COMPLETADA
790	173	129	4	COMPLETADA
616	488	491	4	COMPLETADA
289	37	377	9	COMPLETADA
852	331	59	5	COMPLETADA
233	236	153	7	COMPLETADA
226	413	52	8	COMPLETADA
767	486	442	4	COMPLETADA
323	202	33	3	COMPLETADA
294	494	254	5	COMPLETADA
352	267	678	5	COMPLETADA
140	490	529	2	COMPLETADA
622	285	610	6	COMPLETADA
395	421	854	5	COMPLETADA
214	435	147	9	COMPLETADA
447	387	711	6	COMPLETADA
891	259	440	8	COMPLETADA
458	40	132	10	COMPLETADA
940	193	58	7	COMPLETADA
838	477	941	4	COMPLETADA
431	428	452	6	COMPLETADA
48	60	173	10	COMPLETADA
404	208	995	3	COMPLETADA
511	415	871	8	CANCELADA
426	93	80	7	CANCELADA
702	298	973	2	CANCELADA
137	149	203	3	CANCELADA
132	120	822	3	CANCELADA
937	330	769	3	CANCELADA
260	249	394	3	CANCELADA
446	497	544	7	CANCELADA
744	53	498	10	CANCELADA
76	311	460	2	CANCELADA
884	207	322	1	CANCELADA
425	217	632	3	CANCELADA
846	487	419	2	CANCELADA
366	74	675	4	CANCELADA
848	275	864	2	CANCELADA
328	56	619	3	CANCELADA
588	263	806	2	CANCELADA
811	40	883	1	CANCELADA
579	237	807	8	CANCELADA
921	63	78	4	CANCELADA
965	91	188	6	CANCELADA
532	174	465	6	CANCELADA
863	238	615	4	CANCELADA
583	462	715	10	CANCELADA
154	69	325	8	CANCELADA
862	32	950	6	CANCELADA
666	12	400	7	CANCELADA
186	235	438	3	CANCELADA
760	393	204	5	CANCELADA
15	217	7	8	CANCELADA
435	152	385	4	CANCELADA
784	413	186	1	CANCELADA
903	20	94	3	CANCELADA
693	205	861	8	CANCELADA
110	208	373	5	CANCELADA
510	255	778	1	CANCELADA
774	118	537	5	CANCELADA
817	336	628	4	CANCELADA
627	92	746	1	CANCELADA
2	270	482	9	CANCELADA
734	234	344	4	CANCELADA
895	398	293	10	CANCELADA
254	546	600	4	CANCELADA
348	431	682	4	CANCELADA
520	318	638	8	CANCELADA
354	536	764	4	CANCELADA
901	472	715	5	CANCELADA
574	39	566	2	CANCELADA
300	77	366	4	CANCELADA
26	332	976	4	CANCELADA
662	519	162	9	CANCELADA
547	48	720	4	CANCELADA
231	12	713	6	CANCELADA
553	186	75	6	CANCELADA
288	141	452	7	CANCELADA
100	121	788	3	CANCELADA
571	377	165	5	CANCELADA
402	449	71	9	CANCELADA
606	300	736	7	CANCELADA
825	165	970	9	CANCELADA
699	178	473	6	CANCELADA
351	544	850	2	CANCELADA
116	106	413	10	CANCELADA
798	427	979	7	CANCELADA
638	3	632	2	CANCELADA
442	350	30	6	CANCELADA
80	308	736	5	CANCELADA
36	263	741	9	CANCELADA
949	309	281	8	CANCELADA
936	294	513	2	CANCELADA
557	53	41	7	CANCELADA
59	82	865	8	CANCELADA
651	33	348	9	CANCELADA
966	92	173	7	CANCELADA
392	531	549	2	CANCELADA
922	542	967	5	CANCELADA
471	216	730	5	CANCELADA
503	73	298	7	CANCELADA
319	60	733	10	CANCELADA
327	435	211	7	CANCELADA
376	147	848	1	CANCELADA
143	253	639	7	CANCELADA
234	509	691	1	CANCELADA
757	540	680	6	CANCELADA
728	511	706	10	CANCELADA
509	500	83	9	CANCELADA
647	372	586	4	CANCELADA
555	428	81	9	CANCELADA
814	513	532	10	CANCELADA
931	25	463	2	CANCELADA
45	181	841	4	CANCELADA
859	25	730	6	CANCELADA
421	309	106	9	CANCELADA
650	261	15	4	CANCELADA
22	77	218	9	CANCELADA
823	468	548	3	CANCELADA
480	4	470	6	CANCELADA
704	106	66	10	CANCELADA
286	356	929	3	CANCELADA
896	95	847	5	CANCELADA
998	476	57	6	CANCELADA
870	258	206	5	CANCELADA
412	405	511	4	CANCELADA
525	175	478	9	CANCELADA
820	290	173	1	CANCELADA
599	293	127	2	CANCELADA
482	401	757	9	CANCELADA
40	467	521	3	CANCELADA
600	319	689	8	CANCELADA
861	240	960	5	CANCELADA
83	126	383	7	CANCELADA
224	539	527	6	CANCELADA
23	220	367	1	CANCELADA
215	475	256	7	CANCELADA
799	490	692	8	CANCELADA
652	481	888	7	CANCELADA
101	42	378	8	CANCELADA
53	348	768	2	CANCELADA
441	323	516	2	CANCELADA
732	344	344	1	CANCELADA
400	304	54	9	CANCELADA
669	138	190	9	CANCELADA
855	290	293	5	CANCELADA
946	258	908	10	CANCELADA
70	91	878	7	CANCELADA
910	104	347	1	CANCELADA
102	223	628	10	CANCELADA
986	189	390	1	CANCELADA
344	123	921	10	CANCELADA
14	287	352	8	CANCELADA
1001	244	838	2	COMPLETADA
1002	289	143	2	COMPLETADA
1003	509	899	2	COMPLETADA
1004	180	827	2	COMPLETADA
1005	415	403	2	COMPLETADA
1006	545	838	2	COMPLETADA
1007	462	143	2	COMPLETADA
1008	126	899	2	COMPLETADA
1009	527	827	2	COMPLETADA
1010	327	403	2	COMPLETADA
\.


--
-- TOC entry 5368 (class 0 OID 31206)
-- Dependencies: 248
-- Data for Name: servicio; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.servicio (id_servicio, tipo_servicio, precio) FROM stdin;
1	Desayuno Buffet	15.00
2	Masaje Relajante 60 min	45.00
3	Transporte Aeropuerto	35.00
4	Servicio a la Habitaci??n	10.00
5	Tour Guiado Volcanes	60.00
7	Alquiler de Bicicleta	12.00
8	Clase de Surf Privada	25.00
9	Cena Rom??ntica en Playa	80.00
6	Lavander??a (por libra)	41.00
10	Estacionamiento Valet	32.00
\.


--
-- TOC entry 5371 (class 0 OID 31224)
-- Dependencies: 252
-- Data for Name: tipo_comodidad; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_comodidad (id_tipo_comodidad, tipo_comodidad) FROM stdin;
1	Aire Acondicionado
2	Wi-Fi de Alta Velocidad
3	Smart TV 55 Pulgadas
4	Mini Bar Premium
5	Jacuzzi Privado
6	Balc??n con Vista al Mar
7	Caja Fuerte Digital
8	Cafetera de C??psulas
9	Escritorio de Trabajo Ergon??mico
10	Tina de Ba??o de Inmersi??n
\.


--
-- TOC entry 5373 (class 0 OID 31230)
-- Dependencies: 254
-- Data for Name: tipo_empleado; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_empleado (id_tipo_empleado, tipo_empleado) FROM stdin;
1	Recepcionista
2	Gerente General
3	Personal de Limpieza
4	T??cnico de Mantenimiento
5	Botones / Maletero
6	Chef Ejecutivo
7	Mesero / Camarero
8	Concierge
9	Guardia de Seguridad
10	Valet Parking
\.


--
-- TOC entry 5370 (class 0 OID 31214)
-- Dependencies: 250
-- Data for Name: tipo_habitacion; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.tipo_habitacion (id_tipo_habitacion, tipo_habitacion) FROM stdin;
1	Individual Est??ndar
2	Doble Est??ndar
3	Doble Superior
4	Suite Junior
5	Suite Ejecutiva
6	Suite Presidencial
7	Habitaci??n Familiar
8	Estudio con Cocina Equipada
9	Habitaci??n Accesible (Ley ADA)
10	Penthouse
\.


--
-- TOC entry 5381 (class 0 OID 0)
-- Dependencies: 220
-- Name: aumento_costos_id_aumento_costo_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.aumento_costos_id_aumento_costo_seq', 10, true);


--
-- TOC entry 5382 (class 0 OID 0)
-- Dependencies: 222
-- Name: comodidad_tipo_habitacion_id_comodidad_habitacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.comodidad_tipo_habitacion_id_comodidad_habitacion_seq', 976, true);


--
-- TOC entry 5383 (class 0 OID 0)
-- Dependencies: 224
-- Name: consumo_servicio_id_consumo_servicio_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.consumo_servicio_id_consumo_servicio_seq', 5524, true);


--
-- TOC entry 5384 (class 0 OID 0)
-- Dependencies: 232
-- Name: descuento_id_descuento_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.descuento_id_descuento_seq', 10, true);


--
-- TOC entry 5385 (class 0 OID 0)
-- Dependencies: 234
-- Name: detalle_factura_id_detalle_factura_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.detalle_factura_id_detalle_factura_seq', 1417, true);


--
-- TOC entry 5386 (class 0 OID 0)
-- Dependencies: 235
-- Name: detalle_reservacion_id_detalle_reservacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.detalle_reservacion_id_detalle_reservacion_seq', 1395, true);


--
-- TOC entry 5387 (class 0 OID 0)
-- Dependencies: 237
-- Name: empleado_id_empleado_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.empleado_id_empleado_seq', 550, true);


--
-- TOC entry 5388 (class 0 OID 0)
-- Dependencies: 238
-- Name: estadia_id_estadia_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.estadia_id_estadia_seq', 1010, true);


--
-- TOC entry 5389 (class 0 OID 0)
-- Dependencies: 239
-- Name: factura_id_factura_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.factura_id_factura_seq', 190, true);


--
-- TOC entry 5390 (class 0 OID 0)
-- Dependencies: 240
-- Name: habitacion_id_habitacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.habitacion_id_habitacion_seq', 976, true);


--
-- TOC entry 5391 (class 0 OID 0)
-- Dependencies: 241
-- Name: hotel_id_hotel_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.hotel_id_hotel_seq', 10, true);


--
-- TOC entry 5392 (class 0 OID 0)
-- Dependencies: 243
-- Name: huesped_id_huesped_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.huesped_id_huesped_seq', 1000, true);


--
-- TOC entry 5393 (class 0 OID 0)
-- Dependencies: 245
-- Name: resenia_id_resenia_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.resenia_id_resenia_seq', 1000, true);


--
-- TOC entry 5394 (class 0 OID 0)
-- Dependencies: 247
-- Name: reservacion_id_reservacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.reservacion_id_reservacion_seq', 1010, true);


--
-- TOC entry 5395 (class 0 OID 0)
-- Dependencies: 249
-- Name: servicio_id_servicio_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.servicio_id_servicio_seq', 10, true);


--
-- TOC entry 5396 (class 0 OID 0)
-- Dependencies: 253
-- Name: tipo_comodidad_id_tipo_comodidad_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_comodidad_id_tipo_comodidad_seq', 10, true);


--
-- TOC entry 5397 (class 0 OID 0)
-- Dependencies: 255
-- Name: tipo_empleado_id_tipo_empleado_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_empleado_id_tipo_empleado_seq', 10, true);


--
-- TOC entry 5398 (class 0 OID 0)
-- Dependencies: 256
-- Name: tipo_habitacion_id_tipo_habitacion_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.tipo_habitacion_id_tipo_habitacion_seq', 10, true);


--
-- TOC entry 5082 (class 2606 OID 31273)
-- Name: aumento_costos pk_aumento_costo; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.aumento_costos
    ADD CONSTRAINT pk_aumento_costo PRIMARY KEY (id_aumento_costo);


--
-- TOC entry 5086 (class 2606 OID 31275)
-- Name: comodidad_tipo_habitacion pk_comodidad_tipo_habitacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comodidad_tipo_habitacion
    ADD CONSTRAINT pk_comodidad_tipo_habitacion PRIMARY KEY (id_comodidad_habitacion);


--
-- TOC entry 5088 (class 2606 OID 31277)
-- Name: consumo_servicio pk_consumo_servicio; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumo_servicio
    ADD CONSTRAINT pk_consumo_servicio PRIMARY KEY (id_consumo_servicio);


--
-- TOC entry 5106 (class 2606 OID 31279)
-- Name: descuento pk_descuento; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.descuento
    ADD CONSTRAINT pk_descuento PRIMARY KEY (id_descuento);


--
-- TOC entry 5108 (class 2606 OID 31281)
-- Name: detalle_factura pk_detalle_factura; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT pk_detalle_factura PRIMARY KEY (id_detalle_factura);


--
-- TOC entry 5090 (class 2606 OID 31283)
-- Name: detalle_reservacion pk_detalle_reservacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_reservacion
    ADD CONSTRAINT pk_detalle_reservacion PRIMARY KEY (id_detalle_reservacion);


--
-- TOC entry 5110 (class 2606 OID 31285)
-- Name: empleado pk_empleado; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT pk_empleado PRIMARY KEY (id_empleado);


--
-- TOC entry 5092 (class 2606 OID 31287)
-- Name: estadia pk_estadia; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estadia
    ADD CONSTRAINT pk_estadia PRIMARY KEY (id_estadia);


--
-- TOC entry 5094 (class 2606 OID 31289)
-- Name: factura pk_factura; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT pk_factura PRIMARY KEY (id_factura);


--
-- TOC entry 5098 (class 2606 OID 31291)
-- Name: habitacion pk_habitacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitacion
    ADD CONSTRAINT pk_habitacion PRIMARY KEY (id_habitacion);


--
-- TOC entry 5102 (class 2606 OID 31293)
-- Name: hotel pk_hotel; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hotel
    ADD CONSTRAINT pk_hotel PRIMARY KEY (id_hotel);


--
-- TOC entry 5116 (class 2606 OID 31295)
-- Name: huesped pk_huesped; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.huesped
    ADD CONSTRAINT pk_huesped PRIMARY KEY (id_huesped);


--
-- TOC entry 5122 (class 2606 OID 31297)
-- Name: resenia pk_resenia; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resenia
    ADD CONSTRAINT pk_resenia PRIMARY KEY (id_resenia);


--
-- TOC entry 5126 (class 2606 OID 31299)
-- Name: reservacion pk_reservacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion
    ADD CONSTRAINT pk_reservacion PRIMARY KEY (id_reservacion);


--
-- TOC entry 5128 (class 2606 OID 31301)
-- Name: servicio pk_servicio; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicio
    ADD CONSTRAINT pk_servicio PRIMARY KEY (id_servicio);


--
-- TOC entry 5136 (class 2606 OID 31303)
-- Name: tipo_comodidad pk_tipo_comodidad; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_comodidad
    ADD CONSTRAINT pk_tipo_comodidad PRIMARY KEY (id_tipo_comodidad);


--
-- TOC entry 5140 (class 2606 OID 31305)
-- Name: tipo_empleado pk_tipo_empleado; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_empleado
    ADD CONSTRAINT pk_tipo_empleado PRIMARY KEY (id_tipo_empleado);


--
-- TOC entry 5132 (class 2606 OID 31307)
-- Name: tipo_habitacion pk_tipo_habitacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_habitacion
    ADD CONSTRAINT pk_tipo_habitacion PRIMARY KEY (id_tipo_habitacion);


--
-- TOC entry 5118 (class 2606 OID 31309)
-- Name: huesped uq_correo; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.huesped
    ADD CONSTRAINT uq_correo UNIQUE (correo);


--
-- TOC entry 5112 (class 2606 OID 31311)
-- Name: empleado uq_correo_empleado; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT uq_correo_empleado UNIQUE (correo);


--
-- TOC entry 5120 (class 2606 OID 31313)
-- Name: huesped uq_documento; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.huesped
    ADD CONSTRAINT uq_documento UNIQUE (documento);


--
-- TOC entry 5114 (class 2606 OID 31315)
-- Name: empleado uq_dui; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT uq_dui UNIQUE (dui);


--
-- TOC entry 5096 (class 2606 OID 31317)
-- Name: factura uq_empleado_huesped_estadia; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT uq_empleado_huesped_estadia UNIQUE (id_empleado, id_huesped, id_estadia);


--
-- TOC entry 5100 (class 2606 OID 31319)
-- Name: habitacion uq_hotel_nivel_numhab; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitacion
    ADD CONSTRAINT uq_hotel_nivel_numhab UNIQUE (id_hotel, nivel, numero_habitacion);


--
-- TOC entry 5104 (class 2606 OID 31321)
-- Name: hotel uq_nombre; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.hotel
    ADD CONSTRAINT uq_nombre UNIQUE (nombre);


--
-- TOC entry 5084 (class 2606 OID 31323)
-- Name: aumento_costos uq_nombre_temp; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.aumento_costos
    ADD CONSTRAINT uq_nombre_temp UNIQUE (nombre_temporada);


--
-- TOC entry 5124 (class 2606 OID 31325)
-- Name: resenia uq_resenia_huesped; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resenia
    ADD CONSTRAINT uq_resenia_huesped UNIQUE (id_estadia, id_huesped);


--
-- TOC entry 5138 (class 2606 OID 31327)
-- Name: tipo_comodidad uq_tipo_comodidad; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_comodidad
    ADD CONSTRAINT uq_tipo_comodidad UNIQUE (tipo_comodidad);


--
-- TOC entry 5142 (class 2606 OID 31329)
-- Name: tipo_empleado uq_tipo_empleado; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_empleado
    ADD CONSTRAINT uq_tipo_empleado UNIQUE (tipo_empleado);


--
-- TOC entry 5134 (class 2606 OID 31331)
-- Name: tipo_habitacion uq_tipo_habitacion; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.tipo_habitacion
    ADD CONSTRAINT uq_tipo_habitacion UNIQUE (tipo_habitacion);


--
-- TOC entry 5130 (class 2606 OID 31333)
-- Name: servicio uq_tipo_servicio; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servicio
    ADD CONSTRAINT uq_tipo_servicio UNIQUE (tipo_servicio);


--
-- TOC entry 5331 (class 2618 OID 31485)
-- Name: v_info_general_hoteles _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.v_info_general_hoteles AS
 SELECT h.nombre AS hotel,
    h.calificacion,
    count(DISTINCT h2.id_habitacion) AS cant_habitaciones,
    sum(df.precio_total) AS ganancias
   FROM (((public.hotel h
     JOIN public.habitacion h2 ON ((h.id_hotel = h2.id_hotel)))
     JOIN public.detalle_factura df ON ((h2.id_habitacion = df.id_habitacion)))
     JOIN public.factura f ON ((df.id_factura = f.id_factura)))
  GROUP BY h.id_hotel;


--
-- TOC entry 5168 (class 2620 OID 31536)
-- Name: habitacion tg_check_nivel_habitacion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tg_check_nivel_habitacion BEFORE INSERT OR UPDATE ON public.habitacion FOR EACH ROW EXECUTE FUNCTION public.fn_validar_nivel_habitacion();


--
-- TOC entry 5169 (class 2620 OID 31529)
-- Name: resenia trg_actualizar_calificacion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_actualizar_calificacion AFTER INSERT OR UPDATE ON public.resenia FOR EACH ROW EXECUTE FUNCTION public.fn_actualizar_calificacion_hotel();


--
-- TOC entry 5167 (class 2620 OID 31533)
-- Name: estadia trg_checkout_factura; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_checkout_factura AFTER UPDATE OF checkout ON public.estadia FOR EACH ROW EXECUTE FUNCTION public.fn_generar_factura_checkout();


--
-- TOC entry 5166 (class 2620 OID 31527)
-- Name: detalle_reservacion trg_verificar_reserva; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_verificar_reserva BEFORE INSERT OR UPDATE ON public.detalle_reservacion FOR EACH ROW EXECUTE FUNCTION public.fn_validar_disponibilidad_habitacion();


--
-- TOC entry 5156 (class 2606 OID 31335)
-- Name: detalle_factura fk_aumento_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT fk_aumento_detalle FOREIGN KEY (id_aumento_costo) REFERENCES public.aumento_costos(id_aumento_costo) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5157 (class 2606 OID 31340)
-- Name: detalle_factura fk_descuento_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT fk_descuento_detalle FOREIGN KEY (id_descuento) REFERENCES public.descuento(id_descuento) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5164 (class 2606 OID 31345)
-- Name: reservacion fk_empleado; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion
    ADD CONSTRAINT fk_empleado FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5151 (class 2606 OID 31350)
-- Name: factura fk_empleado_factura; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT fk_empleado_factura FOREIGN KEY (id_empleado) REFERENCES public.empleado(id_empleado) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5162 (class 2606 OID 31355)
-- Name: resenia fk_estadia; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resenia
    ADD CONSTRAINT fk_estadia FOREIGN KEY (id_estadia) REFERENCES public.estadia(id_estadia) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5145 (class 2606 OID 31360)
-- Name: consumo_servicio fk_estadia_consumo; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumo_servicio
    ADD CONSTRAINT fk_estadia_consumo FOREIGN KEY (id_estadia) REFERENCES public.estadia(id_estadia) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5152 (class 2606 OID 31365)
-- Name: factura fk_estadia_factura; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT fk_estadia_factura FOREIGN KEY (id_estadia) REFERENCES public.estadia(id_estadia) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5158 (class 2606 OID 31370)
-- Name: detalle_factura fk_factura_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT fk_factura_detalle FOREIGN KEY (id_factura) REFERENCES public.factura(id_factura) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5146 (class 2606 OID 31375)
-- Name: consumo_servicio fk_habitacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumo_servicio
    ADD CONSTRAINT fk_habitacion FOREIGN KEY (id_habitacion) REFERENCES public.habitacion(id_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5148 (class 2606 OID 31380)
-- Name: detalle_reservacion fk_habitacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_reservacion
    ADD CONSTRAINT fk_habitacion FOREIGN KEY (id_habitacion) REFERENCES public.habitacion(id_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5159 (class 2606 OID 31385)
-- Name: detalle_factura fk_habitacion_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT fk_habitacion_detalle FOREIGN KEY (id_habitacion) REFERENCES public.habitacion(id_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5154 (class 2606 OID 31390)
-- Name: habitacion fk_hotel; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitacion
    ADD CONSTRAINT fk_hotel FOREIGN KEY (id_hotel) REFERENCES public.hotel(id_hotel) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5163 (class 2606 OID 31395)
-- Name: resenia fk_huesped; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.resenia
    ADD CONSTRAINT fk_huesped FOREIGN KEY (id_huesped) REFERENCES public.huesped(id_huesped) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5165 (class 2606 OID 31400)
-- Name: reservacion fk_huesped; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.reservacion
    ADD CONSTRAINT fk_huesped FOREIGN KEY (id_huesped) REFERENCES public.huesped(id_huesped) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5153 (class 2606 OID 31405)
-- Name: factura fk_huesped_factura; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.factura
    ADD CONSTRAINT fk_huesped_factura FOREIGN KEY (id_huesped) REFERENCES public.huesped(id_huesped) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5149 (class 2606 OID 31410)
-- Name: detalle_reservacion fk_reservacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_reservacion
    ADD CONSTRAINT fk_reservacion FOREIGN KEY (id_reservacion) REFERENCES public.reservacion(id_reservacion) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5150 (class 2606 OID 31415)
-- Name: estadia fk_reservacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.estadia
    ADD CONSTRAINT fk_reservacion FOREIGN KEY (id_reservacion) REFERENCES public.reservacion(id_reservacion) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5147 (class 2606 OID 31420)
-- Name: consumo_servicio fk_servicio; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.consumo_servicio
    ADD CONSTRAINT fk_servicio FOREIGN KEY (id_servicio) REFERENCES public.servicio(id_servicio) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5160 (class 2606 OID 31425)
-- Name: detalle_factura fk_servicio_detalle; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.detalle_factura
    ADD CONSTRAINT fk_servicio_detalle FOREIGN KEY (id_servicio) REFERENCES public.servicio(id_servicio) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5143 (class 2606 OID 31430)
-- Name: comodidad_tipo_habitacion fk_tipo_comodidad; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comodidad_tipo_habitacion
    ADD CONSTRAINT fk_tipo_comodidad FOREIGN KEY (id_tipo_comodidad) REFERENCES public.tipo_comodidad(id_tipo_comodidad);


--
-- TOC entry 5161 (class 2606 OID 31435)
-- Name: empleado fk_tipo_empleado; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.empleado
    ADD CONSTRAINT fk_tipo_empleado FOREIGN KEY (id_tipo_empleado) REFERENCES public.tipo_empleado(id_tipo_empleado) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 5144 (class 2606 OID 31440)
-- Name: comodidad_tipo_habitacion fk_tipo_habitacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.comodidad_tipo_habitacion
    ADD CONSTRAINT fk_tipo_habitacion FOREIGN KEY (id_tipo_habitacion) REFERENCES public.tipo_habitacion(id_tipo_habitacion);


--
-- TOC entry 5155 (class 2606 OID 31445)
-- Name: habitacion fk_tipo_habitacion; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.habitacion
    ADD CONSTRAINT fk_tipo_habitacion FOREIGN KEY (id_tipo_habitacion) REFERENCES public.tipo_habitacion(id_tipo_habitacion) ON UPDATE CASCADE ON DELETE RESTRICT;


-- Completed on 2026-06-20 23:23:41

--
-- PostgreSQL database dump complete
--

\unrestrict DrF9YcJq10JHFoatMdUQRUb7WLoRMhuWfhjhO526eocQNwsWGNZbcGGJPlO8ecc

