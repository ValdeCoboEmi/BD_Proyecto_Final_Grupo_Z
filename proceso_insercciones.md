# 🏨 Sistema de Gestión Hotelera  

## 📘 Guía de Carga y Restauración de Base de Datos

Este documento explica los procedimientos necesarios para poblar la base de datos del sistema hotelero, ya sea mediante:

- 📦 **Restauración completa desde un Backup SQL** *(recomendado)*  
- 🚀 **Carga masiva individual utilizando archivos CSV**

---

# 📑 Menú de Opciones

1. [📌 Consideraciones Previas](#-consideraciones-previas)
2. [📦 Opción 1: Restauración Completa desde Backup SQL](#-opción-1-restauración-completa-desde-backup-sql-recomendado)
   - [🖥️ Restauración Local](#️-restauración-local)
   - [🐳 Restauración en Docker](#-restauración-en-docker)
3. [🚀 Opción 2: Carga Masiva mediante CSV](#-opción-2-carga-masiva-mediante-archivos-csv-bulk-insert)
   - [🏗️ Jerarquía de Inserción](#️-jerarquía-de-inserción-orden-obligatorio)
   - [📥 Comandos de Carga CSV](#-comandos-de-carga-csv)
4. [🛠️ Solución de Problemas Comunes](#️-solución-de-problemas-comunes)

---

# 📌 Consideraciones Previas

Antes de comenzar, toma en cuenta lo siguiente:

- ✅ **Estado de la Base de Datos**
  - Para la **Opción 1**, el script SQL incluye instrucciones `DROP TABLE`.
  - Para la **Opción 2**, las tablas deben existir previamente y estar vacías.

- ✅ **Codificación de Archivos**
  - Todos los archivos deben estar en formato **UTF-8**.

- ✅ **Usuario de PostgreSQL**
  - El usuario por defecto es:

```bash
postgres
````

> ⚠️ Importante: el parámetro del usuario siempre se escribe con `-U` mayúscula.

---

# 📦 Opción 1: Restauración Completa desde Backup SQL (Recomendado)

Esta es la forma más rápida y segura de restaurar:

* estructura
* restricciones
* validaciones
* datos de ejemplo

Todo en un solo paso.

---

## 🖥️ Restauración Local

Si tienes PostgreSQL instalado directamente en tu sistema operativo:

```bash
psql -U postgres -d db_sistemas_reservas_hote -f backup_hotel_db.sql
```

---

## 🐳 Restauración en Docker

Si utilizas un contenedor Docker llamado:

```bash
some-postgres
```

### 🔹 Desde Windows (PowerShell)

```powershell
Get-Content backup_hotel_db.sql | docker exec -i some-postgres psql -U postgres -d db_sistemas_reservas_hotel
```

### 🔹 Desde Linux o CMD

```bash
docker exec -i some-postgres psql -U postgres -d db_sistemas_reservas_hotel < backup_hotel_db.sql
```

---

# 🚀 Opción 2: Carga Masiva mediante Archivos CSV (Bulk Insert)

Utiliza esta opción únicamente si deseas cargar los archivos individualmente.

---

## 🏗️ Jerarquía de Inserción (Orden Obligatorio)

> ⚠️ Debes respetar este orden para evitar errores de llaves foráneas.

---

### 📂 Fase 1: Catálogos e Independientes

1. `descuento.csv`
2. `aumento_costos.csv`
3. `hotel.csv`
4. `huesped.csv`
5. `servicio.csv`
6. `tipo_comodidad.csv`
7. `tipo_empleado.csv`
8. `tipo_habitacion.csv`

---

### 📂 Fase 2: Dependencias de Nivel 1

9. `comodidad_tipo_habitacion.csv`
10. `habitacion.csv`
11. `empleado.csv`

---

### 📂 Fase 3: Operaciones y Detalles

12. `reservacion.csv`
13. `detalle_reservacion.csv`
14. `estadia.csv`
15. `resenia.csv`
16. `consumo_servicio.csv`
17. `factura.csv`
18. `detalle_factura.csv`

---

# 📥 Comandos de Carga CSV

## 🔹 Paso 1: Copiar archivos al contenedor Docker

```bash
docker cp . some-postgres:/csv_data
```

---

## 🔹 Paso 2: Ejecutar COPY desde pgAdmin, DBeaver o Terminal

```sql
COPY nombre_tabla
FROM '/csv_data/archivo.csv'
WITH (
    FORMAT csv,
    HEADER true,
    DELIMITER ','
);
```

---

# 🛠️ Solución de Problemas Comunes

| ❌ Error                        | 📌 Causa Probable                       | ✅ Solución                                             |
| ------------------------------ | --------------------------------------- | ------------------------------------------------------ |
| `Invalid Option -u`            | Se utilizó `-u` minúscula               | Usa siempre `-U` mayúscula                             |
| `Permission Denied`            | PostgreSQL no tiene acceso a la carpeta | En Docker, copia los archivos a `/tmp/` o `/csv_data/` |
| `Key (id) is not present`      | Violación de llaves foráneas            | Respeta el orden de inserción por fases                |
| `Extra data after last column` | Delimitador incorrecto                  | Verifica si el CSV usa `,` o `;`                       |

---
