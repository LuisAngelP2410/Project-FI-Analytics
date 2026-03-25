
-- -- -- -- -- -- --
-- DATA EXTRACCION --
-- -- -- -- -- -- --

CREATE DATABASE PROYECTO_FINAL;
USE PROYECTO_FINAL;


-- 1. CREACIÓN DE LAS 3 TABLAS NORMALIZADAS 
CREATE TABLE TB_EMPRESAS (
    ID_ANONIMO_EMP VARCHAR(255) PRIMARY KEY,
    TAMANO_EMP VARCHAR(100),
    CIIU INT,
    DESCRIPCION_CIIU VARCHAR(MAX),
    SECTOR VARCHAR(MAX),
    CONTRIBUYENTE VARCHAR(MAX),
    FECHA_DE_CREACION VARCHAR(50)
);

CREATE TABLE TB_GEOGRAFIA (
    ID_ANONIMO_EMP VARCHAR(255),
    UBIGEO INT,
    DEPARTAMENTO VARCHAR(100),
    PROVINCIA VARCHAR(100),
    DISTRITO VARCHAR(100)
);

CREATE TABLE TB_FINANZAS (
    ID_ANONIMO_EMP VARCHAR(255),
    NUMERO_TRAB INT,
    SALDO_MIL_SOLES DECIMAL(18,2),
    EXPORTA VARCHAR(10),
    VENTAS_PROM DECIMAL(18,2),
    ANO INT
);

-- 2. REPARTIR LA DATA (Asegúrate de que los nombres coincidan exactamente con tu CSV)

-- A. Llenamos la tabla de Empresas (Datos maestros)
INSERT INTO TB_EMPRESAS 
SELECT DISTINCT ID_ANONIMO_EMP, TAMANO_EMPRESA, CIIU, DESCRIPCION_CIUU
, SECTOR, CONTRIBUYENTE, FECHA_DE_CREACION 
FROM CARGA_TOTAL;

-- B. Llenamos la tabla de Geografía
INSERT INTO TB_GEOGRAFIA 
SELECT DISTINCT ID_ANONIMO_EMP, UBIGEO, DEPARTAMENTO, PROVINCIA, DISTRITO 
FROM CARGA_TOTAL;

-- C. Llenamos la tabla de Finanzas (Aquí van todos los registros históricos)
INSERT INTO TB_FINANZAS 
SELECT ID_ANONIMO_EMP, NUMERO_DE_TRABAJADORES,SALDO_MILES_SOLES,EXPORTACION, VENTAS_PROM,ANO 
FROM CARGA_TOTAL;

----------------------
--- DATA CLEANING ----
----------------------
USE PROYECTO_FINAL

--VERIFICAR VALORES DUPLICADOS EN LA TABLA EMPRESAS	(POR EL ID DE LA EMPRESA)

SELECT ID_ANONIMO_EMP, COUNT(*)
FROM TB_EMPRESAS 
GROUP BY ID_ANONIMO_EMP
HAVING COUNT(*) > 1 ; 

----- ELIMINAR LA DATA QUE NO CONTENGA LA INFORMACIÓN COMPLETA-----

---1. Eliminar empresas que no tienen identificación y sector 
DELETE FROM TB_EMPRESAS
WHERE ID_ANONIMO_EMP IS NULL OR ID_ANONIMO_EMP = '';

DELETE FROM TB_EMPRESAS
WHERE SECTOR IS NULL OR SECTOR = '';

---2. Eliminar registros financieros que no tienen ni Deuda ni Ventas (Si ambos son 0 o NULL, no hay nada que analizar en riesgo)
DELETE FROM TB_FINANZAS
WHERE (SALDO_MIL_SOLES IS NULL OR SALDO_MIL_SOLES = 0)

DELETE FROM TB_FINANZAS
WHERE VENTAS_PROM = 0 


-- 3. Eliminar registros sin ubicación geográfica mínima (Departamento)
DELETE FROM TB_GEOGRAFIA 
WHERE DEPARTAMENTO IS NULL OR DEPARTAMENTO = '';

---- Standardization --
-- A) Para dejar todo en mayúsculas y sin espacios 
UPDATE TB_GEOGRAFIA
SET DEPARTAMENTO = UPPER(LTRIM(RTRIM(DEPARTAMENTO))),
    PROVINCIA = UPPER(LTRIM(RTRIM(PROVINCIA))),
    DISTRITO = UPPER(LTRIM(RTRIM(DISTRITO)));

