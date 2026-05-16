/* ----- TABLAS FLOTANTES -----*/

create table descuento(
id_descuento bigint generated always as identity not null,
porcentaje_descuento numeric(5,2) not null,
cant_dia_hospedado int,

constraint pk_descuento primary key(id_descuento),
constraint ck_porcentaje check(porcentaje_descuento >= 0),
constraint ck_cant_dia check(cant_dia_hospedado > 0)
);

create table aumento_costos(
id_aumento_costo bigint generated always as identity not null,
porcentaje_aumento numeric(5,2) not null,
fecha_inicio date not null,
fecha_fin date not null,
nombre_temporada varchar(100),
activado boolean default(true),

constraint pk_aumento_costo primary key(id_aumento_costo),
constraint ck_fecha_inicio check((fecha_inicio < fecha_fin)),
constraint uq_nombre_temp unique(nombre_temporada)
);
/*------------------------------------------------------*/


/* ----- TABLAS QUE NO TIENEN DEPENDENCIAS -----*/
create table hotel(
id_hotel bigint generated always as identity not null,
nombre varchar(255) not null,
direccion varchar (255),
niveles_edificios int not null,
calificacion numeric(2,1),
descripcion text,

constraint pk_hotel primary key(id_hotel),
constraint ck_niveles check(niveles_edificios > 0),
constraint ck_calificacion check(calificacion between 1 and 5),
constraint uq_nombre unique(nombre)
);


create table huesped(
id_huesped bigint generated always as identity not null,
nombre varchar(255) not null,
correo varchar(255) not null,
telefono varchar(20) not null,
documento varchar(50) not null,
tipo_documento varchar(50) not null,

constraint pk_huesped primary key(id_huesped),
constraint uq_correo unique(correo),
constraint ck_correo check(correo like '%@%.%'),
constraint uq_documento unique(documento),
constraint ck_tipo_documento check(tipo_documento in ('DUI','PASAPORTE', 'CONSTANCIA DE RESIDENCIA'))
);

create table servicio(
id_servicio bigint generated always as identity not null,
tipo_servicio varchar(100) not null,
precio numeric(10,2) not null,

constraint pk_servicio primary key(id_servicio),
constraint uq_tipo_servicio unique(tipo_servicio),
constraint ck_precio check(precio >= 0)
);

create table tipo_comodidad(
id_tipo_comodidad bigint generated always as identity not null,
tipo_comodidad varchar(100) not null,

constraint pk_tipo_comodidad primary key(id_tipo_comodidad),
constraint uq_tipo_comodidad unique(tipo_comodidad)
);

create table tipo_empleado(
id_tipo_empleado bigint generated always as identity not null,
tipo_empleado varchar(100) not null,

constraint pk_tipo_empleado primary key(id_tipo_empleado),
constraint uq_tipo_empleado unique(tipo_empleado)
);

create table tipo_habitacion(
id_tipo_habitacion bigint generated always as identity not null,
tipo_habitacion varchar(100) not null,

constraint pk_tipo_habitacion primary key(id_tipo_habitacion),
constraint uq_tipo_habitacion unique(tipo_habitacion)
);

/*------------------------------------------------------*/

/* ----- TABLAS QUE TIENEN DEPENDENCIAS -----*/
create table comodidad_tipo_habitacion(
id_comodidad_habitacion bigint generated always as identity not null,
id_tipo_habitacion bigint not null,
id_tipo_comodidad bigint not null,
detalle text not null,

constraint pk_comodidad_tipo_habitacion primary key(id_comodidad_habitacion),
constraint fk_tipo_habitacion foreign key(id_tipo_habitacion)
references tipo_habitacion(id_tipo_habitacion),
constraint fk_tipo_comodidad foreign key(id_tipo_comodidad)
references tipo_comodidad (id_tipo_comodidad)
);

