--IMPORTANTE
--Leer con antelacion el proceso_insercciones.md
-- Primeras insercciones, tablas padres

COPY descuento (porcentaje_descuento, cant_dia_hospedado) 
FROM '/csv_data/descuento_.csv' 
WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY aumento_costos (porcentaje_aumento, fecha_inicio, fecha_fin, nombre_temporada, activado) 
FROM '/csv_data/aumento_costos_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY hotel (nombre, direccion, niveles_edificios, calificacion, descripcion) 
FROM '/csv_data/hotel_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

--HUespued nacional
COPY huesped (nombre, correo, telefono, documento, tipo_documento) 
FROM '/csv_data/huesped_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

--HUespued de residencia 
COPY huesped (nombre, correo, telefono, documento, tipo_documento) 
FROM '/csv_data/huesped_constancia_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

--Huesped internacional
COPY huesped (nombre, correo, telefono, documento, tipo_documento) 
FROM '/csv_data/huesped_pasaporte_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');


COPY servicio (tipo_servicio, precio) 
FROM '/csv_data/servicio_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY tipo_comodidad (tipo_comodidad) 
FROM '/csv_data/tipo_comodidad_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY tipo_empleado (tipo_empleado) 
FROM '/csv_data/tipo_empleado_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY tipo_habitacion (tipo_habitacion) 
FROM '/csv_data/tipo_habitacion_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Segunda insercciones, tablas hijas
COPY comodidad_tipo_habitacion (id_tipo_habitacion, id_tipo_comodidad, detalle) 
FROM '/csv_data/comodidad_tipo_habitacion_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY habitacion (id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima, descripcion) 
FROM '/csv_data/habitacion_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY empleado (id_tipo_empleado, nombre, correo, telefono, dui, salario) 
FROM '/csv_data/empleado_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

-- Dependientes de mas tablas
COPY reservacion (id_empleado, id_huesped, cant_huespedes_totales, estado) 
FROM '/csv_data/reservacion_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida) 
FROM '/csv_data/detalle_reservacion_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY estadia (id_reservacion, checkin, checkout) 
FROM '/csv_data/estadia_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY resenia (id_estadia, id_huesped, calificacion, comentario) 
FROM '/csv_data/resenia_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY consumo_servicio (id_servicio, id_habitacion, id_estadia, hora_consumo) 
FROM '/csv_data/consumo_servicio_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY factura (id_empleado, id_huesped, id_estadia, fecha, metodo_pago, total_a_pagar) 
FROM '/csv_data/factura_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');

COPY detalle_factura (id_factura, id_servicio, id_habitacion, id_descuento, id_aumento_costo, concepto, precio_unitario, cantidad, subtotal, monto_descuento, monto_aumento, precio_total) 
FROM '/csv_data/detalle_factura_.csv' WITH (FORMAT csv, HEADER true, DELIMITER ',');