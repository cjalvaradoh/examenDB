-- CREACION DB
CREATE DATABASE Produccion2025
GO

USE Produccion2025
GO

SELECT * FROM dbo.forecast_produccion
SELECT * FROM dbo.produccion_real

-- ESQUEMA PARA DATOS CRUDOS 
CREATE SCHEMA stg;  

-- ALMACENANDO DATOS CRUDOS EN EL ESQUEMA STG
ALTER SCHEMA stg TRANSFER dbo.forecast_produccion;
ALTER SCHEMA stg TRANSFER dbo.produccion_real;

SELECT * FROM stg.forecast_produccion
SELECT * FROM stg.produccion_real

-- VERIFICAICON Y LIMPIEZA  (Limpieza)
-- VERIFICANDO INCOSISTENCIAS O REPETIDOS

SELECT * FROM stg.forecast_produccion WHERE mes NOT BETWEEN 1 AND 12;
SELECT * FROM stg.forecast_produccion WHERE cantidad_estimado < 0;

SELECT DISTINCT planta_nombre FROM stg.forecast_produccion;
SELECT DISTINCT producto_nombre FROM stg.forecast_produccion;

SELECT COUNT(*) AS total_registros FROM stg.forecast_produccion;

SELECT * FROM stg.forecast_produccion WHERE cantidad_estimado = 0;

-- VERIFICACION DE NULLS 
SELECT * FROM stg.forecast_produccion 
WHERE codigo_planta IS NULL 
   OR codigo_producto IS NULL
   OR año IS NULL
   OR mes IS NULL
   OR cantidad_estimado IS NULL
   OR planta_nombre IS NULL
   OR producto_nombre IS NULL;

 -- VERIFICACION DE NULLS 
SELECT * FROM stg.produccion_real
WHERE codigo_planta IS NULL 
   OR codigo_producto IS NULL
   OR año IS NULL
   OR mes IS NULL
   OR cantidad_real IS NULL
   OR horas_operativas IS NULL
   OR fallas_mecanicas IS NULL
   OR materia_prima_disponible IS NULL
   OR clima_adverso IS NULL;


-- Desde aqui me presentan data en las consultas
-- Plantas en forecast que no están en real y viceversa
SELECT DISTINCT codigo_planta, planta_nombre FROM stg.forecast_produccion
EXCEPT
SELECT DISTINCT codigo_planta, NULL FROM stg.produccion_real;

-- Productos en forecast que no están en real y viceversa
SELECT DISTINCT codigo_producto, producto_nombre FROM stg.forecast_produccion
EXCEPT
SELECT DISTINCT codigo_producto, NULL FROM stg.produccion_real;

-- Verificar si hay producción real cuando hay clima adverso
SELECT * FROM stg.produccion_real 
WHERE clima_adverso = 1 AND cantidad_real > 0;

-- Verificar si hay producción real cuando no hay materia prima
SELECT * FROM stg.produccion_real 
WHERE materia_prima_disponible = 0 AND cantidad_real > 0;

-- Verificar si hay meses sin datos de producción real pero con forecast
SELECT f.año, f.mes, f.planta_nombre, f.producto_nombre
FROM stg.forecast_produccion f
LEFT JOIN stg.produccion_real r 
  ON f.codigo_planta = r.codigo_planta 
  AND f.codigo_producto = r.codigo_producto
  AND f.año = r.año 
  AND f.mes = r.mes
WHERE r.codigo_planta IS NULL;

-- Esquema dimensional
CREATE SCHEMA dim;  -- Para dimensiones


--CREACION DE TRABLAS EN EL ESQUEMA DE DIMENSION
-- Tabla dim.Planta
CREATE TABLE dim.Planta (
    id_planta INT IDENTITY(1,1),
    codigo_planta INT NOT NULL,
    nombre_planta NVARCHAR(100) NOT NULL,
    fecha_carga DATETIME DEFAULT GETDATE()
);

ALTER TABLE dim.Planta
ADD CONSTRAINT PK_planta_id_s PRIMARY KEY (id_planta);

-- Tabla dim.Producto
CREATE TABLE dim.Producto (
    id_producto INT IDENTITY(1,1),
    codigo_producto NVARCHAR(50) NOT NULL,
    nombre_producto NVARCHAR(100) NOT NULL,
    fecha_carga DATETIME DEFAULT GETDATE()
);