create table habitacion(
id_habitacion bigint generated always as identity not null,
id_hotel bigint not null,
nivel int not null ,
numero_habitacion int not null,
id_tipo_habitacion bigint not null,
precio numeric(10,2) not null,
estado varchar(50) not null,
capacidad_maxima int not null,
descripcion text,

constraint pk_habitacion primary key(id_habitacion),
constraint fk_hotel foreign key(id_hotel)
references hotel(id_hotel) on delete restrict on update cascade,
constraint fk_tipo_habitacion foreign key(id_tipo_habitacion)
references tipo_habitacion(id_tipo_habitacion) on delete restrict on update cascade,

constraint ck_precio check(precio >= 0),
constraint ck_estado check(estado in ('DISPONIBLE', 'OCUPADA', 'MANTENIMIENTO')),
constraint ck_capacidad_maxima check(capacidad_maxima between 1 and 15),
constraint ck_nivel check(nivel >= 0),
constraint ck_num_habitacion check(numero_habitacion >= 0),
constraint uq_hotel_nivel_numHab unique(id_hotel, nivel, numero_habitacion)
);


create table empleado(
id_empleado bigint generated always as identity not null,
id_tipo_empleado bigint not null,
nombre varchar(255) not null,
correo varchar(100) not null,
telefono varchar(20),
dui varchar(10) not null,
salario numeric(10,2) not null,

constraint pk_empleado primary key(id_empleado),
constraint fk_tipo_empleado foreign key(id_tipo_empleado) 
references tipo_empleado(id_tipo_empleado) on delete restrict on update cascade,

constraint uq_dui unique(dui),
constraint ck_dui CHECK (dui ~ '^[0-9]{8}-[0-9]{1}$'),
constraint ck_salario check(salario >= 0),
constraint uq_correo_empleado unique(correo),
constraint ck_correo check(correo like '%@%.%'),
constraint ck_telefono check (telefono ~ '^\+503[267][0-9]{7}$')
);

create table reservacion(
id_reservacion bigint generated always as identity not null,
id_empleado bigint not null,
id_huesped bigint not null,
cant_huespedes_totales int not null,
estado varchar(50) not null,

constraint pk_reservacion primary key(id_reservacion),
constraint fk_empleado foreign key(id_empleado) 
references empleado(id_empleado) on delete restrict on update cascade,
constraint fk_huesped foreign key(id_huesped)
references huesped(id_huesped) on delete restrict on update cascade,


constraint ck_cant_huepedes check(cant_huespedes_totales >= 0),
constraint ck_estado check(estado in ('PENDIENTE', 'CONFIRMADA', 'CANCELADA', 'RECHAZADA'))

);

create table detalle_reservacion(
id_detalle_reservacion bigint generated always as identity not null,
id_reservacion bigint not null,
id_habitacion bigint not null,
cant_huespedes int,
fecha_entrada date not null,
fecha_salida date not null,

constraint pk_detalle_reservacion primary key(id_detalle_reservacion),
constraint fk_reservacion foreign key(id_reservacion)
references reservacion(id_reservacion) on delete restrict on update cascade,
constraint fk_habitacion foreign key(id_habitacion)
references habitacion (id_habitacion) on delete restrict on update cascade,

constraint ck_fecha_entrada check(fecha_entrada < fecha_salida )
);

create table estadia(
id_estadia bigint generated always as identity not null,
id_reservacion bigint not null,
checkin timestamp not null default(NOW()),
checkout timestamp, 

constraint pk_estadia primary key(id_estadia),
constraint fk_reservacion foreign key(id_reservacion)
references reservacion(id_reservacion) on delete restrict on update cascade,

constraint ck_checkin check((checkout IS NULL OR checkin < checkout))
);

create table resenia(
id_resenia bigint generated always as identity not null,
id_estadia bigint not null,
id_huesped bigint not null,
calificacion numeric(2,1),
comentario text,

constraint pk_resenia primary key(id_resenia),
constraint fk_estadia foreign key(id_estadia)
references estadia(id_estadia) on delete restrict on update cascade,
constraint fk_huesped foreign key(id_huesped)
references huesped(id_huesped) on delete restrict on update cascade,

constraint ck_calificacion check(calificacion between 1 and 5)
);

create table consumo_servicio(
id_consumo_servicio bigint generated always as identity not null,
id_servicio bigint not null,
id_habitacion bigint not null,
id_estadia bigint not null,
hora_consumo timestamp not null default(NOW()),

constraint pk_consumo_servicio primary key(id_consumo_servicio),
constraint fk_servicio foreign key(id_servicio)
references servicio (id_servicio) on delete restrict on update cascade,
constraint fk_habitacion foreign key(id_habitacion)
references habitacion(id_habitacion) on delete restrict on update cascade
);

