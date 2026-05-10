-- Al intentar insertar una reservación, verificar que la habitación no esté 
-- ocupada en ese período; si hay conflicto, lanzar un error
--Funcion
CREATE OR REPLACE FUNCTION validar_disponibilidad_habitacion()
RETURNS TRIGGER AS $$
BEGIN
    -- Buscamos si ya existe una reserva que choque con las fechas nuevas
    IF EXISTS (
        SELECT 1 
        FROM detalle_reservacion 
        WHERE id_habitacion = NEW.id_habitacion 
          -- Esta es la lógica matemática para detectar si dos rangos de fecha se cruzan
          AND fecha_entrada < NEW.fecha_salida 
          AND fecha_salida > NEW.fecha_entrada
          -- Esto evita que marque error si estamos actualizando (UPDATE) la misma reserva
          AND id_detalle_reservacion IS DISTINCT FROM NEW.id_detalle_reservacion
    ) THEN
        -- Si encuentra un choque, aborta la operación y lanza este mensaje
        RAISE EXCEPTION 'La habitación % ya está reservada en esas fechas.', NEW.id_habitacion;
    END IF;

    -- Si no hay choques, deja pasar los datos (retorna NEW)
    RETURN NEW;
END;
$$ LANGUAGE plpgsql; 

--Trigger
CREATE TRIGGER trg_verificar_reserva
BEFORE INSERT OR UPDATE ON detalle_reservacion
FOR EACH ROW
EXECUTE FUNCTION validar_disponibilidad_habitacion();