ALTER TABLE dim.Producto
ADD CONSTRAINT PK_producto_id_s PRIMARY KEY (id_producto);


--Insertar Datos normalizados en las tablas de dimenciones

-- Insertar plantas únicas desde forecast_produccion
INSERT INTO dim.Planta (codigo_planta, nombre_planta)
SELECT DISTINCT 
    CAST(codigo_planta AS INT) AS codigo_planta,
    planta_nombre AS nombre_planta
FROM stg.forecast_produccion
WHERE NOT EXISTS (
    SELECT 1 FROM dim.Planta 
    WHERE CAST(codigo_planta AS INT) = dim.Planta.codigo_planta
);

-- Insertar productos únicos desde forecast_produccion
INSERT INTO dim.Producto (codigo_producto, nombre_producto)
SELECT DISTINCT 
    codigo_producto,
    producto_nombre AS nombre_producto
FROM stg.forecast_produccion
WHERE NOT EXISTS (
    SELECT 1 FROM dim.Producto 
    WHERE codigo_producto = dim.Producto.codigo_producto
);


--Creacion del Esquema
CREATE SCHEMA fact;

SELECT * FROM dim.planta;
SELECT * FROM dim.Producto;


--CREACION DE TRABLAS EN LA TABLA DE HECHOS
-- Primero creamos las tablas sin las FOREIGN KEY
CREATE TABLE fact.produccion_estimado (
    fecha DATE NOT NULL,
    id_planta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad_estimado INT NOT NULL,
    PRIMARY KEY (fecha, id_planta, id_producto)  -- Corregido: usar id_planta e id_producto
);

ALTER TABLE fact.produccion_estimado
ADD CONSTRAINT fk_produccion_estimado_planta 
FOREIGN KEY (id_planta) REFERENCES dim.planta(id_planta);

ALTER TABLE fact.produccion_estimado
ADD CONSTRAINT fk_produccion_estimado_producto 
FOREIGN KEY (id_producto) REFERENCES dim.producto(id_producto);

CREATE TABLE fact.produccion_real (
    fecha DATE NOT NULL,
    id_planta INT NOT NULL,
    id_producto INT NOT NULL,
    cantidad_real INT NOT NULL,
    horas_operativas INT,
    fallas_mecanicas INT,
    materia_prima_disponible INT,
    clima_adverso INT,
    PRIMARY KEY (fecha, id_planta, id_producto)  -- Corregido: usar id_planta e id_producto
);

ALTER TABLE fact.produccion_real
ADD CONSTRAINT fk_produccion_real_planta 
FOREIGN KEY (id_planta) REFERENCES dim.planta(id_planta);

ALTER TABLE fact.produccion_real
ADD CONSTRAINT fk_produccion_real_producto 
FOREIGN KEY (id_producto) REFERENCES dim.producto(id_producto);

--Insertar Datos normalizados en las tablas de Hechos

INSERT INTO fact.produccion_estimado (fecha, id_planta, id_producto, cantidad_estimado)
SELECT 
    DATEFROMPARTS(año, mes, 1) AS fecha,
    p.id_planta,
    pr.id_producto,  -- Corregido: usar id_producto en lugar de id_planta
    f.cantidad_estimado
FROM stg.forecast_produccion f
JOIN dim.planta p ON f.codigo_planta = p.codigo_planta
JOIN dim.producto pr ON f.codigo_producto = pr.codigo_producto
WHERE f.cantidad_estimado IS NOT NULL;

INSERT INTO fact.produccion_real (fecha, id_planta, id_producto, cantidad_real, horas_operativas, fallas_mecanicas, materia_prima_disponible, clima_adverso)
SELECT 
    DATEFROMPARTS(año, mes, 1),
    p.id_planta,
    pr.id_producto,
    r.cantidad_real,
    r.horas_operativas,
    r.fallas_mecanicas,
    r.materia_prima_disponible,
    r.clima_adverso
FROM stg.produccion_real r
JOIN dim.planta p ON r.codigo_planta = p.codigo_planta
JOIN dim.producto pr ON r.codigo_producto = pr.codigo_producto
WHERE r.cantidad_real IS NOT NULL;

SELECT TOP 10 * FROM  fact.produccion_estimado ;
SELECT TOP 10 * FROM  fact.produccion_real ;