UPDATE TB_EMPRESAS
SET SECTOR = UPPER(LTRIM(RTRIM(SECTOR))),
    TAMANO_EMP = UPPER(LTRIM(RTRIM(TAMANO_EMP)));

---B) PARA LA COLUMNA DE EXPORTACION PARA SOLO TENER LA RESPUESTA SI o NO

UPDATE TB_FINANZAS
SET EXPORTA = CASE 
    WHEN EXPORTA IN ('SI', 'S', '1', 'si') THEN 'SI'
    ELSE 'NO'
END;


--C) DELIMITAR EL RANGO DE VENTAS POR NIVEL DE EMPRESA

-- Añadimos una columna para categorizar
ALTER TABLE TB_FINANZAS ADD NIVEL_VENTAS VARCHAR(20);

-- Estandarizamos los rangos
UPDATE TB_FINANZAS
SET NIVEL_VENTAS = 
	CASE 
    WHEN VENTAS_PROM < 100 THEN 'BAJO'
    WHEN VENTAS_PROM BETWEEN 100 AND 500 THEN 'MEDIO'
    ELSE 'ALTO'
END;

-- -- -- -- -- -- -- -- -- -- -- -- -- -- --
-- EXPLORATORY DATA ANALYSIS AND INSIGHTS --
-- -- -- -- -- -- -- -- -- -- -- -- -- -- --

--1. El Planteamiento: Antes de analizar riesgos, un auditor debe saber dónde está el dinero. Queremos identificar cuáles son los 5 sectores económicos que acumulan la mayor deuda total en el país.

SELECT TOP 5 E.SECTOR, SUM(F.SALDO_MIL_SOLES * 1000) AS DEUDA_TOTAL_SOLES, COUNT (E.ID_ANONIMO_EMP) AS CANTIDAD_EMPRESAS
FROM TB_EMPRESAS AS E
INNER JOIN TB_FINANZAS AS F ON E.ID_ANONIMO_EMP= F.ID_ANONIMO_EMP
GROUP BY SECTOR
ORDER BY DEUDA_TOTAL_SOLES DESC;


-- 2. Queremos identificar cuáles son los Departamentos que acumulan la mayor cantidad de deuda real en soles. Pero, para hacerlo más analítico, no solo queremos el total, sino también el promedio de deuda por empresa en cada departamento.

SELECT G.DEPARTAMENTO, SUM(F.SALDO_MIL_SOLES * 1000) AS TOTAL_DEUDA_REGION, COUNT(G.ID_ANONIMO_EMP) AS NUMERO_MYPE, AVG(F.SALDO_MIL_SOLES * 1000) AS DEUDA_PROMEDIO_MYPE
FROM TB_GEOGRAFIA G
INNER JOIN TB_FINANZAS F ON G.ID_ANONIMO_EMP=F.ID_ANONIMO_EMP
GROUP BY DEPARTAMENTO
ORDER BY TOTAL_DEUDA_REGION DESC;

--- 3. ¿Qué sectores presentan una estructura financiera más apalancada (mayor proporción de deuda frente a sus ventas anuales)?

SELECT 
    E.SECTOR, 
    (SUM(F.SALDO_MIL_SOLES * 1000.0) / SUM(F.VENTAS_PROM)) AS RATIO_SECTORIAL
FROM TB_EMPRESAS AS E
INNER JOIN TB_FINANZAS AS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
GROUP BY E.SECTOR
ORDER BY RATIO_SECTORIAL DESC;

-- 4. Se busca crear un "SEMAFORO DE RIESGO" para clasificar a cada empresa según su ratio de endeudamiento ( ratio = deuda real/ventas reales). 
--- Reglas de Auditoría : 'CRÍTICO': Ratio > 3 (Debe más de 3 años de lo que vende). 'MODERADO': Ratio entre 1 y 3. Y 'SALUDABLE': Ratio < 1.

