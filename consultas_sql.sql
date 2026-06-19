--------------- Tasa de ocupación mensual por tipo de habitación---------------
create or replace view v_tasa_ocupacion_mensual as
---- Desglosamos cada dia de la estadia/reserva
with dias_ocupados as (
    select 
    dr.id_habitacion,
    h.id_tipo_habitacion,
    th.tipo_habitacion,
    generate_series(
    e.checkin::date, 
    (coalesce(e.checkout, dr.fecha_salida::timestamp) - interval '1 day')::date, 
    '1 day'::interval
    )::date AS fecha_ocupada
    FROM detalle_reservacion dr
    JOIN reservacion r ON dr.id_reservacion = r.id_reservacion
    JOIN estadia e ON r.id_reservacion = e.id_reservacion 
    JOIN habitacion h ON dr.id_habitacion = h.id_habitacion
    JOIN tipo_habitacion th ON h.id_tipo_habitacion = th.id_tipo_habitacion
    WHERE r.estado = 'CONFIRMADA' 
),
--Agrupamos los días ocupados por mes y tipo de habitación
ocupacion_agrupada as (
    select
        id_tipo_habitacion,
        tipo_habitacion,
        TO_CHAR(fecha_ocupada, 'YYYY-MM') as mes_anio,
        DATE_TRUNC('month', fecha_ocupada)::date as fecha_base_mes,
        COUNT(id_habitacion) as total_dias_ocupados
    from dias_ocupados
    group by
        id_tipo_habitacion, 
        tipo_habitacion, 
        TO_CHAR(fecha_ocupada, 'YYYY-MM'), 
        DATE_TRUNC('month', fecha_ocupada)
),
--  Obtenemos el total de habitaciones existentes por cada tipo
capacidad_habitaciones as (
    select   
    id_tipo_habitacion,
    count(id_habitacion) as cantidad_habitaciones
    from habitacion
    group by id_tipo_habitacion
)
-- Calculamos el porcentaje de ocupación final
select 
    oa.mes_anio as mes,
    oa.tipo_habitacion,
    oa.total_dias_ocupados,
    (ch.cantidad_habitaciones * extract(day from (oa.fecha_base_mes + interval '1 month' - interval '1 day')))::int as total_dias_disponibles,
    
    to_char(
    (oa.total_dias_ocupados::numeric / 
    (ch.cantidad_habitaciones * extract(day 
    from (oa.fecha_base_mes + 
    interval '1 month' - interval '1 day')))::numeric) * 100, 
    'FM990.00"%"'
    ) as porcentaje_ocupacion
from ocupacion_agrupada oa
join capacidad_habitaciones ch on oa.id_tipo_habitacion = ch.id_tipo_habitacion
order by oa.mes_anio desc, porcentaje_ocupacion desc;

select * from v_tasa_ocupacion_mensual;

-----------------Visualizar huespuedes---------------
create or replace view v_huespedes_por_hotel as
select  
    h.id_huesped, 
    h.nombre huesped, 
    h.correo,
    h.documento, 
    h.tipo_documento, 
    hot.nombre nombre_hotel,
    COUNT(distinct f.id_factura) veces_hospedado
FROM public.huesped h
inner join public.factura f on h.id_huesped = f.id_huesped
inner join public.estadia e on f.id_estadia = e.id_estadia
inner join public.detalle_reservacion dr on e.id_reservacion = dr.id_reservacion
inner join public.habitacion hab on dr.id_habitacion = hab.id_habitacion
inner join public.hotel hot on hab.id_hotel = hot.id_hotel
group by
    h.id_huesped,
    h.nombre,
    h.correo,
    h.documento,
    h.tipo_documento,
    hot.nombre;

select*from v_huespedes_por_hotel 
order by nombre_hotel desc,veces_hospedado desc;