create table factura(
id_factura bigint generated always as identity not null,
id_empleado bigint not null,
id_huesped bigint not null,
id_estadia bigint not null,
fecha timestamp not null default(NOW()),
metodo_pago varchar(50) not null,
total_a_pagar numeric(10,2) not null,

constraint pk_factura primary key(id_factura),
constraint fk_empleado_factura foreign key(id_empleado)
references empleado (id_empleado) on delete restrict on update cascade,
constraint fk_huesped_factura foreign key(id_huesped)
references huesped(id_huesped) on delete restrict on update cascade,
constraint fk_estadia_factura foreign key(id_estadia)
references estadia(id_estadia) on delete restrict on update cascade,

constraint ck_metodo_pago check(metodo_pago in ('EFECTIVO', 'TRANSFERENCIA','TARJETA','BITCOIN', 'PAYPAL')),
constraint ck_total_pagar check(total_a_pagar >= 0),
constraint uq_empleado_huesped_estadia unique(id_empleado, id_huesped, id_estadia)
);

create table detalle_factura(
    id_detalle_factura bigint generated always as identity not null,
    id_factura bigint not null,
    
    -- Si es el cobro de un servicio, se llena este y los demás quedan nulos
    id_servicio bigint, 
    -- Si es el cobro de la habitación, se llena este
    id_habitacion bigint, 
    -- Se llena si a esta línea se le aplicó un descuento de tu tabla flotante
    id_descuento bigint, 
    -- Se llena si a esta línea se le aplicó tarifa de temporada (tabla flotante)
    id_aumento_costo bigint, 
    
    -- DESGLOSE DEL COBRO
    concepto varchar(255) not null, 
    precio_unitario numeric(10,2) not null,
    cantidad int not null, 
    subtotal numeric(10,2) not null, 
    
    -- VALORES DE LAS TABLAS FLOTANTES
    monto_descuento numeric(10,2) default 0.00, -- Dinero exacto restado por el descuento
    monto_aumento numeric(10,2) default 0.00, -- Dinero exacto sumado por la temporada
    
    -- TOTAL FINAL DE ESTA LÍNEA
    precio_total numeric(10,2) not null, -- (subtotal + monto_aumento) - monto_descuento

    constraint pk_detalle_factura primary key(id_detalle_factura),
    constraint fk_factura_detalle foreign key(id_factura) 
    references factura (id_factura) on delete restrict on update cascade,
    constraint fk_servicio_detalle foreign key(id_servicio) 
    references servicio (id_servicio) on delete restrict on update cascade,
    constraint fk_habitacion_detalle foreign key(id_habitacion) 
    references habitacion (id_habitacion) on delete restrict on update cascade,
    constraint fk_descuento_detalle foreign key(id_descuento) 
    references descuento (id_descuento) on delete restrict on update cascade,
    constraint fk_aumento_detalle foreign key(id_aumento_costo) 
    references aumento_costos (id_aumento_costo) on delete restrict on update cascade,

    constraint ck_cantidad check(cantidad >= 1),
    constraint ck_precio_total check(precio_total >= 0),
    
    -- Validar que la línea tenga o un servicio o una habitación (no ambos, no ninguno)
    constraint ck_origen_cobro check (
        (id_servicio IS NOT NULL AND id_habitacion IS NULL) OR 
        (id_servicio IS NULL AND id_habitacion IS NOT NULL)
    )
);
/*------------------------------------------------------*/
/*------------------------------------------------------*/
---INSERCIONES 
-- DESCUENTO
INSERT INTO descuento (porcentaje_descuento, cant_dia_hospedado) VALUES 
(5.00, 3), 
(10.00, 7), 
(15.00, 14), 
(20.00, 30),
(25.00, 60);

-- AUMENTO_COSTOS
INSERT INTO aumento_costos (porcentaje_aumento, fecha_inicio, fecha_fin, nombre_temporada) VALUES 
(20.00, '2026-12-15', '2027-01-05', 'Temporada Navideña'),
(15.00, '2026-03-28', '2026-04-05', 'Semana Santa'),
(10.00, '2026-08-01', '2026-08-07', 'Vacaciones de Agosto'),
(25.00, '2026-06-01', '2026-08-31', 'Verano Internacional'),
(30.00, '2026-11-20', '2026-11-30', 'Black Week');

