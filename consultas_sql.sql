
---------------Habitaciones disponibles en un rango de fechas ------------------
CREATE OR REPLACE view vista_habitaciones_disponibles AS
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


select * from vista_habitaciones_disponibles vh
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

---------------Huespedes con mayor gasto historico ------------------

select * from huesped
select * from factura 

CREATE OR REPLACE view vista_gasto_historica AS
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

select * from vista_gasto_historica;

---------------Servicios mas consumidos por tipo habitacion ------------------
select * from tipo_habitacion 
select  * from servicio
select * from consumo_servicio
select * from detalle_factura

CREATE OR REPLACE view servicios_mas_consumidos_tipo_habitacion AS
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

select * from servicios_mas_consumidos_tipo_habitacion;

-- Tasa de ocupación mensual por tipo de habitación
drop view if exists vista_tasa_ocupacion_mensual;

create or replace view vista_tasa_ocupacion_mensual as
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

select * from vista_tasa_ocupacion_mensual;

--Visualizar huespuedes
drop view if exists vistas_huespuedes;

create or replace view vistas_huespuedes as
select
h.id_huesped, h.nombre as huesped, h.correo,
h.documento, h.tipo_documento, hot.nombre as nombre_hotel,
COUNT(distinct f.id_factura) as veces_hospedado
from huesped h
	inner join factura f on h.id_huesped = f.id_huesped
	inner join estadia e on f.id_estadia = e.id_estadia
	inner join detalle_reservacion dr on e.id_reservacion = dr.id_reservacion
	inner join habitacion hab on dr.id_habitacion = hab.id_habitacion
	inner join hotel hot on hab.id_hotel = hot.id_hotel
group by
h.id_huesped,
h.nombre,
h.correo,
h.documento,
h.tipo_documento,
hot.nombre
order by nombre_hotel desc, veces_hospedado desc;

--VISTA CALIFICACION Y GANANCIA DE HOTEL
drop view if exists vista_calificacion_y_ganancias_prom;

create or replace view vista_calificacion_y_ganancias_prom as
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
-- calcular la calificación promedio general de cada hotel
promedio_calificacion as (
    select 
        hab.id_hotel,
        round(avg(r.calificacion), 2) as calificacion_promedio_hotel
    from resenia r
    inner join estadia est on r.id_estadia = est.id_estadia
    inner join detalle_reservacion det on est.id_reservacion = det.id_reservacion
    inner join habitacion hab on det.id_habitacion = hab.id_habitacion
    group by hab.id_hotel
)
-- consolidar los promedios métricos finales por cada hotel existente
select 
    hot.id_hotel,
    hot.nombre as nombre_hotel,
    coalesce(pc.calificacion_promedio_hotel, 0.00) as calificacion_promedio_hotel,
    coalesce(pa.ganancia_promedio_anual, 0.00) as ganancia_promedio_anual,
    coalesce(pm.ganancia_promedio_mensual, 0.00) as ganancia_promedio_mensual
from hotel hot
left join promedio_anual pa on hot.id_hotel = pa.id_hotel
left join promedio_mensual pm on hot.id_hotel = pm.id_hotel
left join promedio_calificacion pc on hot.id_hotel = pc.id_hotel;

select*from vista_calificacion_y_ganancias_prom;