--------------- Tasa de ocupación mensual por tipo de habitación---------------
select * from v_tasa_ocupacion_mensual;

-----------------Visualizar huespuedes---------------
select*from v_huespedes_por_hotel 
order by nombre_hotel desc,veces_hospedado desc;

-----------------vista general de hotel---------------
select*from v_datos_generales_hoteles;

---------------------------vista facturas ---------------
select * from v_factura_completa; 

------------------ Vista que obtiene el total de ingresos por mes correspondientes a los años
select * from v_ingresos_mes;

-- Vista que resume la información general de los hoteles (calificación, capacidad y ganancias)
SELECT * FROM v_info_general_hoteles;

---------------Habitaciones disponibles en un rango de fechas ------------------
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
select * from v_gasto_historica;

---------------vista Servicios mas consumidos por tipo habitacion ------------------
select * from v_servicios_mas_consumidos_tipo_habitacion;

---------------------------- VISTA dias_restantes_reservacion -----------------
select * from v_dias_restantes_reservacion;

------------------ VISTA DE detalle_habitacion_comodidas----------------------------
select * from v_detalle_habitaciones_y_comodidades;

---------------------------Vista total habitaciones por tipo---------------------
select * from v_total_habitaciones_por_tipo;

--- Visualizar el consumo de una estadia de los huespedes ---
select * from v_consumo_estadia;

------------------ Visualizar los empleados y sus roles(Tipo_empleado) ---------------
select * from v_tipo_de_empleados;