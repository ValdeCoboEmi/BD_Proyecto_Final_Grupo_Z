-- Tasa de ocupación mensual por tipo de habitación
CREATE OR REPLACE VIEW vista_tasa_ocupacion_mensual AS
WITH dias_ocupados AS (
    -- 1. Desglosamos cada reserva en días individuales (sin contar el día de salida/checkout)
    SELECT 
        dr.id_habitacion,
        h.id_tipo_habitacion,
        th.tipo_habitacion,
        generate_series(
            dr.fecha_entrada::timestamp, 
            (dr.fecha_salida - interval '1 day')::timestamp, 
            '1 day'::interval
        )::date AS fecha_ocupada
    FROM detalle_reservacion dr
    JOIN reservacion r ON dr.id_reservacion = r.id_reservacion
    JOIN habitacion h ON dr.id_habitacion = h.id_habitacion
    JOIN tipo_habitacion th ON h.id_tipo_habitacion = th.id_tipo_habitacion
    -- Solo tomamos en cuenta las reservas confirmadas
    WHERE r.estado = 'CONFIRMADA' 
),
ocupacion_agrupada AS (
    -- 2. Agrupamos los días ocupados por mes y tipo de habitación
    SELECT 
        id_tipo_habitacion,
        tipo_habitacion,
        TO_CHAR(fecha_ocupada, 'YYYY-MM') AS mes_anio,
        DATE_TRUNC('month', fecha_ocupada)::date AS fecha_base_mes,
        COUNT(id_habitacion) AS total_dias_ocupados
    FROM dias_ocupados
    GROUP BY 
        id_tipo_habitacion, 
        tipo_habitacion, 
        TO_CHAR(fecha_ocupada, 'YYYY-MM'), 
        DATE_TRUNC('month', fecha_ocupada)
),
capacidad_habitaciones AS (
    -- 3. Obtenemos el total de habitaciones existentes por cada tipo
    SELECT 
        id_tipo_habitacion,
        COUNT(id_habitacion) AS cantidad_habitaciones
    FROM habitacion
    GROUP BY id_tipo_habitacion
)
-- 4. Calculamos el porcentaje de ocupación final
SELECT 
    oa.mes_anio AS mes,
    oa.tipo_habitacion,
    oa.total_dias_ocupados,
    -- Calculamos los días totales del mes (28, 29, 30 o 31) y lo multiplicamos por el número de habitaciones de ese tipo
    (ch.cantidad_habitaciones * EXTRACT(day FROM (oa.fecha_base_mes + interval '1 month' - interval '1 day')))::int AS total_dias_disponibles,
    
    -- Fórmula: (Días ocupados / Días disponibles) * 100
    ROUND(
        (oa.total_dias_ocupados::numeric / 
        (ch.cantidad_habitaciones * EXTRACT(day FROM (oa.fecha_base_mes + interval '1 month' - interval '1 day')))::numeric) * 100, 
    2) AS porcentaje_ocupacion
FROM ocupacion_agrupada oa
JOIN capacidad_habitaciones ch ON oa.id_tipo_habitacion = ch.id_tipo_habitacion
ORDER BY oa.mes_anio DESC, porcentaje_ocupacion DESC;

SELECT * FROM vista_tasa_ocupacion_mensual;