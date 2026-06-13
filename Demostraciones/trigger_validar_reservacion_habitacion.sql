-----FUNCIONANMIENTO DEL TRIGGER validar_disponibilidad_habitacion-----

--insert nuevo de detalle reservacion donde se tomara de referencia
--para que salte el error
INSERT INTO public.detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida)
SELECT 
    (SELECT id_reservacion FROM public.reservacion WHERE estado IN ('CONFIRMADA', 'COMPLETADA') LIMIT 1),
    (SELECT id_habitacion FROM public.habitacion LIMIT 1),
    2, 
    '2026-12-10', 
    '2026-12-15';

--EXITO
INSERT INTO public.detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida)
SELECT 
    -- Tomamos OTRA reservación distinta para este huésped
    (SELECT id_reservacion FROM public.reservacion WHERE estado IN ('CONFIRMADA', 'COMPLETADA') ORDER BY id_reservacion DESC LIMIT 1),
    -- Forzamos a que sea la MISMA habitación de la reserva base
    (SELECT id_habitacion FROM public.habitacion LIMIT 1), 
    2, 
    '2026-12-16', -- Fecha de entrada después de la salida anterior
    '2026-12-20';

-- ERROR
INSERT INTO public.detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida)
SELECT 
    (SELECT id_reservacion FROM public.reservacion WHERE estado IN ('CONFIRMADA', 'COMPLETADA') ORDER BY id_reservacion ASC LIMIT 1),
    -- Forzamos la MISMA habitación
    (SELECT id_habitacion FROM public.habitacion LIMIT 1),
    2, 
    '2026-12-12', -- Choca con la reserva base que está del 10 al 15
    '2026-12-18';