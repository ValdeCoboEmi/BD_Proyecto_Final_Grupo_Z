
-- se inserta una habitacion con nivel mayor al del hotel de la misma
insert into habitacion(id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima)
values (1, 5, 111, 3, 39.99, 'DISPONIBLE', 1);

-- TRIGGER PARA VALIDAR NIVEL DE HABITACION
-- creacion de la funcion disparadora
create or replace function validar_nivel_habitacion()
returns trigger as $$
declare nivel_hotel int;
begin 
	-- se guarda el nivel del hotel de la habitacion en una variable
	select niveles_edificios into nivel_hotel
	from hotel where id_hotel = NEW.id_hotel;
	-- se valida si el nivel ingresado es mayor al del hotel
	if NEW.nivel > nivel_hotel then
		raise exception 'Operación cancelada: el nivel ingresado (%) es mayor al del hotel (%).', NEW.nivel, nivel_hotel;
	end if;
	
	return new;
end;
$$ language plpgsql;

-- creacion del trigger en la tabla de habitacion cuando se inserte o modifique
create trigger tg_check_nivel_habitacion
before insert or update on habitacion
for each row 
execute function validar_nivel_habitacion();

-- se prueba un insert mandando un nivel superior al del hotel
insert into habitacion(id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima)
values (1, 5, 222, 2, 49.99, 'DISPONIBLE', 2);


-- insert corregido
insert into habitacion(id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima)
values (1, 4, 333, 3, 56.99, 'OCUPADA', 3);



