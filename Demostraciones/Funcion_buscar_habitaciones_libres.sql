------Funcion para buscar habitaciones libres por rango de fecha--------
create or replace function buscar_habitaciones_disponibles(
    p_fecha_entrada date, 
    p_fecha_salida date, 
    p_id_tipo_habitacion bigint
)
returns table(
    id_habitacion_libre bigint,
    nombre_hotel_pertenece varchar(100),
    numero_habitacion_libre int,
    tipo_habitacion_libre varchar(100),
    precio_habitacion numeric(10,2)
) as $$
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
$$ language plpgsql;

------Muestra de datos de funcion con los distintos tipos de habitacion--------

---Tipo Habitacion 1---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 1);

---Tipo Habitacion 2---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 2);

---Tipo Habitacion 3---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 3);

---Tipo Habitacion 4---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 4);

---Tipo Habitacion 5---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 5);

---Tipo Habitacion 6---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 6);

---Tipo Habitacion 7---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 7);

---Tipo Habitacion 8---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 8);

---Tipo Habitacion 9---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 9);

---Tipo Habitacion 10---
select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 10);

---Con un id inexistente o datos extra innecesario---

select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 11);

select * from buscar_habitaciones_disponibles('2026-02-05', '2026-10-06', 1, 2);








