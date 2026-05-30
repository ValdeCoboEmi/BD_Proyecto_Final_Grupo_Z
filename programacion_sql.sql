-- Al intentar insertar una reservación, verificar que la habitación no esté 
-- ocupada en ese período; si hay conflicto, lanzar un error
--Funcion
create or replace function validar_disponibilidad_habitacion()
returns trigger as $$
BEGIN
    -- Buscamos si ya existe una reserva que choque con las fechas nuevas
    if exists    (
        select 1 
        from detalle_reservacion 
        where id_habitacion = new.id_habitacion 
          -- Esta es la lógica matemática para detectar si dos rangos de fecha se cruzan
          and fecha_entrada < new.fecha_salida 
          and fecha_salida > new.fecha_entrada
          -- Esto evita que marque error si estamos actualizando la misma reserva
          and id_detalle_reservacion is distinct from new.id_detalle_reservacion
    ) then
        -- Si encuentra un choque, aborta la operación
        raise exception 'La habitación % ya está reservada en esas fechas.', NEW.id_habitacion;
    end if;

    -- Si no hay choques, deja pasar los datos 
    return new;
end;
$$ language plpgsql; 

--Trigger
create trigger trg_verificar_reserva
before insert or update on detalle_reservacion
for each row
execute function validar_disponibilidad_habitacion();