-----------------vista general de hotel---------------
create or replace view v_datos_generales_hoteles as
-- calcular la ganancia total por año para cada hotel
with ganancia_por_anio as (
    select 
        hab.id_hotel,
        extract(year from f.fecha) as anio,
        sum(f.total_a_pagar) as total_del_anio
    from factura f
    inner join estadia e on f.id_estadia = e.id_estadia
    inner join detalle_reservacion dr on e.id_reservacion = dr.id_reservacion
    inner join habitacion hab on dr.id_habitacion = hab.id_habitacion
    group by hab.id_hotel, extract(year from f.fecha)
),
-- obtener el promedio de las ganancias anuales de cada hotel
promedio_anual as (
    select 
        id_hotel,
        round(avg(total_del_anio), 2) as ganancia_promedio_anual
    from ganancia_por_anio
    group by id_hotel
),
-- calcular la ganancia total por mes (de cada año) para cada hotel
ganancia_por_mes as (
    select 
        hab.id_hotel,
        extract(year from f.fecha) as anio,
        extract(month from f.fecha) as mes,
        sum(f.total_a_pagar) as total_del_mes
    from factura f
    inner join estadia e on f.id_estadia = e.id_estadia
    inner join detalle_reservacion dr on e.id_reservacion = dr.id_reservacion
    inner join habitacion hab on dr.id_habitacion = hab.id_habitacion
    group by hab.id_hotel, extract(year from f.fecha), extract(month from f.fecha)
),
-- obtener el promedio de las ganancias mensuales de cada hotel
promedio_mensual as (
    select 
        id_hotel,
        round(avg(total_del_mes), 2) as ganancia_promedio_mensual
    from ganancia_por_mes
    group by id_hotel
),
habitaciones_hotel as(
select 
    id_hotel,
    count(*) as habitaciones_totales,
    sum((estado = 'DISPONIBLE')::int) as habitaciones_disponibles,
    sum((estado = 'OCUPADA')::int) as habitaciones_ocupadas,
    sum((estado = 'MANTENIMIENTO')::int) as habitaciones_mantenimiento
from habitacion
group by id_hotel
)
select 
    hot.id_hotel,
    hot.nombre as nombre_hotel,
    hot.calificacion,
    hot.direccion,
    hot.niveles_edificios,
    hot.descripcion,
    h.habitaciones_totales,
    h.habitaciones_disponibles,
    h.habitaciones_ocupadas,
    h.habitaciones_mantenimiento,
    coalesce(pa.ganancia_promedio_anual, 0.00) as ganancia_promedio_anual,
    coalesce(pm.ganancia_promedio_mensual, 0.00) as ganancia_promedio_mensual
from hotel hot
left join promedio_anual pa on hot.id_hotel = pa.id_hotel
left join promedio_mensual pm on hot.id_hotel = pm.id_hotel
inner join habitaciones_hotel h on hot.id_hotel = h.id_hotel
order by calificacion desc;

select*from v_datos_generales_hoteles;

-----------------vista facturas ---------------
CREATE OR REPLACE VIEW v_factura_completa AS
SELECT 
    -- 1. Información principal de la Factura
    f.id_factura,
    f.fecha,
    f.metodo_pago,
    f.total_a_pagar,
    f.id_estadia,

    -- 2. Datos del Empleado
    e.nombre AS nombre_empleado,

    -- 3. Datos del Huésped
    h.nombre AS nombre_huesped,
    h.correo AS correo_huesped,
    h.id_huesped,

    -- 4. COLUMNA COMPUESTA: Arreglo JSON con todo el detalle desglosado
    COALESCE(
        (
            SELECT jsonb_agg(
                jsonb_build_object(
                    'id_detalle_factura', df.id_detalle_factura,
                    'concepto', df.concepto,
                    'precio_unitario', df.precio_unitario,
                    'cantidad', df.cantidad,
                    'subtotal', df.subtotal,
                    'monto_descuento', df.monto_descuento,
                    'monto_aumento', df.monto_aumento,
                    'precio_total', df.precio_total,
                    
                    'servicio', CASE 
                        WHEN df.id_servicio IS NOT NULL THEN 
                            jsonb_build_object('id_servicio', s.id_servicio, 'tipo_servicio', s.tipo_servicio)
                        ELSE NULL 
                    END,
                    
                    'habitacion', CASE 
                        WHEN df.id_habitacion IS NOT NULL THEN 
                            jsonb_build_object('id_habitacion', hab.id_habitacion, 'numero', hab.numero_habitacion, 'nivel', hab.nivel)
                        ELSE NULL 
                    END,
                    
                    'descuento', CASE 
                        WHEN df.id_descuento IS NOT NULL THEN 
                            jsonb_build_object('id_descuento', d.id_descuento, 'porcentaje', d.porcentaje_descuento)
                        ELSE NULL 
                    END,
                    
                    'aumento_costo', CASE 
                        WHEN df.id_aumento_costo IS NOT NULL THEN 
                            jsonb_build_object('id_aumento_costo', ac.id_aumento_costo, 'temporada', ac.nombre_temporada, 'porcentaje', ac.porcentaje_aumento)
                        ELSE NULL 
                    END
                )
            )
            FROM detalle_factura df
            LEFT JOIN servicio s ON df.id_servicio = s.id_servicio
            LEFT JOIN habitacion hab ON df.id_habitacion = hab.id_habitacion
            LEFT JOIN descuento d ON df.id_descuento = d.id_descuento
            LEFT JOIN aumento_costos ac ON df.id_aumento_costo = ac.id_aumento_costo
            WHERE df.id_factura = f.id_factura
        ),
        '[]'::jsonb 
    ) AS detalle_factura
    FROM factura f
