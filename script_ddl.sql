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