SELECT *,
CASE 
    WHEN ((SALDO_MIL_SOLES * 1000)/VENTAS_PROM) > 3 THEN 'CRITICO'
	WHEN ((SALDO_MIL_SOLES * 1000)/VENTAS_PROM) BETWEEN 1 AND 3 THEN 'MODERADO'
	WHEN ((SALDO_MIL_SOLES * 1000)/VENTAS_PROM) < 1 THEN 'SALUDABLE'
	END AS SEMAFORO_RIESGOS 
FROM TB_FINANZAS

--- 5. ¿En qué sector hay más empresas en situación CRÍTICA?". No queremos ver la lista de empresas, queremos el conteo total de empresas críticas por cada sector.

SELECT E.SECTOR,
COUNT (CASE WHEN ((SALDO_MIL_SOLES*1000)/VENTAS_PROM) > 3 THEN '1' END) AS CANTIDAD_CRITICOS
FROM TB_FINANZAS F
INNER JOIN TB_EMPRESAS E ON F.ID_ANONIMO_EMP= E.ID_ANONIMO_EMP
GROUP BY E.SECTOR
ORDER BY CANTIDAD_CRITICOS DESC;

--- 6. Se requiere comparar el Ratio de Endeudamiento Promedio de las empresas que SÍ exportan frente a las que NO exportan, segmentado por Sector. Para comprobar la hipotesis "Las empresas que exportan tienen un flujo de caja más estable y, por lo tanto, un ratio de endeudamiento más bajo que las que solo venden al mercado local".

 SELECT 
    E.SECTOR,
    AVG(CASE WHEN F.EXPORTA = 'SI' THEN (F.SALDO_MIL_SOLES * 1000) / F.VENTAS_PROM END) AS RATIO_EXPORTADOR,
    AVG(CASE WHEN F.EXPORTA = 'NO' THEN (F.SALDO_MIL_SOLES * 1000) / F.VENTAS_PROM END) AS RATIO_NO_EXPORTADOR
FROM TB_EMPRESAS E
INNER JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
GROUP BY E.SECTOR
ORDER BY RATIO_EXPORTADOR DESC;

--- 7. Queremos identificar las 10 empresas más productivas (Ventas por Trabajador) de todo el país, pero solo de aquellas que tienen más de 5 trabajadores (para evitar distorsiones de empresas unipersonales).

SELECT TOP 10
    E.ID_ANONIMO_EMP,
    E.SECTOR,
    G.DEPARTAMENTO,
    (F.VENTAS_PROM / F.NUMERO_TRAB) AS PRODUCTIVIDAD_LABORAL
FROM TB_EMPRESAS AS E
INNER JOIN TB_FINANZAS AS F ON E.ID_ANONIMO_EMP=F.ID_ANONIMO_EMP
INNER JOIN TB_GEOGRAFIA AS G ON E.ID_ANONIMO_EMP = G.ID_ANONIMO_EMP
WHERE F.NUMERO_TRAB > 5
ORDER BY PRODUCTIVIDAD_LABORAL DESC;

--- 8. Listar las empresas cuyo ratio individual de deuda es superior al promedio de su propio sector. Esto permite identificar 'Ovejas Negras' o empresas con una gestión financiera deficiente en comparación con sus pares directos.

SELECT 
    E.ID_ANONIMO_EMP,
    E.SECTOR,
    ((F.SALDO_MIL_SOLES * 1000.0) / F.VENTAS_PROM) AS RATIO_EMPRESA
FROM TB_EMPRESAS E
INNER JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
WHERE ((F.SALDO_MIL_SOLES * 1000.0) / F.VENTAS_PROM) > (
  SELECT AVG((F2.SALDO_MIL_SOLES * 1000.0) / F2.VENTAS_PROM)
    FROM TB_FINANZAS F2
    INNER JOIN TB_EMPRESAS E2 ON F2.ID_ANONIMO_EMP = E2.ID_ANONIMO_EMP
    WHERE E2.SECTOR = E.SECTOR
)
ORDER BY RATIO_EMPRESA DESC;

--- 9. Muéstrame cuál es la empresa más endeudada de cada departamento, sin importar cuántos departamentos existan 

