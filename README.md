# 🏨 Sistema de Reservas de Hotel - Proyecto Final de Bases de Datos

## 📋 Descripción del Proyecto
Este proyecto consiste en el diseño e implementación de una base de datos relacional para gestionar las operaciones de un hotel. El sistema permite administrar de manera integral las habitaciones, huéspedes, reservaciones, servicios adicionales y la facturación de las estancias. 

## 👥 Equipo de Desarrollo
* **Integrante 1:** Josué Abdel Ortiz Deodanes - 00017125
* **Integrante 2:** Osmar Alejandro Rodas Rodriguez - 00068125
* **Integrante 3:** Osmar Alejandro Rodas Rodriguez - 00068125
* **Integrante 4:** Eduardo Josué Guerra Sagastizado - 00043625
* **Integrante 5:** Josué Emiliano Valdés Jacobo - 00003525

## 🛠️ Tecnologías y Herramientas
* **Motor de Base de Datos:** PostgreSQL (Versión 17 o superior).
* **Gestor de Base de Datos:** DBeaver.
* **Modelado:** Modelo Entidad-Relación (Notación Chen).
* **Lenguaje:** SQL (DDL, DML, PL/pgSQL).

## 🏗️ Arquitectura de Datos
El diseño de la base de datos se encuentra normalizado hasta la Tercera Forma Normal (3FN) para garantizar la integridad y evitar redundancias. 

### Entidades Principales
El modelo conceptual incluye las siguientes entidades clave:
* Hotel, Tipo de Habitación, Habitación
* Huésped, Reservación, Check-In/Check-Out
* Servicio, Consumo de Servicio
* Empleado, Factura

## ⚙️ Reglas de Negocio Implementadas
* Un huésped puede realizar múltiples reservaciones.
* Una reservación cubre una habitación por un rango de fechas específico.
* Los huéspedes pueden consumir servicios adicionales (restaurante, lavandería, spa) durante su estancia.
* Al realizar el check-out, el sistema genera una factura consolidada.
* **Restricción Crítica:** Una habitación no puede estar reservada dos veces en el mismo período.

## 📂 Estructura de Archivos y Scripts
El repositorio está organizado de la siguiente manera para mantener el orden y la trazabilidad del código:

* **`Diagramas/`**: Carpeta que contiene los apoyos visuales, incluyendo el Diagrama Entidad-Relación en notación Chen y el esquema lógico relacional.
* **`script_ddl.sql`**: Script de definición de datos. Contiene la creación de la base de datos, las tablas y las restricciones de integridad.
* **`script_dml.sql`**: Script de manipulación de datos. Incluye la carga inicial de datos representativos para realizar pruebas en el sistema.
* **`programacion_sql.sql`**: Contiene la lógica procedimental de la base de datos:
    * **Trigger:** Validación al intentar insertar una reservación (verifica que la habitación no esté ocupada y lanza error si hay conflicto).
    * **Procedimiento Almacenado:** Proceso de check-out que calcula el total a cobrar (habitación + servicios) y genera la factura.
* **`consultas_sql.sql`**: Archivo con las consultas SQL desarrolladas que responden a las necesidades del negocio (habitaciones disponibles, ingresos totales, etc.).
* **Archivos de configuración y entorno**: 
    * `.dbeaver/` y `.project`: Archivos de configuración del entorno de desarrollo local.

## 🚀 Instalación y Ejecución Local
Para replicar el entorno de la base de datos y ejecutar el proyecto:

1. Clona este repositorio y asegúrate de hacer *pull* de los últimos cambios del equipo.
2. Abre tu gestor de bases de datos (recomendado: DBeaver, aprovechando la configuración incluida).
3. Ejecuta los scripts estrictamente en el siguiente orden:
    * Ejecuta primero `script_ddl.sql` para levantar la arquitectura.
    * Ejecuta `script_dml.sql` para poblar las tablas.
    * Carga las funciones y disparadores ejecutando `programacion_sql.sql`.
4. Utiliza `consultas_sql.sql` para probar la lógica de negocio y verificar el funcionamiento de las vistas y reportes.

## 📄 Documentación Técnica Adjunta
* **Documento_Tecnico.pdf**: Contiene la descripción de las reglas de negocio, el diccionario de datos y la documentación detallada de las consultas y la programación de la base de datos.
