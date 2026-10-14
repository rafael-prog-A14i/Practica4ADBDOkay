DROP DATABASE IF EXISTS viveros;
CREATE DATABASE viveros
    WITH ENCODING = 'UTF8';

\c viveros;

CREATE TABLE Viveros (
    idVivero VARCHAR(10) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL UNIQUE,
    Latitud NUMERIC(8, 5) NOT NULL,
    Longitud NUMERIC(8, 5) NOT NULL,
    CONSTRAINT chk_vivero_latitud CHECK (Latitud BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_vivero_longitud CHECK (Longitud BETWEEN -180.0 AND 180.0)
);

CREATE TABLE Zona (
    codigoZona VARCHAR(15) NOT NULL,
    idVivero VARCHAR(10) NOT NULL,
    Nombre VARCHAR(80) NOT NULL,
    Latitud NUMERIC(8, 5) NOT NULL,
    Longitud NUMERIC(8, 5) NOT NULL,
    PRIMARY KEY (idVivero, codigoZona),
    CONSTRAINT fk_zona_vivero FOREIGN KEY (idVivero)
        REFERENCES Viveros (idVivero)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_zona_latitud CHECK (Latitud BETWEEN -90.0 AND 90.0),
    CONSTRAINT chk_zona_longitud CHECK (Longitud BETWEEN -180.0 AND 180.0)
);

CREATE TABLE Producto (
    idProducto VARCHAR(12) PRIMARY KEY,
    Nombre VARCHAR(100) NOT NULL,
    Tipo VARCHAR(30) NOT NULL,
    CONSTRAINT chk_producto_tipo CHECK (Tipo IN ('Planta', 'Jardineria', 'Decoracion'))
);

CREATE TABLE Zona_Producto (
    idVivero VARCHAR(10) NOT NULL,
    codigoZona VARCHAR(15) NOT NULL,
    idProducto VARCHAR(12) NOT NULL,
    stockDisponible INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (idVivero, codigoZona, idProducto),
    CONSTRAINT fk_zp_zona FOREIGN KEY (idVivero, codigoZona)
        REFERENCES Zona (idVivero, codigoZona)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_zp_producto FOREIGN KEY (idProducto)
        REFERENCES Producto (idProducto)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_zp_stock CHECK (stockDisponible >= 0)
);

CREATE TABLE Empleado (
    idEmpleado VARCHAR(10) PRIMARY KEY,
    DNI VARCHAR(12) NOT NULL UNIQUE,
    nombreCompleto VARCHAR(120) NOT NULL,
    fechaNacimiento DATE NOT NULL,
    Telefono VARCHAR(20),
    CONSTRAINT chk_empleado_fecha_nac CHECK (fechaNacimiento < CURRENT_DATE)
);

CREATE TABLE Historico_Trabaja (
    idEmpleado VARCHAR(10) NOT NULL,
    fechaInicio DATE NOT NULL,
    idVivero VARCHAR(10) NOT NULL,
    codigoZona VARCHAR(15) NOT NULL,
    FechaFin DATE,
    EpocaAnio VARCHAR(20) NOT NULL,
    Puesto VARCHAR(60) NOT NULL,
    Productividad NUMERIC(5, 2) NOT NULL DEFAULT 100.00,
    PRIMARY KEY (idEmpleado, fechaInicio),
    CONSTRAINT fk_hist_empleado FOREIGN KEY (idEmpleado)
        REFERENCES Empleado (idEmpleado)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_hist_zona FOREIGN KEY (idVivero, codigoZona)
        REFERENCES Zona (idVivero, codigoZona)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT chk_hist_epoca CHECK (EpocaAnio IN ('Primavera', 'Verano', 'Otono', 'Invierno')),
    CONSTRAINT chk_hist_fechas CHECK (FechaFin IS NULL OR FechaFin >= fechaInicio),
    CONSTRAINT chk_hist_productividad CHECK (Productividad BETWEEN 0.00 AND 100.00)
);

CREATE TABLE Cliente (
    idCliente VARCHAR(10) PRIMARY KEY,
    DNI VARCHAR(12) NOT NULL UNIQUE,
    nombreCompleto VARCHAR(120) NOT NULL,
    esTajinastePlus BOOLEAN NOT NULL DEFAULT FALSE,
    fechaIngresoPlus DATE,
    volumenCompraMensual NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    bonificacionPorcentaje NUMERIC(5, 2) GENERATED ALWAYS AS (
        CASE
            WHEN NOT esTajinastePlus THEN 0.00
            WHEN volumenCompraMensual >= 300.00 THEN 15.00
            WHEN volumenCompraMensual >= 100.00 THEN 10.00
            WHEN volumenCompraMensual > 0.00 THEN 5.00
            ELSE 0.00
        END
    ) STORED,
    CONSTRAINT chk_cliente_volumen CHECK (volumenCompraMensual >= 0.00),
    CONSTRAINT chk_cliente_plus CHECK (
        (esTajinastePlus = TRUE AND fechaIngresoPlus IS NOT NULL) OR
        (esTajinastePlus = FALSE AND fechaIngresoPlus IS NULL AND volumenCompraMensual = 0.00)
    )
);

CREATE TABLE Pedido (
    idPedido VARCHAR(15) PRIMARY KEY,
    idCliente VARCHAR(10) NOT NULL,
    idEmpleado VARCHAR(10),
    fechaPedido DATE NOT NULL DEFAULT CURRENT_DATE,
    importeTotal NUMERIC(10, 2) NOT NULL,
    CONSTRAINT fk_pedido_cliente FOREIGN KEY (idCliente)
        REFERENCES Cliente (idCliente)
        ON DELETE CASCADE
        ON UPDATE CASCADE,
    CONSTRAINT fk_pedido_empleado FOREIGN KEY (idEmpleado)
        REFERENCES Empleado (idEmpleado)
        ON DELETE SET NULL
        ON UPDATE CASCADE,
    CONSTRAINT chk_pedido_importe CHECK (importeTotal > 0.00)
);

CREATE OR REPLACE FUNCTION fn_validar_pedido_plus()
RETURNS TRIGGER AS $$
DECLARE
    v_es_plus BOOLEAN;
    v_fecha_ingreso DATE;
BEGIN
    SELECT esTajinastePlus, fechaIngresoPlus
    INTO v_es_plus, v_fecha_ingreso
    FROM Cliente
    WHERE idCliente = NEW.idCliente;

    IF NOT v_es_plus THEN
        RAISE EXCEPTION 'El cliente % no pertenece al programa Tajinaste Plus.', NEW.idCliente;
    END IF;

    IF NEW.fechaPedido < v_fecha_ingreso THEN
        RAISE EXCEPTION 'La fecha del pedido (%) es anterior a la fecha de ingreso en Tajinaste Plus (%).',
            NEW.fechaPedido, v_fecha_ingreso;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validar_pedido_plus
BEFORE INSERT OR UPDATE ON Pedido
FOR EACH ROW EXECUTE FUNCTION fn_validar_pedido_plus();

CREATE OR REPLACE FUNCTION fn_actualizar_volumen_cliente()
RETURNS TRIGGER AS $$
DECLARE
    v_id_cliente VARCHAR(10);
BEGIN
    v_id_cliente := COALESCE(NEW.idCliente, OLD.idCliente);

    UPDATE Cliente
    SET volumenCompraMensual = COALESCE((
        SELECT SUM(importeTotal)
        FROM Pedido
        WHERE idCliente = v_id_cliente
    ), 0.00)
    WHERE idCliente = v_id_cliente;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_actualizar_volumen_cliente
AFTER INSERT OR UPDATE OR DELETE ON Pedido
FOR EACH ROW EXECUTE FUNCTION fn_actualizar_volumen_cliente();

INSERT INTO Viveros (idVivero, Nombre, Latitud, Longitud) VALUES
('VIV-01', 'Tajinaste La Laguna', 28.48740, -16.31590),
('VIV-02', 'Tajinaste Santa Cruz', 28.46360, -16.25180),
('VIV-03', 'Tajinaste La Orotava', 28.39050, -16.52300),
('VIV-04', 'Tajinaste Adeje Sur', 28.12270, -16.72600),
('VIV-05', 'Tajinaste Tegueste', 28.52220, -16.33640);

INSERT INTO Zona (codigoZona, idVivero, Nombre, Latitud, Longitud) VALUES
('Z-EXT', 'VIV-01', 'Zona Exterior Plantas', 28.48745, -16.31585),
('Z-ALM', 'VIV-01', 'Almacen Principal', 28.48735, -16.31595),
('Z-DEC', 'VIV-02', 'Zona Decoracion Interior', 28.46365, -16.25175),
('Z-INV', 'VIV-03', 'Invernadero Subtropical', 28.39055, -16.52310),
('Z-EXT', 'VIV-04', 'Exposicion Exterior Sur', 28.12275, -16.72605),
('Z-ALM', 'VIV-05', 'Almacen Semillas y Abonos', 28.52225, -16.33645);

INSERT INTO Producto (idProducto, Nombre, Tipo) VALUES
('PROD-01', 'Tajinaste Rojo del Teide', 'Planta'),
('PROD-02', 'Drago Canario Joven', 'Planta'),
('PROD-03', 'Sustrato Ecologico 50L', 'Jardineria'),
('PROD-04', 'Kit Tijeras de Poda Profesional', 'Jardineria'),
('PROD-05', 'Macetero Ceramico Volcanico', 'Decoracion'),
('PROD-06', 'Fuente Solar de Piedra', 'Decoracion');

INSERT INTO Zona_Producto (idVivero, codigoZona, idProducto, stockDisponible) VALUES
('VIV-01', 'Z-EXT', 'PROD-01', 50),
('VIV-01', 'Z-EXT', 'PROD-02', 20),
('VIV-01', 'Z-ALM', 'PROD-03', 150),
('VIV-02', 'Z-DEC', 'PROD-05', 40),
('VIV-03', 'Z-INV', 'PROD-01', 80),
('VIV-04', 'Z-EXT', 'PROD-06', 12);

INSERT INTO Empleado (idEmpleado, DNI, nombreCompleto, fechaNacimiento, Telefono) VALUES
('EMP-01', '43111222A', 'Carlos Hernandez Perez', '1990-04-12', '600111222'),
('EMP-02', '43222333B', 'Marta Rodriguez Armas', '1988-09-25', '600222333'),
('EMP-03', '43333444C', 'Javier Gonzalez Diaz', '1995-01-19', '600333444'),
('EMP-04', '43444555D', 'Elena Morales Bello', '1992-07-08', '600444555'),
('EMP-05', '43555666E', 'David Trujillo Ramos', '1999-11-30', '600555666'),
('EMP-06', '43666777F', 'Sofia Cabrera Mendez', '1985-03-14', '600666777');

INSERT INTO Historico_Trabaja (idEmpleado, fechaInicio, idVivero, codigoZona, FechaFin, EpocaAnio, Puesto, Productividad) VALUES
('EMP-01', '2026-01-01', 'VIV-01', 'Z-ALM', '2026-03-31', 'Invierno', 'Responsable de Almacen', 91.50),
('EMP-01', '2026-04-01', 'VIV-03', 'Z-INV', '2026-06-30', 'Primavera', 'Especialista Botanico', 95.00),
('EMP-02', '2026-04-01', 'VIV-01', 'Z-EXT', '2026-09-30', 'Verano', 'Asesora de Ventas', 98.20),
('EMP-03', '2026-01-01', 'VIV-02', 'Z-DEC', '2026-06-30', 'Primavera', 'Decorador de Exteriores', 88.00),
('EMP-04', '2026-07-01', 'VIV-04', 'Z-EXT', NULL, 'Verano', 'Encargada de Zona Sur', 93.40),
('EMP-05', '2026-09-01', 'VIV-05', 'Z-ALM', NULL, 'Otono', 'Mozo de Almacen', 85.00);

INSERT INTO Cliente (idCliente, DNI, nombreCompleto, esTajinastePlus, fechaIngresoPlus) VALUES
('CLI-01', '78100100A', 'Ana Belen Suarez', TRUE, '2025-05-10'),
('CLI-02', '78200200B', 'Luis Miguel Padron', TRUE, '2025-11-01'),
('CLI-03', '78300300C', 'Beatriz Afonso Mora', TRUE, '2026-01-15'),
('CLI-04', '78400400D', 'Roberto Dorta Cruz', TRUE, '2026-02-20'),
('CLI-05', '78500500E', 'Nuria Estevez Gil', FALSE, NULL),
('CLI-06', '78600600F', 'Pedro Santana Vega', FALSE, NULL);

INSERT INTO Pedido (idPedido, idCliente, idEmpleado, fechaPedido, importeTotal) VALUES
('PED-2026-001', 'CLI-01', 'EMP-01', '2026-10-01', 96.30),
('PED-2026-002', 'CLI-01', 'EMP-02', '2026-10-03', 85.00),
('PED-2026-003', 'CLI-02', 'EMP-02', '2026-10-05', 340.00),
('PED-2026-004', 'CLI-03', 'EMP-03', '2026-10-07', 64.20),
('PED-2026-005', 'CLI-04', 'EMP-04', '2026-10-10', 120.50),
('PED-2026-006', 'CLI-02', 'EMP-06', '2026-10-12', 42.80);

DELETE FROM Empleado WHERE idEmpleado = 'EMP-06';
DELETE FROM Pedido WHERE idPedido = 'PED-2026-002';
INSERT INTO Viveros VALUES ('VIV-99', 'Tajinaste Temporal', 28.40000, -16.30000);
INSERT INTO Zona VALUES ('Z-TMP', 'VIV-99', 'Zona Temporal', 28.40000, -16.30000);
DELETE FROM Viveros WHERE idVivero = 'VIV-99';

SELECT * FROM Viveros;
SELECT * FROM Zona;
SELECT * FROM Producto;
SELECT * FROM Zona_Producto;
SELECT * FROM Empleado;
SELECT * FROM Historico_Trabaja;
SELECT * FROM Cliente;
SELECT * FROM Pedido;