WITH RankingDeuda AS (
    SELECT 
        G.DEPARTAMENTO,
        E.ID_ANONIMO_EMP,
        E.SECTOR,
        (F.SALDO_MIL_SOLES * 1000.0) AS DEUDA_REAL,
        ROW_NUMBER() OVER(
            PARTITION BY G.DEPARTAMENTO 
            ORDER BY (F.SALDO_MIL_SOLES * 1000.0) DESC
        ) AS POSICION
    FROM TB_EMPRESAS E
    INNER JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
    INNER JOIN TB_GEOGRAFIA G ON E.ID_ANONIMO_EMP = G.ID_ANONIMO_EMP
)
SELECT * 
FROM RankingDeuda 
WHERE POSICION = 1;

---10. Ya sabemos quiénes son los más endeudados. Pero ahora queremos saber qué tanto pesa cada empresa individual dentro de su propio sector.

SELECT 
    E.ID_ANONIMO_EMP,
    E.SECTOR,
    (F.SALDO_MIL_SOLES * 1000.0) AS DEUDA_INDIVIDUAL,
    SUM(F.SALDO_MIL_SOLES * 1000.0) OVER(PARTITION BY E.SECTOR) AS TOTAL_DEUDA_SECTOR,
    ((F.SALDO_MIL_SOLES * 1000.0) / SUM(F.SALDO_MIL_SOLES * 1000.0) OVER(PARTITION BY E.SECTOR)) * 100 AS PORCENTAJE_PARTICIPACION
FROM TB_EMPRESAS E
INNER JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
ORDER BY E.SECTOR, PORCENTAJE_PARTICIPACION DESC;
 
--- 11. "Diseñar un Algoritmo de Detección de Anomalías que identifique empresas con comportamientos fuera de la norma sectorial. El objetivo es filtrar empresas que reportan una productividad laboral humana imposible (ventas excesivas con pocos empleados) combinada con un sobreendeudamiento extremo (5 veces mayor al promedio de su sector), clasificándolas por nivel de prioridad para una auditoría forense inmediata."

WITH EstadisticasSectores AS (
    SELECT 
        E.ID_ANONIMO_EMP,
        E.SECTOR,
        G.DEPARTAMENTO,
        F.VENTAS_PROM,
        F.NUMERO_TRAB,
        (F.SALDO_MIL_SOLES * 1000.0) AS DEUDA_REAL,
        -- Promedio del ratio por sector usando Window Function
        AVG((F.SALDO_MIL_SOLES * 1000.0) / F.VENTAS_PROM) OVER(PARTITION BY E.SECTOR) AS PROMEDIO_RATIO_SECTOR
    FROM TB_EMPRESAS E
    JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
    JOIN TB_GEOGRAFIA G ON E.ID_ANONIMO_EMP = G.ID_ANONIMO_EMP
),
CalculoAlertas AS (
    SELECT *,
        -- Alerta 1: Ventas por trabajador > 500k (Productividad sospechosa)
        CASE WHEN (VENTAS_PROM / NUMERO_TRAB) > 500000 THEN 1 ELSE 0 END AS ALERTA_PRODUCTIVIDAD,
        -- Alerta 2: Deuda individual > 5 veces el promedio de su sector
        CASE WHEN (DEUDA_REAL / VENTAS_PROM) > (PROMEDIO_RATIO_SECTOR * 5) THEN 1 ELSE 0 END AS ALERTA_SOBREDEUDA
    FROM EstadisticasSectores
)
SELECT 
    ID_ANONIMO_EMP, 
    SECTOR, 
    DEPARTAMENTO,
    (ALERTA_PRODUCTIVIDAD + ALERTA_SOBREDEUDA) AS PUNTOS_RIESGO,
    CASE 
        WHEN (ALERTA_PRODUCTIVIDAD + ALERTA_SOBREDEUDA) = 2 THEN 'INVESTIGACIÓN INMEDIATA'
        WHEN (ALERTA_PRODUCTIVIDAD + ALERTA_SOBREDEUDA) = 1 THEN 'REVISIÓN DOCUMENTAL'
        ELSE 'NORMAL'
    END AS PRIORIDAD_AUDITORIA
FROM CalculoAlertas
WHERE (ALERTA_PRODUCTIVIDAD + ALERTA_SOBREDEUDA) > 0
ORDER BY PUNTOS_RIESGO DESC, DEUDA_REAL DESC;

--- 12. Calcular qué porcentaje de la deuda total de cada departamento está concentrada únicamente en sus 3 empresas más grandes. Un alto porcentaje indica que la economía regional es vulnerable ante la caída de unos pocos actores.