inner JOIN estadia es ON es.id_estadia = f.id_estadia
inner JOIN reservacion r oN r.id_reservacion = es.id_reservacion
inner JOIN empleado e ON e.id_empleado = r.id_empleado
JOIN huesped h ON h.id_huesped = r.id_huesped;
   
select * from v_factura_completa; 

------------------ Vista que obtiene el total de ingresos por mes correspondientes al año en curso
CREATE OR REPLACE VIEW v_ingresos_mes AS (
    SELECT
        EXTRACT(YEAR FROM f.fecha) AS anio,
        EXTRACT(MONTH FROM f.fecha) AS num_mes,
        TO_CHAR(f.fecha, 'Month') AS mes,
        SUM(f.total_a_pagar) AS ingresos
    FROM factura f
    GROUP BY 
        EXTRACT(YEAR FROM f.fecha), 
        EXTRACT(MONTH FROM f.fecha), 
        TO_CHAR(f.fecha, 'Month')
    ORDER BY 
        anio DESC, 
        num_mes ASC
);

select *from v_ingresos_mes;
 	
----------- Vista que resume la información general de los hoteles (calificación, capacidad y ganancias)
CREATE OR REPLACE VIEW v_info_general_hoteles AS (
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

SELECT * FROM v_info_general_hoteles;


---------------Habitaciones disponibles en un rango de fechas ------------------
create OR REPLACE view v_habitaciones_disponibles AS
select
    h.id_habitacion,
    ho.nombre AS hotel,
    ho.direccion,
    h.nivel,
    h.numero_habitacion,
    th.tipo_habitacion,
    h.precio,
    h.estado,
    h.capacidad_maxima
from habitacion h
inner join hotel ho 
    on h.id_hotel = ho.id_hotel
inner join tipo_habitacion th 
    on h.id_tipo_habitacion = th.id_tipo_habitacion
where h.estado = 'DISPONIBLE';


select * from v_habitaciones_disponibles vh
where not exists (
    select 1
    from detalle_reservacion dr
    where dr.id_habitacion = vh.id_habitacion
      and dr.id_reservacion in (
          select r.id_reservacion
          from reservacion r
          where r.estado in ('PENDIENTE', 'CONFIRMADA')
            and dr.fecha_entrada < '2020-05-06'
            and dr.fecha_salida > '2026-05-01'
      )
);

---------------VISTA de Huespedes con mayor gasto historico ------------------
create OR REPLACE view v_gasto_historica AS
select
    h.id_huesped,
    h.nombre AS huesped,
    h.correo,
    h.documento,
    h.tipo_documento,
    SUM(f.total_a_pagar) as gasto_total,
    count(f.id_factura) as cantidad_facturas
from huesped h
inner join factura f 
    on h.id_huesped = f.id_huesped
group by
h.id_huesped,
h.nombre,
h.correo,
h.documento,
h.tipo_documento
order by gasto_total desc;

select * from v_gasto_historica;


---------------vista Servicios mas consumidos por tipo habitacion ------------------
create OR REPLACE view v_servicios_mas_consumidos_tipo_habitacion AS
select 
    th.id_tipo_habitacion,
    th.tipo_habitacion,
    s.id_servicio,
    s.tipo_servicio,
    SUM(df_serv.cantidad) AS total_consumos
from detalle_factura df_serv
inner join servicio s 
on df_serv.id_servicio = s.id_servicio
inner join  factura f 
on df_serv.id_factura = f.id_factura
inner join  estadia e 
on f.id_estadia = e.id_estadia
inner join  detalle_reservacion dr
on e.id_reservacion = dr.id_reservacion
inner join  habitacion h
on dr.id_habitacion = h.id_habitacion
inner join tipo_habitacion th 
on h.id_tipo_habitacion = th.id_tipo_habitacion
group by
    th.id_tipo_habitacion,
    th.tipo_habitacion,
    s.id_servicio,
    s.tipo_servicio
order by
    th.tipo_habitacion,
    total_consumos DESC;

select * from v_servicios_mas_consumidos_tipo_habitacion;

---------------------------- VISTA dias_restantes_reservacion -----------------
create OR REPLACE view v_dias_restantes_reservacion as
select
    r.id_reservacion, h.nombre as nombre_huesped, h.documento as documento_huesped,
    h.telefono as telefono_huesped, e.nombre as nombre_empleado, r.cant_huespedes_totales,
    r.estado as estado_reservacion, MIN(dr.fecha_entrada) as fecha_entrada_proxima,
    MIN(dr.fecha_salida) as fecha_salida_proxima,
    (MIN(dr.fecha_entrada) - CURRENT_DATE) AS dias_para_iniciar
from reservacion r
inner join huesped h on r.id_huesped = h.id_huesped
inner join empleado e on r.id_empleado = e.id_empleado
inner join detalle_reservacion dr on r.id_reservacion = dr.id_reservacion
where r.estado in ('PENDIENTE', 'CONFIRMADA') 
  and dr.fecha_entrada >= CURRENT_DATE
group by 
    r.id_reservacion, h.nombre, h.documento, h.telefono,
    e.nombre, r.cant_huespedes_totales, r.estado
order by
    dias_para_iniciar asc;

select * from v_dias_restantes_reservacion;

------------------ VISTA DE detalle_habitacion_comodidas----------------------------
create OR REPLACE view v_detalle_habitaciones_y_comodidades as
select 
    h.id_habitacion, h.numero_habitacion, h.precio,
    h.estado, h.capacidad_maxima, th.tipo_habitacion,
    (select count(*) 
     from habitacion h2 
     where h2.id_tipo_habitacion = th.id_tipo_habitacion
    ) as total_habitaciones_este_tipo,
    string_agg( distinct tc.tipo_comodidad, ', ') as comodidades,
    count(distinct tc.id_tipo_comodidad) as total_comodidades
from habitacion h
inner join tipo_habitacion th 
    on h.id_tipo_habitacion = th.id_tipo_habitacion
left join comodidad_tipo_habitacion cth 
    on th.id_tipo_habitacion = cth.id_tipo_habitacion
left join tipo_comodidad tc 
    on cth.id_tipo_comodidad = tc.id_tipo_comodidad
group by 
    h.id_habitacion, h.numero_habitacion, h.nivel, h.precio,
    h.estado, h.capacidad_maxima, th.id_tipo_habitacion, th.tipo_habitacion
order by 
    th.tipo_habitacion, h.numero_habitacion;

select * from v_detalle_habitaciones_y_comodidades;

---------------------------Vista total habitaciones por tipo---------------------
create OR REPLACE view v_total_habitaciones_por_tipo as
select 
    th.tipo_habitacion,
    count(h.id_habitacion) as total_habitaciones
from tipo_habitacion th
left join habitacion h on th.id_tipo_habitacion = h.id_tipo_habitacion
group by 
    th.id_tipo_habitacion, 
    th.tipo_habitacion
order by 
    total_habitaciones desc;

select * from v_total_habitaciones_por_tipo;

--- Visualizar el consumo de una estadia de los huespedes ---
create OR REPLACE view v_consumo_estadia as
select
    e.id_estadia,
    h.nombre,
    h.documento,
    json_build_object(
        'habitaciones', (
            -- Habitaciones de la reservación
            select json_agg(
                json_build_object(
                    'numero_habitacion', h2.numero_habitacion,
                    
                    -- Consumos específicos de ESTA habitación
                    'consumos', (
                        select coalesce(json_agg(
                            json_build_object(
                                'servicio', s.tipo_servicio,
                                'precio', s.precio
                            )
                        ), '[]'::json) -- Si no hay consumos, devuelve un arreglo vacío []
                        from consumo_servicio cs
                        inner join servicio s on cs.id_servicio = s.id_servicio
                        where cs.id_estadia = e.id_estadia 
                          and cs.id_habitacion = h2.id_habitacion
                    )
                )
            )
            from detalle_reservacion dr
            inner join habitacion h2 on dr.id_habitacion = h2.id_habitacion
            where dr.id_reservacion = r.id_reservacion
        ),
        
        -- Total general de la factura
        'gasto_total', f.total_a_pagar
        
    ) as reporte_json
from estadia e
inner join reservacion r on e.id_reservacion = r.id_reservacion
inner join huesped h on r.id_huesped = h.id_huesped
left join factura f on e.id_estadia = f.id_estadia;

select * from v_consumo_estadia;

------------------ Visualizar los empleados y sus roles(Tipo_empleado) --------------------------
create view vista_empleados as
select
e.nombre as Empleado, 
e.dui as Documento_de_identidad, 
e.telefono as Teléfono,
e.correo as Email, 
te.tipo_empleado as Rol_de_trabajo, 
e.salario as Salario
from empleado e
inner join tipo_empleado te on e.id_tipo_empleado = te.id_tipo_empleado;

select * from vista_empleados;
