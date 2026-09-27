-- ============================================================
-- BASE DE DATOS NORMALIZADA: COTIZADOR LABORATORIO
-- ============================================================
-- Base de datos para gestión de cotizaciones en laboratorio de ensayos
-- Autor: Sistema de Cotización GTQC
-- Fecha: 2024
-- ============================================================

-- Crear base de datos
CREATE DATABASE IF NOT EXISTS cotizador_laboratorio;
USE cotizador_laboratorio;

-- ============================================================
-- TABLA 1: EMPRESAS (Clientes tipo RUC)
-- ============================================================
CREATE TABLE EMPRESAS (
    ruc VARCHAR(11) PRIMARY KEY COMMENT 'RUC de 11 dígitos',
    razonSocial VARCHAR(255) NOT NULL COMMENT 'Razón social de la empresa',
    direccion VARCHAR(500) COMMENT 'Dirección registrada',
    telefonoEmpresa VARCHAR(20) COMMENT 'Teléfono principal',
    estado ENUM('activo', 'inactivo', 'suspendido') DEFAULT 'activo' COMMENT 'Estado actual',
    fechaRegistro TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Fecha de registro en sistema',
    INDEX idx_razonSocial (razonSocial),
    INDEX idx_estado (estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Tabla de empresas registradas en padrón SUNAT';

-- ============================================================
-- TABLA 2: CONTACTOS (Personas que representan empresas)
-- ============================================================
CREATE TABLE CONTACTOS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único (UUID)',
    empresaRuc VARCHAR(11) NOT NULL COMMENT 'RUC de la empresa',
    dni VARCHAR(8) NOT NULL COMMENT 'DNI del contacto (8 dígitos)',
    nombre VARCHAR(100) NOT NULL COMMENT 'Nombre del contacto',
    apellido VARCHAR(100) NOT NULL COMMENT 'Apellido del contacto',
    cargo VARCHAR(100) COMMENT 'Cargo/Posición en la empresa',
    celular VARCHAR(20) COMMENT 'Número de celular',
    email VARCHAR(150) COMMENT 'Correo electrónico',
    estado ENUM('activo', 'inactivo') DEFAULT 'activo' COMMENT 'Estado del contacto',
    fechaRegistro TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Fecha de registro',
    FOREIGN KEY (empresaRuc) REFERENCES EMPRESAS(ruc) ON DELETE RESTRICT,
    INDEX idx_empresaRuc (empresaRuc),
    INDEX idx_dni (dni),
    INDEX idx_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Tabla de personas que representan empresas (contactos)';

-- ============================================================
-- TABLA 3: PERSONAS (Clientes tipo DNI)
-- ============================================================
CREATE TABLE PERSONAS (
    dni VARCHAR(8) PRIMARY KEY COMMENT 'DNI de 8 dígitos',
    nombre VARCHAR(100) NOT NULL COMMENT 'Nombre de la persona',
    apellido VARCHAR(100) NOT NULL COMMENT 'Apellido de la persona',
    celular VARCHAR(20) COMMENT 'Número de celular',
    email VARCHAR(150) COMMENT 'Correo electrónico',
    empresaAsociada VARCHAR(255) COMMENT 'Empresa asociada (opcional)',
    estado ENUM('activo', 'inactivo') DEFAULT 'activo' COMMENT 'Estado de la persona',
    fechaRegistro TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Fecha de registro',
    INDEX idx_email (email),
    INDEX idx_estado (estado)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Tabla de personas (clientes DNI) registradas en sistema';

-- ============================================================
-- TABLA 4: ENSAYOS_CATALOGO (Catálogo de ensayos disponibles)
-- ============================================================
CREATE TABLE ENSAYOS_CATALOGO (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único del ensayo',
    nombre VARCHAR(150) NOT NULL COMMENT 'Nombre del ensayo',
    descripcion TEXT COMMENT 'Descripción detallada',
    norma VARCHAR(50) COMMENT 'Norma asociada (Ej: NTP 339.034, ASTM E)',
    precioBase DECIMAL(10, 2) NOT NULL COMMENT 'Precio base en soles',
    unidad VARCHAR(50) COMMENT 'Unidad de medida (por muestra, por lote, etc)',
    categoria VARCHAR(100) COMMENT 'Categoría del ensayo (concreto, agregados, etc)',
    tiempo_estimado VARCHAR(50) COMMENT 'Tiempo estimado de ejecución',
    activo BOOLEAN DEFAULT true COMMENT 'Disponible para cotizaciones',
    fechaCreacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fechaActualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_nombre (nombre),
    INDEX idx_norma (norma),
    INDEX idx_categoria (categoria),
    INDEX idx_activo (activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Catálogo de ensayos disponibles en el laboratorio';

-- ============================================================
-- TABLA 5: PAQUETES_CATALOGO (Paquetes de ensayos)
-- ============================================================
CREATE TABLE PAQUETES_CATALOGO (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único del paquete',
    nombre VARCHAR(150) NOT NULL COMMENT 'Nombre del paquete',
    descripcion TEXT COMMENT 'Descripción del paquete',
    ensayosIncluidos JSON NOT NULL COMMENT 'Array JSON con IDs de ensayos incluidos',
    precioBase DECIMAL(10, 2) NOT NULL COMMENT 'Precio total del paquete',
    descuento_porcentaje DECIMAL(5, 2) DEFAULT 0 COMMENT 'Descuento aplicable (%)',
    activo BOOLEAN DEFAULT true COMMENT 'Disponible para cotizaciones',
    fechaCreacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fechaActualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_nombre (nombre),
    INDEX idx_activo (activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Paquetes de ensayos predefinidos';

-- ============================================================
-- TABLA 6: COTIZACIONES (Encabezado de cotizaciones)
-- ============================================================
CREATE TABLE COTIZACIONES (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único de cotización (UUID)',
    numeroSerie VARCHAR(50) NOT NULL UNIQUE COMMENT 'Número correlativo (COT-2024-001)',
    clienteRuc VARCHAR(11) COMMENT 'RUC del cliente (si es empresa)',
    clienteDni VARCHAR(8) COMMENT 'DNI del cliente (si es persona)',
    contactoId VARCHAR(36) COMMENT 'ID del contacto (si cliente es empresa)',
    nombreProyecto VARCHAR(200) COMMENT 'Nombre del proyecto/obra',
    validezDias INT DEFAULT 30 COMMENT 'Días de validez de la cotización',
    plantilaId VARCHAR(36) COMMENT 'ID de plantilla usada',
    estado ENUM('borrador', 'emitida', 'aceptada', 'rechazada', 'cancelada') DEFAULT 'borrador' COMMENT 'Estado de cotización',
    fechaCreacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Fecha de creación',
    fechaEmision TIMESTAMP COMMENT 'Fecha de emisión',
    observaciones TEXT COMMENT 'Observaciones generales',

    FOREIGN KEY (clienteRuc) REFERENCES EMPRESAS(ruc) ON DELETE SET NULL,
    FOREIGN KEY (clienteDni) REFERENCES PERSONAS(dni) ON DELETE SET NULL,
    FOREIGN KEY (contactoId) REFERENCES CONTACTOS(id) ON DELETE SET NULL,
    INDEX idx_numeroSerie (numeroSerie),
    INDEX idx_clienteRuc (clienteRuc),
    INDEX idx_clienteDni (clienteDni),
    INDEX idx_estado (estado),
    INDEX idx_fechaCreacion (fechaCreacion)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Encabezado de cotizaciones';

-- ============================================================
-- TABLA 7: COTIZACION_ITEMS (Ítems de cada cotización)
-- ============================================================
CREATE TABLE COTIZACION_ITEMS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único del item',
    cotizacionId VARCHAR(36) NOT NULL COMMENT 'ID de la cotización',
    tipo ENUM('ensayo', 'paquete') NOT NULL COMMENT 'Tipo de item',
    itemId VARCHAR(36) NOT NULL COMMENT 'ID del ensayo o paquete',
    cantidad INT NOT NULL DEFAULT 1 COMMENT 'Cantidad de items',
    precioUnitario DECIMAL(10, 2) NOT NULL COMMENT 'Precio unitario',
    subtotal DECIMAL(12, 2) NOT NULL COMMENT 'Subtotal (cantidad x precio)',
    observaciones TEXT COMMENT 'Observaciones del item',
    fechaAgregado TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (cotizacionId) REFERENCES COTIZACIONES(id) ON DELETE CASCADE,
    INDEX idx_cotizacionId (cotizacionId),
    INDEX idx_tipo (tipo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Ítems incluidos en cada cotización';

-- ============================================================
-- TABLA 8: DESCUENTOS (Control de descuentos aplicados)
-- ============================================================
CREATE TABLE DESCUENTOS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único del descuento',
    cotizacionId VARCHAR(36) NOT NULL COMMENT 'ID de la cotización',
    tipo ENUM('porcentaje', 'monto') NOT NULL COMMENT 'Tipo de descuento',
    valor DECIMAL(10, 2) NOT NULL COMMENT 'Valor del descuento',
    montoDescuento DECIMAL(12, 2) NOT NULL COMMENT 'Monto final calculado',
    razon VARCHAR(255) COMMENT 'Razón/justificación del descuento',
    autorizadoPor VARCHAR(100) COMMENT 'Usuario que autorizó',
    fechaAplicacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (cotizacionId) REFERENCES COTIZACIONES(id) ON DELETE CASCADE,
    INDEX idx_cotizacionId (cotizacionId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Registro de descuentos aplicados a cotizaciones';

-- ============================================================
-- TABLA 9: PLANTILLAS (Modelos de cotización)
-- ============================================================
CREATE TABLE PLANTILLAS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único de la plantilla',
    nombre VARCHAR(150) NOT NULL COMMENT 'Nombre de la plantilla',
    descripcion TEXT COMMENT 'Descripción de uso',
    nombreEmpresa VARCHAR(255) NOT NULL COMMENT 'Nombre de empresa en plantilla',
    logoUrl VARCHAR(500) COMMENT 'URL del logo',
    telefonoEmpresa VARCHAR(20) COMMENT 'Teléfono de contacto',
    emailEmpresa VARCHAR(150) COMMENT 'Email de contacto',
    direccionEmpresa VARCHAR(500) COMMENT 'Dirección de empresa',
    terminosCondiciones TEXT COMMENT 'Términos y condiciones específicos',
    condicionesPago VARCHAR(500) COMMENT 'Condiciones de pago',
    notaAdicional TEXT COMMENT 'Nota adicional en pie de página',
    colorPrimario VARCHAR(7) DEFAULT '#6366f1' COMMENT 'Color principal (hex)',
    colorSecundario VARCHAR(7) DEFAULT '#8b5cf6' COMMENT 'Color secundario (hex)',
    activo BOOLEAN DEFAULT true COMMENT 'Plantilla disponible',
    fechaCreacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    fechaActualizacion TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_nombre (nombre),
    INDEX idx_activo (activo)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Plantillas de cotización personalizables';

-- ============================================================
-- TABLA 10: COTIZACION_DESCARGAS (Registro de descargas)
-- ============================================================
CREATE TABLE COTIZACION_DESCARGAS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único',
    cotizacionId VARCHAR(36) NOT NULL COMMENT 'ID de cotización',
    tipo ENUM('pdf', 'excel', 'json') NOT NULL COMMENT 'Formato descargado',
    modoDescarga ENUM('online', 'offline') NOT NULL COMMENT 'Modo de descarga',
    ipDescarga VARCHAR(45) COMMENT 'IP del descargador',
    usuarioDescarga VARCHAR(100) COMMENT 'Usuario que descargó',
    fechaDescarga TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (cotizacionId) REFERENCES COTIZACIONES(id) ON DELETE CASCADE,
    INDEX idx_cotizacionId (cotizacionId),
    INDEX idx_fechaDescarga (fechaDescarga)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Registro de descargas de cotizaciones';

-- ============================================================
-- TABLA 11: COTIZACION_ENVIOS (Registro de envíos por email/WhatsApp)
-- ============================================================
CREATE TABLE COTIZACION_ENVIOS (
    id VARCHAR(36) PRIMARY KEY COMMENT 'ID único',
    cotizacionId VARCHAR(36) NOT NULL COMMENT 'ID de cotización',
    medio ENUM('email', 'whatsapp', 'sms') NOT NULL COMMENT 'Medio de envío',
    destinatario VARCHAR(255) NOT NULL COMMENT 'Email o teléfono destino',
    estado ENUM('enviado', 'pendiente', 'fallido', 'leido') DEFAULT 'pendiente' COMMENT 'Estado envío',
    numeroIntento INT DEFAULT 0 COMMENT 'Número de intentos',
    respuestaDestino VARCHAR(500) COMMENT 'Respuesta del servidor',
    fechaEnvio TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (cotizacionId) REFERENCES COTIZACIONES(id) ON DELETE CASCADE,
    INDEX idx_cotizacionId (cotizacionId),
    INDEX idx_estado (estado),
    INDEX idx_fechaEnvio (fechaEnvio)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
COMMENT='Registro de envíos de cotizaciones';

-- ============================================================
-- INSERTS DE DATOS INICIALES
-- ============================================================

-- Empresas
INSERT INTO EMPRESAS (ruc, razonSocial, direccion, telefonoEmpresa, estado) VALUES
('20123456789', 'Constructora ACME S.A.C.', 'Av. Principal 123, Lima', '01-2345678', 'activo'),
('20987654321', 'Ingeniería Moderna E.I.R.L.', 'Calle 2 456, Lima', '01-9876543', 'activo'),
('20111222333', 'Proyectos Andinos S.A.', 'Jr. 3 789, Arequipa', '054-1234567', 'activo');

-- Personas
INSERT INTO PERSONAS (dni, nombre, apellido, celular, email, empresaAsociada) VALUES
('12345678', 'Juan', 'García López', '987654321', 'juan.personal@email.com', NULL),
('98765432', 'Roberto', 'Martínez Ruiz', '987111222', 'roberto@email.com', NULL),
('55667788', 'Sofía', 'Fernández Torres', '987222333', 'sofia@email.com', NULL);

-- Contactos
INSERT INTO CONTACTOS (id, empresaRuc, dni, nombre, apellido, cargo, celular, email) VALUES
('C001', '20123456789', '12345678', 'Juan', 'García López', 'Gerente Proyectos', '987654321', 'juan@acme.com'),
('C002', '20123456789', '87654321', 'María', 'Rodríguez Silva', 'Asistente', '987123456', 'maria@acme.com'),
('C003', '20987654321', '11223344', 'Carlos', 'Pérez Martínez', 'Director', '987456789', 'carlos@moderna.com'),
('C004', '20111222333', '44556677', 'Ana', 'López García', 'Coordinadora', '987789012', 'ana@andinos.com');

-- Ensayos
INSERT INTO ENSAYOS_CATALOGO (id, nombre, descripcion, norma, precioBase, unidad, categoria, tiempo_estimado, activo) VALUES
('E001', 'Resistencia a la Compresión', 'Ensayo de compresión en probetas de concreto', 'NTP 339.034', 150.00, 'por muestra', 'concreto', '7 días', true),
('E002', 'Módulo de Rotura', 'Ensayo de flexión en vigas', 'NTP 339.079', 200.00, 'por muestra', 'concreto', '7 días', true),
('E003', 'Densidad y Absorción', 'Ensayo para agregados', 'NTP 400.021', 120.00, 'por muestra', 'agregados', '3 días', true),
('E004', 'Análisis Granulométrico', 'Tamizado de agregados', 'NTP 400.012', 100.00, 'por muestra', 'agregados', '2 días', true),
('E005', 'Contenido de Humedad', 'Humedad en agregados', 'NTP 400.011', 80.00, 'por muestra', 'agregados', '1 día', true),
('E006', 'Revenimiento (Slump)', 'Medida de consistencia', 'NTP 339.114', 50.00, 'por muestra', 'concreto', '1 día', true);

-- Paquetes
INSERT INTO PAQUETES_CATALOGO (id, nombre, descripcion, ensayosIncluidos, precioBase, descuento_porcentaje, activo) VALUES
('P001', 'Paquete Básico Concreto', 'Ensayos esenciales para control de concreto', '["E001", "E006"]', 350.00, 5.00, true),
('P002', 'Paquete Completo Agregados', 'Análisis completo de agregados', '["E003", "E004", "E005"]', 280.00, 10.00, true),
('P003', 'Paquete Premium Concreto', 'Análisis estructural completo', '["E001", "E002", "E006"]', 400.00, 8.00, true);

-- Plantillas (3 modelos)
INSERT INTO PLANTILLAS (id, nombre, descripcion, nombreEmpresa, logoUrl, telefonoEmpresa, emailEmpresa, direccionEmpresa, terminosCondiciones, condicionesPago, colorPrimario, colorSecundario) VALUES
('PLANT001', 'Plantilla Estándar', 'Plantilla estándar para cotizaciones', 'Laboratorio de Ensayos GTQC', '/logo-default.png', '01-2345678', 'info@laboratorio.com', 'Av. Principal 123, Lima', 'Términos y condiciones estándar. Validez de 30 días. Sujeto a cambios sin previo aviso.', 'Pago contra entrega. Aceptamos transferencia bancaria, cheque o efectivo.', '#6366f1', '#8b5cf6'),
('PLANT002', 'Plantilla Premium', 'Plantilla para clientes premium', 'Laboratorio de Ensayos GTQC - Premium', '/logo-premium.png', '01-2345678', 'premium@laboratorio.com', 'Av. Principal 123, Lima', 'Términos y condiciones premium. Validez de 60 días. Servicio prioritario incluido.', 'Crédito a 30 días para clientes calificados. Descuentos por volumen.', '#8b5cf6', '#6366f1'),
('PLANT003', 'Plantilla Corporativo', 'Plantilla para grandes proyectos', 'Laboratorio de Ensayos GTQC - Corporativo', '/logo-corporate.png', '01-2345678', 'corporate@laboratorio.com', 'Av. Principal 123, Lima', 'Términos y condiciones corporativos. Validez de 90 días. Auditoría ISO incluida.', 'Crédito a 60 días. Presupuesto personalizado. Servicio técnico dedicado.', '#1a1a2e', '#6366f1');

-- ============================================================
-- VISTAS ÚTILES
-- ============================================================

-- Vista: Resumen de Cotización
CREATE VIEW VW_RESUMEN_COTIZACION AS
SELECT
    c.id as cotizacionId,
    c.numeroSerie,
    CASE
        WHEN c.clienteRuc IS NOT NULL THEN e.razonSocial
        ELSE CONCAT(p.nombre, ' ', p.apellido)
    END as clienteNombre,
    COALESCE(c.clienteRuc, c.clienteDni) as clienteId,
    c.nombreProyecto,
    c.validezDias,
    c.estado,
    c.fechaCreacion,
    SUM(ci.subtotal) as subtotalItems,
    COALESCE(d.montoDescuento, 0) as descuentoTotal,
    (SUM(ci.subtotal) - COALESCE(d.montoDescuento, 0)) * 1.18 as totalConIGV
FROM COTIZACIONES c
LEFT JOIN EMPRESAS e ON c.clienteRuc = e.ruc
LEFT JOIN PERSONAS p ON c.clienteDni = p.dni
LEFT JOIN COTIZACION_ITEMS ci ON c.id = ci.cotizacionId
LEFT JOIN DESCUENTOS d ON c.id = d.cotizacionId
GROUP BY c.id, c.numeroSerie, c.estado, c.fechaCreacion;

-- Vista: Ensayos con Normas
CREATE VIEW VW_ENSAYOS_DISPONIBLES AS
SELECT
    id,
    nombre,
    descripcion,
    norma,
    precioBase,
    unidad,
    categoria,
    tiempo_estimado,
    CONCAT(nombre, ' (', norma, ')') as nombreCompleto
FROM ENSAYOS_CATALOGO
WHERE activo = true
ORDER BY categoria, nombre;

-- ============================================================
-- ÍNDICES ADICIONALES PARA PERFORMANCE
-- ============================================================

CREATE INDEX idx_cot_cliente ON COTIZACIONES(clienteRuc, clienteDni);
CREATE INDEX idx_cot_items_cotizacion ON COTIZACION_ITEMS(cotizacionId);
CREATE INDEX idx_desc_cotizacion ON DESCUENTOS(cotizacionId);

-- ============================================================
-- STORED PROCEDURES
-- ============================================================

-- Procedure: Calcular Total Cotización
DELIMITER $$

CREATE PROCEDURE SP_CALCULAR_TOTAL_COTIZACION(
    IN p_cotizacionId VARCHAR(36),
    OUT p_subtotal DECIMAL(12, 2),
    OUT p_descuento DECIMAL(12, 2),
    OUT p_neto DECIMAL(12, 2),
    OUT p_igv DECIMAL(12, 2),
    OUT p_total DECIMAL(12, 2)
)
BEGIN
    SELECT COALESCE(SUM(subtotal), 0) INTO p_subtotal
    FROM COTIZACION_ITEMS
    WHERE cotizacionId = p_cotizacionId;

    SELECT COALESCE(montoDescuento, 0) INTO p_descuento
    FROM DESCUENTOS
    WHERE cotizacionId = p_cotizacionId;

    SET p_neto = p_subtotal - p_descuento;
    SET p_igv = p_neto * 0.18;
    SET p_total = p_neto + p_igv;
END$$

DELIMITER ;

-- ============================================================
-- CONFIGURACIÓN DE SEGURIDAD
-- ============================================================

-- Crear usuario de aplicación con permisos limitados
CREATE USER IF NOT EXISTS 'app_cotizador'@'localhost' IDENTIFIED BY 'Cotizador2024!';
GRANT SELECT ON cotizador_laboratorio.* TO 'app_cotizador'@'localhost';
GRANT INSERT, UPDATE ON cotizador_laboratorio.COTIZACIONES TO 'app_cotizador'@'localhost';
GRANT INSERT, UPDATE ON cotizador_laboratorio.COTIZACION_ITEMS TO 'app_cotizador'@'localhost';
GRANT INSERT ON cotizador_laboratorio.COTIZACION_DESCARGAS TO 'app_cotizador'@'localhost';
GRANT INSERT ON cotizador_laboratorio.COTIZACION_ENVIOS TO 'app_cotizador'@'localhost';

-- ============================================================
-- FIN DEL SCRIPT
-- ============================================================