WITH DeudaRegional AS (
    SELECT 
        G.DEPARTAMENTO,
        (F.SALDO_MIL_SOLES * 1000.0) AS DEUDA_EMPRESA,
        SUM(F.SALDO_MIL_SOLES * 1000.0) OVER(PARTITION BY G.DEPARTAMENTO) AS TOTAL_DEPTO,
        ROW_NUMBER() OVER(PARTITION BY G.DEPARTAMENTO ORDER BY F.SALDO_MIL_SOLES DESC) AS RANK_DEUDA
    FROM TB_FINANZAS F
    JOIN TB_GEOGRAFIA G ON F.ID_ANONIMO_EMP = G.ID_ANONIMO_EMP
)
SELECT 
    DEPARTAMENTO,
    ROUND((SUM(CASE WHEN RANK_DEUDA <= 3 THEN DEUDA_EMPRESA ELSE 0 END) / MAX(TOTAL_DEPTO)) * 100, 2) AS PCT_CONCENTRACION_TOP3
FROM DeudaRegional
GROUP BY DEPARTAMENTO
ORDER BY PCT_CONCENTRACION_TOP3 DESC;

---13. Crear una Matriz de Distribución de Riesgo que cuente cuántas empresas por cada SECTOR tardarían: 'Menos de 1 año', '1 a 5 años' o 'Más de 5 años' en pagar su deuda con sus ventas actuales

SELECT 
    E.SECTOR,
    COUNT(CASE WHEN (F.SALDO_MIL_SOLES * 1000.0 / (F.VENTAS_PROM / 12.0)) <= 12 THEN 1 END) AS RIESGO_BAJO_1_ANIO,
    COUNT(CASE WHEN (F.SALDO_MIL_SOLES * 1000.0 / (F.VENTAS_PROM / 12.0)) BETWEEN 13 AND 60 THEN 1 END) AS RIESGO_MEDIO_5_ANIOS,
    COUNT(CASE WHEN (F.SALDO_MIL_SOLES * 1000.0 / (F.VENTAS_PROM / 12.0)) > 60 THEN 1 END) AS RIESGO_ALTO_MAS_5_ANIOS
FROM TB_EMPRESAS E
JOIN TB_FINANZAS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
GROUP BY E.SECTOR
ORDER BY RIESGO_ALTO_MAS_5_ANIOS DESC;

---14. Identificar qué empresas tienen una carga de deuda por cada trabajador que supera los 100,000 soles. Esto ayuda a detectar empresas que están muy endeudadas pero tienen muy poca fuerza laboral para generar ingresos.

SELECT 
    G.DEPARTAMENTO,
    E.ID_ANONIMO_EMP,
    E.SECTOR,
    (F.SALDO_MIL_SOLES * 1000.0) AS DEUDA_TOTAL,
    F.NUMERO_TRAB,
    ((F.SALDO_MIL_SOLES * 1000.0) / F.NUMERO_TRAB) AS DEUDA_POR_TRABAJADOR
FROM TB_EMPRESAS AS E
INNER JOIN TB_FINANZAS AS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
INNER JOIN TB_GEOGRAFIA AS G ON E.ID_ANONIMO_EMP = G.ID_ANONIMO_EMP
WHERE ((F.SALDO_MIL_SOLES * 1000.0) / F.NUMERO_TRAB) > 100000
ORDER BY DEUDA_POR_TRABAJADOR DESC;


--- 15. Generar un resumen final que muestre por cada Sector: cuántas empresas hay, cuánta deuda total acumulan y cuál es el promedio de trabajadores.

SELECT 
    E.SECTOR,
    COUNT(E.ID_ANONIMO_EMP) AS CANTIDAD_MYPE,
    SUM(F.SALDO_MIL_SOLES * 1000.0) AS TOTAL_DEUDA_SECTOR,
    AVG(F.VENTAS_PROM) AS VENTAS_PROMEDIO_SECTOR,
    AVG(F.NUMERO_TRAB) AS PROMEDIO_TRABAJADORES
FROM TB_EMPRESAS AS E
INNER JOIN TB_FINANZAS AS F ON E.ID_ANONIMO_EMP = F.ID_ANONIMO_EMP
GROUP BY E.SECTOR
ORDER BY TOTAL_DEUDA_SECTOR DESC;