-- HOTEL
INSERT INTO hotel (nombre, direccion, niveles_edificios, calificacion, descripcion) VALUES 
('Hotel Royal San Salvador', 'Paseo Escalón #405', 6, 4.8, 'Lujo en la capital'),
('Playa Blanca Resort', 'La Costa del Sol, Km 75', 2, 4.5, 'Frente al mar'),
('Eco-Mountain Lodge', 'Ruta de las Flores', 3, 4.2, 'Ambiente natural'),
('City Business Center', 'Zona Rosa, San Salvador', 10, 4.0, 'Para ejecutivos'),
('Hostal Colonial', 'Suchitoto, Cuscatlán', 2, 3.5, 'Estilo clásico');

-- HUESPED
INSERT INTO huesped (nombre, correo, telefono, documento, tipo_documento) VALUES 
('Roberto Carlos', 'rcarlos@mail.com', '7788-9900', '05123456-7', 'DUI'),
('Alice Walker', 'alice.w@web.com', '2255-4433', 'A99887766', 'PASAPORTE'),
('Fernando Palomo', 'ferpa@sport.com', '7122-3344', '04889911-0', 'DUI'),
('Claudia Rivera', 'crivera@info.net', '6011-2233', 'P44556677', 'PASAPORTE'),
('Mario Gochez', 'mgochez@res.com', '2566-7788', 'RES-99881', 'CONSTANCIA DE RESIDENCIA');

-- SERVICIO
INSERT INTO servicio (tipo_servicio, precio) VALUES 
('Gimnasio', 10.00), ('Piscina Privada', 25.00), ('Tour Guiado', 40.00), ('Room Service', 15.00), ('Lavandería', 12.50);

-- TIPOS 
INSERT INTO tipo_comodidad (tipo_comodidad) VALUES 
('WiFi 6'), 
('Aire Acondicionado'), 
('Caja Fuerte'), 
('Jacuzzi'), 
('Mini-bar');

INSERT INTO tipo_empleado (tipo_empleado) VALUES 
('Gerencia'), 
('Recepcionista'), 
('Conserje'),
('Mantenimiento'), 
('Seguridad');

INSERT INTO tipo_habitacion (tipo_habitacion) VALUES 
('Sencilla'),
('Doble'), 
('Suite Ejecutiva'), 
('Penthouse'), 
('Estudio');

-- COMODIDAD_TIPO_HABITACION
INSERT INTO comodidad_tipo_habitacion (id_tipo_habitacion, id_tipo_comodidad, detalle) VALUES 
(1, 1, 'Internet de 200 Mbps'),
(2, 2, 'Split 12000 BTU'),
(3, 4, 'Jacuzzi para dos personas'),
(4, 5, 'Bebidas premium incluidas'), 
(5, 3, 'Digital con clave');

-- HABITACION
INSERT INTO habitacion (id_hotel, nivel, numero_habitacion, id_tipo_habitacion, precio, estado, capacidad_maxima) VALUES 
(1, 1, 101, 1, 65.00, 'DISPONIBLE', 2),
(1, 2, 201, 2, 95.00, 'OCUPADA', 4),
(2, 1, 10, 3, 180.00, 'DISPONIBLE', 4),
(3, 1, 5, 5, 50.00, 'MANTENIMIENTO', 2),
(4, 5, 505, 4, 300.00, 'DISPONIBLE', 6);

-- EMPLEADO (Validando formato DUI y Teléfono)
INSERT INTO empleado (id_tipo_empleado, nombre, correo, telefono, dui, salario) VALUES 
(1, 'Andrea Zelaya', 'azelaya@hotel.com', '+50322558877', '04556677-8', 1200.00),
(2, 'Kevin Meza', 'kmeza@hotel.com', '+50371889900', '02334455-6', 600.00),
(3, 'Luis Duarte', 'lduarte@hotel.com', '+50360223344', '09887766-5', 450.00),
(4, 'Sofia Varela', 'svarela@hotel.com', '+50325114422', '01112233-4', 500.00),
(5, 'Carlos Soler', 'csoler@hotel.com', '+50377441122', '08889900-1', 550.00);

-- RESERVACION
INSERT INTO reservacion (id_empleado, id_huesped, cant_huespedes_totales, estado) VALUES 
(2, 1, 2, 'CONFIRMADA'),
(2, 2, 1, 'PENDIENTE'),
(2, 3, 4, 'CONFIRMADA'),
(1, 4, 1, 'CANCELADA'),
(2, 5, 2, 'CONFIRMADA');

