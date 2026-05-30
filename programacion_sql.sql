-- Al intentar insertar una reservación, verificar que la habitación no esté 
-- ocupada en ese período; si hay conflicto, lanzar un error
--Funcion
create or replace function validar_disponibilidad_habitacion()
returns trigger as $$
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
$$ language plpgsql; 

-- trigger 
create trigger trg_verificar_reserva
before insert or update on public.detalle_reservacion
for each row
execute function validar_disponibilidad_habitacion();

--------Trigger para actualizar calificaciones------------
--FUNCION
CREATE OR REPLACE FUNCTION actualizar_calificacion_hotel()
RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql;

-- Nos aseguramos de eliminarlo si ya existía para evitar duplicados
DROP TRIGGER IF EXISTS trg_actualizar_calificacion ON resenia;

CREATE TRIGGER trg_actualizar_calificacion
AFTER INSERT OR UPDATE ON resenia
FOR EACH ROW
EXECUTE FUNCTION actualizar_calificacion_hotel();