-- DETALLE_RESERVACION
INSERT INTO detalle_reservacion (id_reservacion, id_habitacion, cant_huespedes, fecha_entrada, fecha_salida) VALUES 
(1, 1, 2, '2026-05-10', '2026-05-15'),
(2, 5, 1, '2026-06-01', '2026-06-05'),
(3, 2, 4, '2026-05-20', '2026-05-25'),
(4, 3, 1, '2026-07-01', '2026-07-10'),
(5, 1, 2, '2026-08-01', '2026-08-05');

-- ESTADIA
INSERT INTO estadia (id_reservacion, checkin, checkout) VALUES 
(1, '2026-05-10 14:00:00', '2026-05-15 11:00:00'),
(3, '2026-05-20 15:30:00', '2026-05-25 10:00:00'),
(5, '2026-08-01 12:00:00', NULL), 
(1, '2026-09-10 14:00:00', '2026-09-12 11:00:00'),
(3, '2026-10-01 15:00:00', '2026-10-05 10:00:00');

-- CONSUMO_SERVICIO
INSERT INTO consumo_servicio (id_servicio, id_habitacion, id_estadia) VALUES 
(1, 1, 1), 
(4, 1, 1), 
(3, 2, 2), 
(5, 2, 2), 
(2, 1, 3);

-- RESENIA
INSERT INTO resenia (id_estadia, id_huesped, calificacion, comentario) VALUES 
(1, 1, 5.0, 'Excelente atención.'), 
(2, 3, 4.5, 'Muy espaciosa la habitación.'),
(4, 1, 3.0, 'El aire acondicionado falló.'),
(5, 3, 5.0, 'Todo perfecto.'),
(1, 2, 4.0, 'Buen tour guiado.');



-- FACTURA
INSERT INTO factura (id_empleado, id_huesped, id_estadia, metodo_pago, total_a_pagar) VALUES 
(1, 1, 1, 'TARJETA', 350.00), 
(1, 3, 2, 'EFECTIVO', 500.00), 
(2, 5, 3, 'BITCOIN', 150.00),
(1, 2, 4, 'PAYPAL', 200.00), 
(2, 4, 5, 'TRANSFERENCIA', 450.00);
INSERT INTO factura (id_empleado, id_huesped, id_estadia, metodo_pago, total_a_pagar) VALUES 
(1, 2, 5, 'PAYPAL', 900.00);

-- DETALLE_FACTURA (Mezcla de habitaciones y servicios según tus constraints)
INSERT INTO detalle_factura (id_factura, id_habitacion, id_descuento, concepto, precio_unitario, cantidad, subtotal, monto_descuento, precio_total) VALUES 
(1, 1, 1, 'Noches de hospedaje', 65.00, 5, 325.00, 16.25, 308.75);

INSERT INTO detalle_factura (id_factura, id_servicio, concepto, precio_unitario, cantidad, subtotal, precio_total) VALUES 
(1, 4, 'Room Service Cena', 15.00, 2, 30.00, 30.00);

INSERT INTO detalle_factura (id_factura, id_habitacion, id_aumento_costo, concepto, precio_unitario, cantidad, subtotal, monto_aumento, precio_total) VALUES 
(2, 2, 3, 'Hospedaje Temporada Agostina', 95.00, 5, 475.00, 47.50, 522.50);

INSERT INTO detalle_factura (id_factura, id_servicio, concepto, precio_unitario, cantidad, subtotal, precio_total) VALUES 
(3, 2, 'Uso de Piscina Privada', 25.00, 1, 25.00, 25.00);

INSERT INTO detalle_factura (id_factura, id_habitacion, id_descuento, concepto, precio_unitario, cantidad, subtotal, monto_descuento, precio_total) VALUES 
(5, 1, 2, 'Estancia Prolongada', 65.00, 8, 520.00, 52.00, 468.00);

--------------------------------------------------------------------------------
--------VISTAAAS--------

---------------Habitaciones disponibles en un rango de fechas ------------------

----- con inner join-----
select * from hotel

drop view vista_habitaciones_disponibles;

create view vista_habitaciones_disponibles AS
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

drop view vista_gasto_historica;

create view vista_gasto_historica AS
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

drop view servicios_mas_consumidos_tipo_habitacion;

create view servicios_mas_consumidos_tipo_habitacion AS
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





