/* =====================================================================
   PROYECTO FINAL - ADMINISTRACION DE BASES DE DATOS

   -------------------------------------------------
   Integrantes:

   Heberto Johalmo Estrada Hernandez    00138821
   Herberth Ariel Tobar Sermeño         00158525
   Ricardo Alexei Valle Avalos          00080525
   Jennifer Liseth Canales Pérez        00160223
   Chelsea Sayuri Mejia Vasquez         00164523
   ================================================================
  */
-- BASE DE DATOS
USE master;
GO

IF DB_ID('HospitalDB') IS NOT NULL
BEGIN
    ALTER DATABASE HospitalDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE HospitalDB;
END
GO

IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_recepcion')    DROP LOGIN lg_recepcion;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_medico')       DROP LOGIN lg_medico;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_contabilidad') DROP LOGIN lg_contabilidad;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_powerbi')      DROP LOGIN lg_powerbi;
GO

CREATE DATABASE HospitalDB
ON PRIMARY
(
    NAME = HospitalDB_data,
    FILENAME = '/var/opt/mssql/data/HospitalDB.mdf',
    SIZE = 100MB,
    FILEGROWTH = 50MB
)
LOG ON
(
    NAME = HospitalDB_log,
    FILENAME = '/var/opt/mssql/data/HospitalDB_log.ldf',
    SIZE = 50MB,
    FILEGROWTH = 25MB
);
GO

-- FULL para poder hacer backups de log 
ALTER DATABASE HospitalDB SET RECOVERY FULL;
GO

USE HospitalDB;
GO

-- ESQUEMAS 
CREATE SCHEMA catalogo    AUTHORIZATION dbo;
GO
CREATE SCHEMA clinico     AUTHORIZATION dbo;
GO
CREATE SCHEMA facturacion AUTHORIZATION dbo;
GO
CREATE SCHEMA reportes    AUTHORIZATION dbo;
GO
CREATE SCHEMA auditoria   AUTHORIZATION dbo;
GO

-- TABLAS


CREATE TABLE catalogo.Especialidades (
    EspecialidadID  INT IDENTITY(1,1) NOT NULL,
    Nombre          VARCHAR(100) NOT NULL,
    Descripcion     VARCHAR(255) NULL,
    CONSTRAINT PK_Especialidades        PRIMARY KEY (EspecialidadID),
    CONSTRAINT UQ_Especialidades_Nombre UNIQUE (Nombre)
);
GO


CREATE TABLE catalogo.Diagnosticos (
    DiagnosticoID      INT IDENTITY(1,1) NOT NULL,
    Nombre_Diagnostico VARCHAR(255) NOT NULL,
    Descripcion        VARCHAR(MAX) NULL,
    CONSTRAINT PK_Diagnosticos        PRIMARY KEY (DiagnosticoID),
    CONSTRAINT UQ_Diagnosticos_Nombre UNIQUE (Nombre_Diagnostico)
);
GO

CREATE TABLE clinico.Pacientes (
    PacienteID        INT IDENTITY(1,1) NOT NULL,
    Nombre_Paciente   VARCHAR(100) NOT NULL,
    Apellido_Paciente VARCHAR(100) NOT NULL,
    FechaNacimiento   DATE NOT NULL,
    Telefono          VARCHAR(15) NULL,
    Email             VARCHAR(100) NULL,
    FechaRegistro     DATETIME NOT NULL CONSTRAINT DF_Pacientes_FechaRegistro DEFAULT (GETDATE()),
    CONSTRAINT PK_Pacientes       PRIMARY KEY (PacienteID),
    CONSTRAINT UQ_Pacientes_Email UNIQUE (Email)
);
GO

CREATE TABLE clinico.Medicos (
    MedicoID        INT IDENTITY(1,1) NOT NULL,
    Nombre_Medico   VARCHAR(100) NOT NULL,
    Apellido_Medico VARCHAR(100) NOT NULL,
    EspecialidadID  INT NOT NULL,
    LicenciaMedica  VARCHAR(50) NOT NULL,
    Email           VARCHAR(100) NULL,
    CONSTRAINT PK_Medicos           PRIMARY KEY (MedicoID),
    CONSTRAINT UQ_Medicos_Licencia  UNIQUE (LicenciaMedica),
    CONSTRAINT UQ_Medicos_Email     UNIQUE (Email),
    CONSTRAINT FK_Medicos_Especialidades
        FOREIGN KEY (EspecialidadID) REFERENCES catalogo.Especialidades (EspecialidadID)
);
GO

CREATE TABLE clinico.Citas (
    CitaID     INT IDENTITY(1,1) NOT NULL,
    PacienteID INT NOT NULL,
    MedicoID   INT NOT NULL,
    FechaHora  DATETIME NOT NULL,
    Estado     VARCHAR(20) NOT NULL CONSTRAINT DF_Citas_Estado DEFAULT ('Pendiente'),
    CONSTRAINT PK_Citas PRIMARY KEY (CitaID),
    CONSTRAINT CK_Citas_Estado CHECK (Estado IN ('Pendiente', 'Completada', 'Cancelada')),
    CONSTRAINT FK_Citas_Pacientes FOREIGN KEY (PacienteID) REFERENCES clinico.Pacientes (PacienteID),
    CONSTRAINT FK_Citas_Medicos   FOREIGN KEY (MedicoID)   REFERENCES clinico.Medicos (MedicoID)
);
GO

CREATE TABLE clinico.Tratamientos (
    TratamientoID INT IDENTITY(1,1) NOT NULL,
    CitaID        INT NOT NULL,
    DiagnosticoID INT NOT NULL,
    Indicaciones  VARCHAR(MAX) NULL,
    Costo         DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_Tratamientos PRIMARY KEY (TratamientoID),
    CONSTRAINT CK_Tratamientos_Costo CHECK (Costo >= 0),
    CONSTRAINT FK_Tratamientos_Citas        FOREIGN KEY (CitaID)        REFERENCES clinico.Citas (CitaID),
    CONSTRAINT FK_Tratamientos_Diagnosticos FOREIGN KEY (DiagnosticoID) REFERENCES catalogo.Diagnosticos (DiagnosticoID)
);
GO

-- MontoTotal ya no se almacena: se calcula como SUM(DetalleFactura.Subtotal)
CREATE TABLE facturacion.Facturacion (
    FacturaID    INT IDENTITY(1,1) NOT NULL,
    CitaID       INT NOT NULL,
    FechaEmision DATETIME NOT NULL CONSTRAINT DF_Facturacion_FechaEmision DEFAULT (GETDATE()),
    EstadoPago   VARCHAR(20) NOT NULL CONSTRAINT DF_Facturacion_EstadoPago DEFAULT ('Pendiente'),
    CONSTRAINT PK_Facturacion PRIMARY KEY (FacturaID),
    CONSTRAINT UQ_Facturacion_Cita UNIQUE (CitaID),
    CONSTRAINT CK_Facturacion_EstadoPago CHECK (EstadoPago IN ('Pendiente', 'Pagado')),
    CONSTRAINT FK_Facturacion_Citas FOREIGN KEY (CitaID) REFERENCES clinico.Citas (CitaID)
);
GO

-- Subtotal es columna calculada (evita dato derivado almacenado a mano)
CREATE TABLE facturacion.DetalleFactura (
    DetalleFacturaID INT IDENTITY(1,1) NOT NULL,
    FacturaID        INT NOT NULL,
    Concepto         VARCHAR(255) NOT NULL,
    Cantidad         INT NOT NULL,
    PrecioUnitario   DECIMAL(10,2) NOT NULL,
    Subtotal AS CAST(Cantidad * PrecioUnitario AS DECIMAL(10,2)) PERSISTED,
    CONSTRAINT PK_DetalleFactura PRIMARY KEY (DetalleFacturaID),
    CONSTRAINT CK_DetalleFactura_Cantidad CHECK (Cantidad > 0),
    CONSTRAINT CK_DetalleFactura_Precio   CHECK (PrecioUnitario >= 0),
    CONSTRAINT FK_DetalleFactura_Facturacion FOREIGN KEY (FacturaID) REFERENCES facturacion.Facturacion (FacturaID)
);
GO

-- Aqui le agrego los datos quemados xd
SET DATEFORMAT ymd;   -- evita errores de fecha segun el idioma del login
GO

-- Catalogos
INSERT INTO catalogo.Especialidades (Nombre) VALUES
('Cardiología'),
('Pediatría'),
('Cirugía Plástica'),
('Nutricionista'),
('Psiquiatría'),
('Neurología'),
('Medicina Interna'),
('Otorrinolaringología'),
('Urología'),
('Obstetricia y Ginecología'),
('Nefrología'),
('Medicina General'),
('Dermatología'),
('Traumatología y Ortopedia'),
('Oftalmología'),
('Oncología Médica'),
('Endocrinología Pediátrica'),
('Neumología'),
('Reumatología'),
('Geriatría'),
('Infectología'),
('Anestesiología');
GO

INSERT INTO catalogo.Diagnosticos (Nombre_Diagnostico) VALUES
('Hipertensión Leve'),
('Control de Crecimiento'),
('Evaluación Rinoplástica'),
('Evaluación Nutricional'),
('Evaluación Neuropsiquiátrica'),
('Control Internista'),
('Infección Nasofaríngea'),
('Infección Urinaria Baja'),
('Chequeo Ginecológico'),
('Evaluación de Función Renal'),
('Control de Rutina'),
('Dermatitis Atópica'),
('Esguince de Tobillo Grado 1'),
('Evaluación Oncológica de Control'),
('Diabetes Infantil Tipo 1'),
('Bronquitis Aguda'),
('Artritis Reumatoide'),
('Control Gerotológico'),
('Evaluación de Cuadro Febril'),
('Evaluación Preanestésica'),
('Arrhythmia Sinusal'),
('Rinitis Alérgica Infantil'),
('Revisión Postquirúrgica'),
('Control de Peso y Grasa Corporal'),
('Trastorno de Ansiedad Generalizada'),
('Migraña Crónica'),
('Otitis Media Aguda'),
('Cálculos Renales Pequeños'),
('Control Prenatal - Primer Trimestre'),
('Insuficiencia Renal Leve'),
('Chequeo General Preventivo'),
('Acné Vulgar Moderado'),
('Lumbalgia Mecánica'),
('Astigmatismo Miópico'),
('Seguimiento Oncológico'),
('Déficit de Crecimiento'),
('Asma Bronquial Severa'),
('Osteoartritis de Rodilla'),
('Deterioro Cognitivo Leve'),
('Evaluación Sedación Consciente'),
('Cardiopatía Isquémica Estable'),
('Faringitis Estreptocócica'),
('Corrección de Cicatriz'),
('Intolerancia a la Lactosa'),
('Depresión Leve'),
('Neuropatía Periférica'),
('Síndrome Metabólico'),
('Sinusitis Crónica'),
('Infección de Vías Urinarias'),
('Sindrome de Ovario Poliquístico'),
('Glomerulonefritis'),
('Examen Médico Laboral'),
('Eczema Nummular'),
('Bursitis de Hombro'),
('Glaucoma Primario de Ángulo Abierto'),
('Sospecha de Linfoma'),
('Crisis Asmática Leve'),
('Fibromialgia'),
('Síndrome Frágil del Anciano'),
('Síndrome Febril a Estudio'),
('Evaluación Anestésica para Cirugía'),
('Hipertensión Arterial Grado 2'),
('Parasitosis Intestinal Pediátrica'),
('Valoración de Liposucción'),
('Hígado Graso No Alcohólico'),
('Insomnio Crónico'),
('Accidente Cerebrovascular (Secuelas)'),
('Consulta de Control Diabético'),
('Poliposis Nasal'),
('Prostatitis Benigna'),
('Control de Discapacidad Ginecología'),
('Proteinuria Aislada'),
('Chequeo Anual de Salud'),
('Psoriasis en Placas'),
('Tendinitis Rotuliana'),
('Catarata Senil Bilateral'),
('Seguimiento Quimioterapia'),
('Hipotiroidismo Congénito'),
('Enfermedad Pulmonar Obstructiva (EPOC)'),
('Lupus Eritematoso Sistémico'),
('Control de Hipertensión en Adulto Mayor'),
('Infección Viral Aguda'),
('Valoración Sedación Odontológica'),
('Insuficiencia Cardíaca Congestiva'),
('Deshidratación Moderada Pediátrica'),
('Reconstrucción Mamaria Post-Mastectomía'),
('Desnutrición Calórico-Proteica'),
('Crisis de Pánico'),
('Epilepsia Focal Controlada'),
('Neumonía Adquirida en la Comunidad'),
('Traumatismo Acústico'),
('Infección Urinaria Recurrente'),
('Control Menopáusico'),
('Litiasis Renal'),
('Evaluación de Estado Físico'),
('Micosis Cutánea'),
('Ruptura de Menisco Interno'),
('Conjuntivitis Bacteriana'),
('Evaluación de Nódulo Mamario'),
('Obesidad Infantil'),
('Apnea Obstructiva del Sueño'),
('Espondilitis Anquilosante'),
('Evaluación de Memoria'),
('Control de Varicela'),
('Chequeo Preoperatorio'),
('Evaluación de Soplos Cardiacos'),
('Dermatitis del Pañal'),
('Mamoplastia de Reducción'),
('Control de Síndrome Anémico'),
('Trastorno Adaptativo');
GO

-- Pacientes
INSERT INTO clinico.Pacientes (Nombre_Paciente, Apellido_Paciente, FechaNacimiento, Telefono, Email) VALUES
('Carlos', 'Martínez', '1985-04-12', '7894-1234', 'carlos.martinez@email.com'),
('María', 'Hernández', '1990-07-22', '7211-5588', 'maria.hernandez@email.com'),
('Juan', 'López', '1965-11-05', '7633-9911', 'juan.lopez@email.com'),
('Ana', 'Rodríguez', '2004-02-19', '7544-2233', 'ana.rodriguez@email.com'),
('Pedro', 'Sánchez', '1978-09-30', '7199-8877', 'pedro.sanchez@email.com'),
('Sofía', 'Gómez', '1995-05-14', '7322-1144', 'sofia.gomez@email.com'),
('Luis', 'Pérez', '2012-12-03', '7455-6688', 'luis.perez@email.com'),
('Carmen', 'Jiménez', '1958-08-25', '7911-3322', 'carmen.jimenez@email.com'),
('José', 'Ruiz', '2001-01-17', '7233-4455', 'jose.ruiz@email.com'),
('Lucía', 'Álvarez', '1989-06-21', '7688-9900', 'lucia.alvarez@email.com'),
('Miguel', 'Moreno', '2016-03-09', '7144-5566', 'miguel.moreno@email.com'),
('Elena', 'Muñoz', '1973-10-11', '7855-2211', 'elena.munoz@email.com'),
('Francisco', 'Alonso', '1998-07-30', '7399-8811', 'francisco.alonso@email.com'),
('Laura', 'Gutiérrez', '2005-09-15', '7511-7766', 'laura.gutierrez@email.com'),
('Alejandro', 'Romero', '1982-04-28', '7722-3344', 'alejandro.romero@email.com'),
('Paula', 'Navarro', '2010-11-19', '7488-1122', 'paula.navarro@email.com'),
('David', 'Torres', '1968-02-05', '7933-6655', 'david.torres@email.com'),
('Beatriz', 'Domínguez', '1993-08-12', '7244-9988', 'beatriz.dominguez@email.com'),
('Jorge', 'Vázquez', '2002-05-23', '7611-2233', 'jorge.vazquez@email.com'),
('Teresa', 'Ramos', '1955-12-14', '7188-4455', 'teresa.ramos@email.com'),
('Manuel', 'Gil', '1991-01-30', '7833-1199', 'manuel.gil@email.com'),
('Raquel', 'Serrano', '2007-06-08', '7355-6622', 'raquel.serrano@email.com'),
('Antonio', 'Blanco', '1984-10-27', '7599-4411', 'antonio.blanco@email.com'),
('Marta', 'Molina', '2015-03-16', '7744-8833', 'marta.molina@email.com'),
('Javier', 'Morales', '1970-07-01', '7211-9966', 'javier.morales@email.com'),
('Claudia', 'Suárez', '2000-11-24', '7655-3311', 'claudia.suarez@email.com'),
('Daniel', 'Ortega', '1988-04-18', '7133-7788', 'daniel.ortega@email.com'),
('Patricia', 'Delgado', '1962-09-07', '7822-5544', 'patricia.delgado@email.com'),
('Rubén', 'Castro', '2011-02-12', '7411-8899', 'ruben.castro@email.com'),
('Silvia', 'Ortiz', '1997-05-29', '7966-2211', 'silvia.ortiz@email.com'),
('Alberto', 'Rubio', '1976-12-05', '7388-1155', 'alberto.rubio@email.com'),
('Rosa', 'Marín', '2003-08-20', '7522-6633', 'rosa.marin@email.com'),
('Fernando', 'Sanz', '1981-01-15', '7799-3377', 'fernando.sanz@email.com'),
('Beatriz', 'Nuñez', '2014-06-11', '7266-4488', 'beatriz.nunez@email.com'),
('Ricardo', 'Iglesias', '1969-10-02', '7644-7722', 'ricardo.iglesias@email.com'),
('Andrea', 'Medina', '1994-03-25', '7155-9944', 'andrea.medina@email.com'),
('Gonzalo', 'Garrido', '2006-07-19', '7811-2266', 'gonzalo.garrido@email.com'),
('Natalia', 'Cortés', '1979-11-08', '7433-5511', 'natalia.cortes@email.com'),
('Héctor', 'Castillo', '1992-04-03', '7922-8833', 'hector.castillo@email.com'),
('Irene', 'Santos', '2008-09-14', '7344-6677', 'irene.santos@email.com'),
('Mario', 'Lozano', '1960-12-28', '7588-1199', 'mario.lozano@email.com'),
('Sara', 'Cano', '1985-05-06', '7711-4422', 'sara.cano@email.com'),
('Víctor', 'Cruz', '2001-02-17', '7299-7755', 'victor.cruz@email.com'),
('Mónica', 'Prieto', '1975-08-31', '7633-2288', 'monica.prieto@email.com'),
('Sergio', 'Flores', '1999-10-22', '7166-5533', 'sergio.flores@email.com'),
('Lorena', 'Cabrera', '2010-01-09', '7844-9911', 'lorena.cabrera@email.com'),
('Adrián', 'Campos', '1967-06-13', '7422-3366', 'adrian.campos@email.com'),
('Noelia', 'Vega', '1990-03-04', '7955-1177', 'noelia.vega@email.com'),
('Iván', 'Diez', '2004-09-26', '7311-6644', 'ivan.diez@email.com'),
('Yolanda', 'Fuentes', '1983-11-18', '7577-8822', 'yolanda.fuentes@email.com'),
('Óscar', 'Velasco', '2013-04-15', '7733-2255', 'oscar.velasco@email.com'),
('Miriam', 'Pascual', '1959-07-27', '7288-5511', 'miriam.pascual@email.com'),
('Gabriel', 'Herrero', '1996-02-10', '7622-9944', 'gabriel.herrero@email.com'),
('Rocío', 'Montero', '2005-12-01', '7144-3377', 'rocio.montero@email.com'),
('Marcos', 'Hidalgo', '1972-05-19', '7866-7788', 'marcos.hidalgo@email.com'),
('Eva', 'Giménez', '1988-08-23', '7499-1133', 'eva.gimenez@email.com'),
('Emilio', 'Ibáñez', '2009-10-12', '7911-4466', 'emilio.ibanez@email.com'),
('Alicia', 'Ferrer', '1966-01-30', '7333-8855', 'alicia.ferrer@email.com'),
('Raúl', 'Durán', '1993-06-07', '7566-2299', 'raul.duran@email.com'),
('Clara', 'Vicente', '2002-09-21', '7788-5544', 'clara.vicente@email.com'),
('Enrique', 'Benítez', '1977-03-11', '7255-1122', 'enrique.benitez@email.com'),
('Beatriz', 'Santiago', '1991-11-15', '7699-6633', 'beatriz.santiago@email.com'),
('Felipe', 'Vargas', '2011-07-04', '7122-4488', 'felipe.vargas@email.com'),
('Natalia', 'Arias', '1957-02-28', '7833-7711', 'natalia.arias@email.com'),
('Alfonso', 'Carmona', '1980-12-19', '7466-9955', 'alfonso.carmona@email.com'),
('Lidia', 'Crespo', '2000-05-10', '7944-3322', 'lidia.crespo@email.com'),
('Esteban', 'Román', '1986-10-06', '7322-5577', 'esteban.roman@email.com'),
('Sonia', 'Pastor', '2015-01-25', '7511-8866', 'sonia.pastor@email.com'),
('Bruno', 'Soto', '1964-06-14', '7755-1144', 'bruno.soto@email.com'),
('Carla', 'Saez', '1995-09-02', '7211-6633', 'carla.saez@email.com'),
('Gonzalo', 'Vera', '2007-04-20', '7677-4499', 'gonzalo.vera@email.com'),
('Daniela', 'Medrano', '1983-12-11', '7199-2255', 'daniela.medrano@email.com'),
('Guillermo', 'Bravo', '2000-08-08', '7844-6611', 'guillermo.bravo@email.com'),
('Ainhoa', 'Gallardo', '1974-03-17', '7433-8822', 'ainhoa.gallardo@email.com'),
('Samuel', 'Esteban', '1992-07-29', '7922-5533', 'samuel.esteban@email.com'),
('Valeria', 'Nieto', '2012-11-03', '7366-1188', 'valeria.nieto@email.com'),
('Damián', 'Parra', '1969-02-14', '7588-3344', 'damian.parra@email.com'),
('Rebeca', 'Calvo', '1989-05-22', '7711-7722', 'rebeca.calvo@email.com'),
('Cristian', 'Mendoza', '2004-10-30', '7244-2299', 'cristian.mendoza@email.com'),
('Monica', 'Aguilar', '1981-01-12', '7655-9966', 'monica.aguilar@email.com'),
('Mauricio', 'Otero', '2010-06-19', '7133-4411', 'mauricio.otero@email.com'),
('Jimena', 'Blanes', '1956-09-25', '7822-7755', 'jimena.blanes@email.com'),
('Leonardo', 'Pardo', '1998-04-07', '7411-1188', 'leonardo.pardo@email.com'),
('Tatiana', 'Riquelme', '2006-11-20', '7966-6633', 'tatiana.riquelme@email.com'),
('Agustín', 'Bermúdez', '1971-03-15', '7388-3377', 'agustin.bermudez@email.com'),
('Renata', 'Zamorano', '1990-08-28', '7522-5522', 'renata.zamorano@email.com'),
('Facundo', 'Peralta', '2008-12-05', '7799-8844', 'facundo.peralta@email.com'),
('Florencia', 'Acosta', '1965-05-18', '7266-1111', 'florencia.acosta@email.com'),
('Joaquín', 'Silva', '1987-10-01', '7644-4499', 'joaquin.silva@email.com'),
('Camila', 'Rojas', '2001-02-23', '7155-7733', 'camila.rojas@email.com'),
('Luciano', 'Maldonado', '1976-07-11', '7811-2288', 'luciano.maldonado@email.com'),
('Martina', 'Contreras', '1997-11-29', '7433-6644', 'martina.contreras@email.com'),
('Mateo', 'Sepúlveda', '2016-04-16', '7922-9911', 'mateo.sepulveda@email.com'),
('Catalina', 'Fuenzalida', '1982-09-08', '7344-3355', 'catalina.fuenzalida@email.com'),
('Vicente', 'Aravena', '2003-01-22', '7588-8866', 'vicente.aravena@email.com'),
('Antonia', 'Quezada', '1970-06-14', '7711-1177', 'antonia.quezada@email.com'),
('Benjamín', 'Espinoza', '1994-10-27', '7299-4422', 'benjamin.espinoza@email.com'),
('Julieta', 'Valenzuela', '2011-03-05', '7633-7755', 'julieta.valenzuela@email.com'),
('Dante', 'Navarrete', '1963-08-19', '7166-2288', 'dante.navarrete@email.com'),
('Emilia', 'Salazar', '1986-12-02', '7844-5533', 'emilia.salazar@email.com'),
('Lucas', 'Pineda', '2019-05-10', '7933-1122', 'lucas.pineda@email.com'),
('Valeria', 'Rivas', '2022-02-14', '7211-9988', 'valeria.rivas@email.com'),
('Diego', 'Morales', '1974-05-12', '7123-4411', 'diego.morales.new@email.com'),
('Valeria', 'Castro', '2003-09-14', '7456-8822', 'valeria.castro.new@email.com'),
('Mateo', 'Benítez', '1961-03-22', '7789-1133', 'mateo.benitez.new@email.com'),
('Abigail', 'Vargas', '2015-08-01', '7234-5544', 'abigail.vargas.new@email.com'),
('Samuel', 'Rivas', '1988-12-11', '7567-9955', 'samuel.rivas.new@email.com'),
('Gabriela', 'Paz', '1999-02-28', '7890-2266', 'gabriela.paz.new@email.com'),
('Esteban', 'Duarte', '2007-07-04', '7345-6677', 'esteban.duarte.new@email.com'),
('Jimena', 'Mejía', '1954-10-19', '7678-3388', 'jimena.mejia.new@email.com'),
('Lucas', 'Silva', '2018-01-30', '7112-4499', 'lucas.silva.new@email.com'),
('Martina', 'Campos', '1992-06-15', '7445-5511', 'martina.campos.new@email.com'),
('Facundo', 'Guevara', '1980-04-05', '7778-6622', 'facundo.guevara.new@email.com'),
('Renata', 'Portillo', '2004-11-20', '7223-7733', 'renata.portillo.new@email.com'),
('Agustín', 'Hasbún', '1968-08-14', '7556-8844', 'agustin.hasbun.new@email.com'),
('Florencia', 'Carpio', '2012-03-09', '7889-9955', 'florencia.carpio.new@email.com'),
('Joaquín', 'Carpio', '1995-07-25', '7334-1166', 'joaquin.carpio.new@email.com'),
('Camila', 'Guerra', '2001-10-31', '7667-2277', 'camila.guerra.new@email.com'),
('Luciano', 'Vasquez', '1975-01-18', '7111-3388', 'luciano.vasquez.new@email.com'),
('Antonia', 'Castillo', '2010-05-12', '7444-4499', 'antonia.castillo.new@email.com'),
('Benjamín', 'Blanco', '1986-09-03', '7777-5511', 'benjamin.blanco.new@email.com'),
('Julieta', 'Alonso', '2005-12-27', '7222-6622', 'julieta.alonso.new@email.com'),
('Dante', 'Navarro', '1959-02-14', '7555-7733', 'dante.navarro.new@email.com'),
('Emilia', 'Torres', '2016-06-08', '7888-8844', 'emilia.torres.new@email.com'),
('Bruno', 'Domínguez', '1991-03-19', '7333-9955', 'bruno.dominguez.new@email.com'),
('Carla', 'Ramos', '2008-08-22', '7666-1166', 'carla.ramos.new@email.com'),
('Gonzalo', 'Gil', '1972-11-06', '7114-2277', 'gonzalo.gil.new@email.com'),
('Daniela', 'Serrano', '2002-04-17', '7447-3388', 'daniela.serrano.new@email.com'),
('Guillermo', 'Molina', '1965-07-10', '7770-4499', 'guillermo.molina.new@email.com'),
('Ainhoa', 'Morales', '2014-01-25', '7225-5511', 'ainhoa.morales.new@email.com'),
('Mauricio', 'Suárez', '1984-10-02', '7558-6622', 'mauricio.suarez.new@email.com'),
('Tatiana', 'Ortega', '1998-05-13', '7881-7733', 'tatiana.ortega.new@email.com'),
('Alfonso', 'Delgado', '2006-09-29', '7336-8844', 'alfonso.delgado.new@email.com'),
('Lidia', 'Castro', '1957-12-04', '7669-9955', 'lidia.castro.new@email.com'),
('Esteban', 'Ortiz', '2011-03-21', '7119-1166', 'esteban.ortiz.new@email.com'),
('Sonia', 'Rubio', '1989-06-16', '7442-2277', 'sonia.rubio.new@email.com'),
('Bruno', 'Marín', '2000-11-09', '7775-3388', 'bruno.marin.new@email.com'),
('Carla', 'Sanz', '1967-02-28', '7228-4499', 'carla.sanz.new@email.com'),
('Daniela', 'Nuñez', '2013-08-05', '7551-5511', 'daniela.nunez.new@email.com'),
('Guillermo', 'Iglesias', '1994-04-12', '7884-6622', 'guillermo.iglesias.new@email.com'),
('Ainhoa', 'Medina', '2009-10-18', '7337-7733', 'ainhoa.medina.new@email.com'),
('Mauricio', 'Garrido', '1979-01-07', '7660-8844', 'mauricio.garrido.new@email.com'),
('Tatiana', 'Cortés', '2001-07-30', '7113-9955', 'tatiana.cortes.new@email.com'),
('Alfonso', 'Castillo', '1963-05-24', '7446-1166', 'alfonso.castillo.new@email.com'),
('Lidia', 'Santos', '2017-09-11', '7779-2277', 'lidia.santos.new@email.com'),
('Esteban', 'Lozano', '1985-02-19', '7222-3388', 'esteban.lozano.new@email.com'),
('Sonia', 'Cano', '2004-06-03', '7555-4499', 'sonia.cano.new@email.com'),
('Bruno', 'Cruz', '1970-11-15', '7888-5511', 'bruno.cruz.new@email.com'),
('Carla', 'Prieto', '2012-04-20', '7333-6622', 'carla.prieto.new@email.com'),
('Daniela', 'Flores', '1996-08-07', '7666-7733', 'daniela.flores.new@email.com'),
('Guillermo', 'Cabrera', '2007-12-12', '7111-8844', 'guillermo.cabrera.new@email.com'),
('Ainhoa', 'Campos', '1952-03-31', '7444-9955', 'ainhoa.campos.new@email.com');
GO

-- Medicos
INSERT INTO clinico.Medicos (Nombre_Medico, Apellido_Medico, EspecialidadID, LicenciaMedica, Email) VALUES
('Dra. Elena', 'Rivas', 1, 'MED-98765', 'elena.rivas@hospital.com'),
('Dr. Roberto', 'Guevara', 2, 'MED-12345', 'roberto.guevara@hospital.com'),
('Dr. Steven', 'Mejia', 3, 'MED-96745', 'steven.mejia@hospital.com'),
('Dra. Margaret', 'Duarte', 4, 'MED-12935', 'margaret.duarte@hospital.com'),
('Dra. Kendall', 'Portillo', 5, 'MED-12346', 'kendall.portillo@hospital.com'),
('Dr. Andres', 'Vasquez', 6, 'MED-14352', 'andres.vasquez@hospital.com'),
('Dra. Nataly', 'Guerra', 7, 'MED-98766', 'nataly.guerra@hospital.com'),
('Dr. Josue', 'Carpio', 8, 'MED-76483', 'josue.carpio@hospital.com'),
('Dr. David', 'Vasquez', 9, 'MED-53724', 'david.vasquez@hospital.com'),
('Dra. Maura', 'Hasbun', 10, 'MED-64291', 'maura.hasbun@hospital.com'),
('Dr. Eduardo', 'Castillo', 11, 'MED-18573', 'eduardo.castillo@hospital.com'),
('Dra. Sofia', 'Blanco', 12, 'MED-54321', 'sofia.blanco@hospital.com'),
('Dr. Fernando', 'Linares', 13, 'MED-44112', 'fernando.linares@hospital.com'),
('Dra. Marcela', 'Fuentes', 14, 'MED-77883', 'marcela.fuentes@hospital.com'),
('Dr. Humberto', 'Salazar', 15, 'MED-33221', 'humberto.salazar@hospital.com'),
('Dra. Patricia', 'Mendoza', 16, 'MED-88994', 'patricia.mendoza@hospital.com'),
('Dr. Ricardo', 'Pineda', 17, 'MED-55667', 'ricardo.pineda@hospital.com'),
('Dra. Gabriela', 'Navas', 18, 'MED-22339', 'gabriela.navas@hospital.com'),
('Dr. Mauricio', 'Acosta', 19, 'MED-99001', 'mauricio.acosta@hospital.com'),
('Dra. Claudia', 'Zepeda', 20, 'MED-66778', 'claudia.zepeda@hospital.com'),
('Dr. Ernesto', 'Villalta', 21, 'MED-11224', 'ernesto.villalta@hospital.com'),
('Dra. Beatriz', 'Quijano', 22, 'MED-33445', 'beatriz.quijano@hospital.com');
GO

-- Citas
INSERT INTO clinico.Citas (PacienteID, MedicoID, FechaHora, Estado) VALUES
-- Septiembre Citas Completadas y Canceladas
(1, 1, '2026-09-01 08:00:00', 'Completada'),
(2, 2, '2026-09-01 08:30:00', 'Completada'),
(3, 3, '2026-09-01 09:15:00', 'Completada'),
(4, 4, '2026-09-01 10:00:00', 'Completada'),
(5, 5, '2026-09-02 08:00:00', 'Cancelada'),
(6, 6, '2026-09-02 09:30:00', 'Completada'),
(7, 7, '2026-09-02 10:45:00', 'Completada'),
(8, 8, '2026-09-02 11:30:00', 'Completada'),
(9, 9, '2026-09-03 08:15:00', 'Cancelada'),
(10, 10, '2026-09-03 09:00:00', 'Completada'),
(11, 11, '2026-09-03 10:30:00', 'Cancelada'),
(12, 12, '2026-09-03 14:00:00', 'Completada'),
(13, 13, '2026-09-04 08:30:00', 'Completada'),
(14, 14, '2026-09-04 09:15:00', 'Completada'),
(15, 15, '2026-09-04 10:00:00', 'Cancelada'),
(16, 16, '2026-09-05 08:00:00', 'Cancelada'),
(17, 17, '2026-09-05 09:30:00', 'Completada'),
(18, 18, '2026-09-05 11:00:00', 'Completada'),
(19, 19, '2026-09-07 08:15:00', 'Completada'),
(20, 20, '2026-09-07 09:45:00', 'Completada'),
(21, 21, '2026-09-07 10:30:00', 'Cancelada'),
(22, 22, '2026-09-07 14:15:00', 'Cancelada'),
(23, 1, '2026-09-08 08:00:00', 'Completada'),
(24, 2, '2026-09-08 09:00:00', 'Completada'),
(25, 3, '2026-09-08 10:30:00', 'Completada'),
(26, 4, '2026-09-09 08:30:00', 'Cancelada'),
(27, 5, '2026-09-09 09:15:00', 'Cancelada'),
(28, 6, '2026-09-09 11:00:00', 'Cancelada'),
(29, 7, '2026-09-10 08:00:00', 'Cancelada'),
(30, 8, '2026-09-10 09:30:00', 'Completada'),
(31, 9, '2026-09-10 10:15:00', 'Completada'),
(32, 10, '2026-09-11 08:45:00', 'Completada'),
(33, 11, '2026-09-11 09:30:00', 'Completada'),
(34, 12, '2026-09-11 11:15:00', 'Completada'),
(35, 13, '2026-09-14 08:00:00', 'Completada'),
(36, 14, '2026-09-14 09:00:00', 'Completada'),
(37, 15, '2026-09-14 10:30:00', 'Completada'),
(38, 16, '2026-09-15 08:30:00', 'Completada'),
(39, 17, '2026-09-15 09:15:00', 'Completada'),
(40, 18, '2026-09-15 11:00:00', 'Completada'),
(41, 19, '2026-09-16 08:00:00', 'Completada'),
(42, 20, '2026-09-16 09:30:00', 'Cancelada'),
(43, 21, '2026-09-16 10:45:00', 'Cancelada'),
(44, 22, '2026-09-17 08:15:00', 'Cancelada'),
(45, 1, '2026-09-17 09:00:00', 'Completada'),
(46, 2, '2026-09-17 10:30:00', 'Cancelada'),
(47, 3, '2026-09-18 08:30:00', 'Cancelada'),
(48, 4, '2026-09-18 09:15:00', 'Completada'),
(49, 5, '2026-09-18 11:00:00', 'Cancelada'),
(50, 6, '2026-09-21 08:00:00', 'Cancelada'),

-- Octubre Citas Completadas y Pendientes
(51, 7, '2026-10-01 08:30:00', 'Completada'),
(52, 8, '2026-10-01 09:15:00', 'Completada'),
(53, 9, '2026-10-01 10:00:00', 'Completada'),
(54, 10, '2026-10-02 08:00:00', 'Completada'),
(55, 11, '2026-10-02 09:30:00', 'Completada'),
(56, 12, '2026-10-02 11:00:00', 'Completada'),
(57, 13, '2026-10-05 08:15:00', 'Pendiente'),
(58, 14, '2026-10-05 09:00:00', 'Completada'),
(59, 15, '2026-10-05 10:30:00', 'Completada'),
(60, 16, '2026-10-06 08:30:00', 'Pendiente'),
(61, 17, '2026-10-06 09:15:00', 'Cancelada'),
(62, 18, '2026-10-06 11:00:00', 'Completada'),
(63, 19, '2026-10-07 08:00:00', 'Completada'),
(64, 20, '2026-10-07 09:30:00', 'Completada'),
(65, 21, '2026-10-07 10:45:00', 'Completada'),
(66, 22, '2026-10-08 08:15:00', 'Completada'),
(67, 1, '2026-10-08 09:00:00', 'Pendiente'),
(68, 2, '2026-10-08 10:30:00', 'Pendiente'),
(69, 3, '2026-10-09 08:30:00', 'Completada'),
(70, 4, '2026-10-09 09:15:00', 'Completada'),
(71, 5, '2026-10-09 11:00:00', 'Pendiente'),
(72, 6, '2026-10-12 08:00:00', 'Completada'),
(73, 7, '2026-10-12 09:30:00', 'Pendiente'),
(74, 8, '2026-10-12 10:45:00', 'Pendiente'),
(75, 9, '2026-10-13 08:15:00', 'Completada'),
(76, 10, '2026-10-13 09:00:00', 'Completada'),
(77, 11, '2026-10-13 10:30:00', 'Completada'),
(78, 12, '2026-10-14 08:30:00', 'Completada'),
(79, 13, '2026-10-14 09:15:00', 'Completada'),
(80, 14, '2026-10-14 11:00:00', 'Completada'),
(81, 15, '2026-10-15 08:00:00', 'Completada'),
(82, 16, '2026-10-15 09:30:00', 'Completada'),
(83, 17, '2026-10-15 10:45:00', 'Completada'),
(84, 18, '2026-10-16 08:15:00', 'Completada'),
(85, 19, '2026-10-16 09:00:00', 'Completada'),
(86, 20, '2026-10-16 10:30:00', 'Completada'),
(87, 21, '2026-10-19 08:30:00', 'Completada'),
(88, 22, '2026-10-19 09:15:00', 'Completada'),
(89, 1, '2026-10-19 11:00:00', 'Completada'),
(90, 2, '2026-10-20 08:00:00', 'Completada'),
(91, 3, '2026-10-20 09:30:00', 'Completada'),
(92, 4, '2026-10-20 10:45:00', 'Pendiente'),
(93, 5, '2026-10-21 08:15:00', 'Pendiente'),
(94, 6, '2026-10-21 09:00:00', 'Pendiente'),
(95, 7, '2026-10-21 10:30:00', 'Completada'),
(96, 8, '2026-10-22 08:30:00', 'Completada'),
(97, 9, '2026-10-22 09:15:00', 'Completada'),
(98, 10, '2026-10-22 11:00:00', 'Pendiente'),
(99, 11, '2026-10-23 08:00:00', 'Pendiente'),
(100, 12, '2026-10-23 09:30:00', 'Pendiente'),

-- Citas Recientes y Próximas 
(101, 13, '2026-10-26 08:00:00', 'Completada'),
(102, 14, '2026-10-26 09:30:00', 'Completada'),
(103, 15, '2026-10-26 11:00:00', 'Completada'),
(104, 16, '2026-10-27 08:15:00', 'Completada'),
(105, 17, '2026-10-27 09:45:00', 'Completada'),
(106, 18, '2026-10-27 11:15:00', 'Completada'),
(107, 19, '2026-10-28 08:30:00', 'Completada'),
(108, 20, '2026-10-28 10:00:00', 'Completada'),
(109, 21, '2026-10-28 14:00:00', 'Completada'),
(110, 22, '2026-10-29 08:00:00', 'Completada'),
(111, 1, '2026-10-29 09:30:00', 'Completada'),
(112, 2, '2026-10-29 11:00:00', 'Completada'),
(113, 3, '2026-10-30 08:15:00', 'Completada'),
(114, 4, '2026-10-30 09:45:00', 'Completada'),
(115, 5, '2026-10-30 11:15:00', 'Completada'),

-- Noviembre 2026 Citas Programadas / Pendientes
(116, 6, '2026-11-02 08:00:00', 'Pendiente'),
(117, 7, '2026-11-02 09:00:00', 'Pendiente'),
(118, 8, '2026-11-02 10:30:00', 'Pendiente'),
(119, 9, '2026-11-03 08:30:00', 'Pendiente'),
(120, 10, '2026-11-03 09:15:00', 'Pendiente'),
(121, 11, '2026-11-03 11:00:00', 'Pendiente'),
(122, 12, '2026-11-04 08:00:00', 'Pendiente'),
(123, 13, '2026-11-04 09:30:00', 'Pendiente'),
(124, 14, '2026-11-04 10:45:00', 'Pendiente'),
(125, 15, '2026-11-05 08:15:00', 'Pendiente'),
(126, 16, '2026-11-05 09:00:00', 'Pendiente'),
(127, 17, '2026-11-05 10:30:00', 'Pendiente'),
(128, 18, '2026-11-06 08:30:00', 'Pendiente'),
(129, 19, '2026-11-06 09:15:00', 'Pendiente'),
(130, 20, '2026-11-06 11:00:00', 'Pendiente'),
(131, 21, '2026-11-09 08:00:00', 'Pendiente'),
(132, 22, '2026-11-09 09:30:00', 'Pendiente'),
(133, 1, '2026-11-09 10:45:00', 'Pendiente'),
(134, 2, '2026-11-10 08:15:00', 'Pendiente'),
(135, 3, '2026-11-10 09:00:00', 'Pendiente'),
(136, 4, '2026-11-10 10:30:00', 'Pendiente'),
(137, 5, '2026-11-11 08:30:00', 'Pendiente'),
(138, 6, '2026-11-11 09:15:00', 'Pendiente'),
(139, 7, '2026-11-11 11:00:00', 'Pendiente'),
(140, 8, '2026-11-12 08:00:00', 'Pendiente'),
(141, 9, '2026-11-12 09:30:00', 'Pendiente'),
(142, 10, '2026-11-12 10:45:00', 'Pendiente'),
(143, 11, '2026-11-13 08:15:00', 'Pendiente'),
(144, 12, '2026-11-13 09:00:00', 'Pendiente'),
(145, 13, '2026-11-13 10:30:00', 'Pendiente'),
(146, 14, '2026-11-16 08:30:00', 'Pendiente'),
(147, 15, '2026-11-16 09:15:00', 'Pendiente'),
(148, 16, '2026-11-16 11:00:00', 'Pendiente'),
(149, 17, '2026-11-17 08:00:00', 'Pendiente'),
(150, 18, '2026-11-17 09:30:00', 'Pendiente');
GO

-- Tratamientos
INSERT INTO clinico.Tratamientos (CitaID, DiagnosticoID, Indicaciones, Costo) VALUES
(1, 1, 'Dieta baja en sodio y control en 3 meses.', 75.00),
(2, 2, 'Multivitamínico y seguimiento en 6 meses.', 45.00),
(3, 3, 'Estudios preoperatorios de rutina.', 150.00),
(4, 4, 'Plan de alimentación balanceado bajo en carbohidratos.', 50.00),
(6, 5, 'Terapia cognitiva y seguimiento en 1 mes.', 90.00),
(7, 6, 'Exámenes de laboratorio general.', 65.00),
(8, 7, 'Antihistamínicos y reposo por 5 días.', 55.00),
(9, 8, 'Antibiótico cada 12 horas por 7 días.', 70.00),
(10, 9, 'Ecografía pélvica normal.', 85.00),
(11, 10, 'Perfil renal y control de presión arterial.', 95.00),
(12, 11, 'Exámenes de laboratorio general.', 40.00),
(13, 12, 'Crema hidratante y corticoide tópico por 5 días.', 60.00),
(14, 13, 'Inmovilización ligera y antiinflamatorios.', 110.00),
(16, 14, 'Pruebas de marcadores tumorales en rango.', 180.00),
(17, 15, 'Ajuste de dosis de insulina y glucometría.', 80.00),
(18, 16, 'Inhaladores y broncodilatadores por 7 días.', 75.00),
(19, 17, 'Tratamiento inmunomodulador y analgésicos.', 120.00),
(20, 18, 'Suplementación de calcio y vitamina D.', 55.00),
(21, 19, 'Hemograma completo y cultivo serológico.', 85.00),
(22, 20, 'Riesgo quirúrgico aprobado.', 60.00),
(23, 21, 'Electrocardiograma normal, control anual.', 80.00),
(24, 22, 'Antihistamínico pediátrico por 10 días.', 45.00),
(25, 23, 'Cicatrización adecuada, retirar puntos.', 100.00),
(26, 24, 'Ajuste de macronutrientes.', 50.00),
(27, 25, 'Inicio de ansiolíticos suaves y psicoterapia.', 95.00),
(28, 26, 'Profiláctico de migraña y cambio de hábitos.', 85.00),
(30, 27, 'Gotas óticas y antibiótico oral.', 65.00),
(31, 28, 'Abundante hidratación y antiespasmódicos.', 90.00),
(32, 29, 'Ecografía obstétrica y ácido fólico.', 95.00),
(33, 30, 'Restricción de proteínas y control de urea.', 105.00),
(34, 31, 'Analítica de sangre y orina.', 40.00),
(35, 32, 'Tratamiento retinoide tópico.', 70.00),
(36, 33, 'Fisioterapia y relajantes musculares.', 115.00),
(37, 34, 'Receta para lentes de medida.', 75.00),
(38, 35, 'Estudios de imagen sin novedades.', 175.00),
(39, 36, 'Estudio hormonal pediátrico.', 90.00),
(40, 37, 'Inhalador de rescate y corticoides inhalados.', 85.00),
(41, 38, 'Infiltración articular con ácido hialurónico.', 140.00),
(42, 39, 'Evaluación neuropsicológica.', 65.00),
(44, 40, 'Valoración para procedimiento menor.', 70.00),
(45, 41, 'Aspirina y estatinas nocturnas.', 90.00),
(46, 42, 'Penicilina benzatínica intramuscular.', 50.00),
(47, 43, 'Valoración laserterapia.', 130.00),
(48, 44, 'Dieta de exclusión y enzimas.', 55.00),
(49, 45, 'Terapia ocupacional y apoyo psicológico.', 85.00),
(50, 46, 'Complejo B y pregabalina.', 95.00),
(51, 47, 'Modificación de estilo de vida y metformina.', 75.00),
(52, 48, 'Lavados nasales y antibiótico específico.', 65.00),
(53, 49, 'Ciprofloxacino por 5 días.', 70.00),
(54, 50, 'Anticonceptivos orales y control endocrino.', 85.00),
(55, 51, 'Estudio de biopsia renal.', 120.00),
(56, 52, 'Certificado médico de aptitud.', 45.00),
(57, 53, 'Corticoides tópicos y antihistamínicos.', 65.00),
(58, 54, 'Inmovilización parcial y AINEs.', 105.00),
(59, 55, 'Gotas hipotensoras oculares.', 85.00),
(60, 56, 'Biopsia ganglionar programada.', 190.00),
(62, 57, 'Nebulización en clínica y seguimiento.', 80.00),
(63, 58, 'Moduladores del dolor y fisioterapia.', 110.00),
(64, 59, 'Plan de cuidados y fisioterapia motora.', 60.00),
(65, 60, 'Descarte de dengue y pruebas serológicas.', 80.00),
(66, 61, 'Estudio cardiovascular prequirúrgico.', 65.00),
(67, 62, 'Enalapril más hidroclorotiazida.', 85.00),
(68, 63, 'Antiparasitario de amplio espectro.', 40.00),
(69, 64, 'Estudios analíticos y electrocardiograma.', 160.00),
(70, 65, 'Dieta hipocalórica y ejercicio.', 55.00),
(71, 66, 'Higiene del sueño y melatonina.', 75.00),
(72, 67, 'Rehabilitación física y antiagregantes.', 130.00),
(73, 68, 'Hemoglobina glicosilada dentro del rango.', 70.00),
(74, 69, 'Corticoides nasales en aerosol.', 75.00),
(75, 70, 'Tamsulosina diaria.', 85.00),
(76, 71, 'Ecografía transvaginal.', 90.00),
(77, 72, 'Monitoreo de orina de 24 horas.', 100.00),
(78, 73, 'Perfil lipídico y tiroideo.', 40.00),
(79, 74, 'Champú formulado y fototerapia.', 80.00),
(80, 75, 'Reposo deportivo y crioterapia.', 100.00),
(81, 76, 'Evaluación para facoemulsificación.', 95.00),
(82, 77, 'Evaluación de hemograma completo.', 170.00),
(83, 78, 'Levotiroxina sódica graduada.', 85.00),
(84, 79, 'Inhaladores combinados.', 90.00),
(85, 80, 'Hidroxicloroquina y corticoides.', 135.00),
(86, 81, 'Amlodipino diario.', 60.00),
(87, 82, 'Tratamiento sintomático y reposo.', 75.00),
(88, 83, 'Aprobado sin riesgo.', 65.00),
(89, 84, 'Diuréticos de asa y vasodilatadores.', 110.00),
(90, 85, 'Sales de rehidratación oral.', 45.00),
(91, 86, 'Planificación quirúrgica reconstructiva.', 200.00),
(92, 87, 'Suplementos hipercalóricos.', 60.00),
(93, 88, 'Psicoterapia y benzodiacepinas de rescate.', 90.00),
(94, 89, 'Valproato de sodio.', 100.00),
(95, 90, 'Levofloxacino oral por 7 días.', 85.00),
(96, 91, 'Audiometría de control.', 60.00),
(97, 92, 'Urocultivo y antibiograma.', 80.00),
(98, 93, 'Terapia de reemplazo hormonal suave.', 90.00),
(99, 94, 'Ecografía renal de control.', 105.00),
(100, 95, 'Apto para actividad deportiva.', 40.00),
(101, 96, 'Antifúngico tópico por 14 días.', 55.00),
(102, 97, 'Resonancia magnética y artroscopia.', 150.00),
(103, 98, 'Gotas oftálmicas con tobramicina.', 50.00),
(104, 99, 'Mamografía y ecografía mamaria.', 160.00),
(105, 100, 'Plan de actividad física y nutrición.', 70.00),
(106, 101, 'Estudio de polisomnografía.', 95.00),
(107, 102, 'Terapia biológica de mantenimiento.', 140.00),
(108, 103, 'Test Minimental y control.', 65.00),
(109, 104, 'Loción calamina y sintomáticos.', 75.00),
(110, 105, 'Pruebas de coagulación.', 60.00),
(111, 106, 'Ecocardiograma Doppler.', 120.00),
(112, 107, 'Crema protectora con óxido de zinc.', 40.00),
(113, 108, 'Evaluación quirúrgica.', 180.00),
(114, 109, 'Hierro carboximaltosa intavenoso.', 65.00),
(115, 110, 'Acompañamiento psicológico.', 80.00);
GO

-- Facturas (el monto ahora vive en DetalleFactura)
INSERT INTO facturacion.Facturacion (CitaID, FechaEmision, EstadoPago) VALUES
(1, '2026-09-01 09:30:00', 'Pagado'),
(2, '2026-09-01 10:00:00', 'Pagado'),
(3, '2026-09-01 11:00:00', 'Pagado'),
(4, '2026-09-01 11:30:00', 'Pagado'),
(6, '2026-09-02 11:00:00', 'Pagado'),
(7, '2026-09-02 12:00:00', 'Pagado'),
(8, '2026-09-02 13:00:00', 'Pagado'),
(9, '2026-09-03 09:30:00', 'Pagado'),
(10, '2026-09-03 10:30:00', 'Pagado'),
(11, '2026-09-03 12:00:00', 'Pagado'),
(12, '2026-09-03 15:30:00', 'Pagado'),
(13, '2026-09-04 10:00:00', 'Pagado'),
(14, '2026-09-04 11:00:00', 'Pagado'),
(16, '2026-09-05 09:30:00', 'Pagado'),
(17, '2026-09-05 11:00:00', 'Pagado'),
(18, '2026-09-05 12:30:00', 'Pagado'),
(19, '2026-09-07 09:30:00', 'Pagado'),
(20, '2026-09-07 11:00:00', 'Pagado'),
(21, '2026-09-07 12:00:00', 'Pagado'),
(22, '2026-09-07 15:30:00', 'Pagado'),
(23, '2026-09-08 09:30:00', 'Pagado'),
(24, '2026-09-08 10:30:00', 'Pagado'),
(25, '2026-09-08 12:00:00', 'Pagado'),
(26, '2026-09-09 10:00:00', 'Pagado'),
(27, '2026-09-09 10:45:00', 'Pagado'),
(28, '2026-09-09 12:30:00', 'Pagado'),
(30, '2026-09-10 11:00:00', 'Pagado'),
(31, '2026-09-10 11:45:00', 'Pagado'),
(32, '2026-09-11 10:00:00', 'Pagado'),
(33, '2026-09-11 11:00:00', 'Pagado'),
(34, '2026-09-11 12:45:00', 'Pagado'),
(35, '2026-09-14 09:30:00', 'Pagado'),
(36, '2026-09-14 10:30:00', 'Pagado'),
(37, '2026-09-14 12:00:00', 'Pagado'),
(38, '2026-09-15 10:00:00', 'Pagado'),
(39, '2026-09-15 10:45:00', 'Pagado'),
(40, '2026-09-15 12:30:00', 'Pagado'),
(41, '2026-09-16 09:30:00', 'Pagado'),
(42, '2026-09-16 11:00:00', 'Pagado'),
(44, '2026-09-17 09:30:00', 'Pagado'),
(45, '2026-09-17 10:30:00', 'Pagado'),
(46, '2026-09-17 12:00:00', 'Pagado'),
(47, '2026-09-18 10:00:00', 'Pagado'),
(48, '2026-09-18 10:45:00', 'Pagado'),
(49, '2026-09-18 12:30:00', 'Pagado'),
(50, '2026-09-21 09:30:00', 'Pagado'),
(51, '2026-10-01 10:00:00', 'Pagado'),
(52, '2026-10-01 10:45:00', 'Pagado'),
(53, '2026-10-01 11:30:00', 'Pagado'),
(54, '2026-10-02 09:30:00', 'Pagado'),
(55, '2026-10-02 11:00:00', 'Pagado'),
(56, '2026-10-02 12:30:00', 'Pagado'),
(57, '2026-10-05 09:45:00', 'Pagado'),
(58, '2026-10-05 10:30:00', 'Pagado'),
(59, '2026-10-05 12:00:00', 'Pagado'),
(60, '2026-10-06 10:00:00', 'Pagado'),
(62, '2026-10-06 12:30:00', 'Pagado'),
(63, '2026-10-07 09:30:00', 'Pagado'),
(64, '2026-10-07 11:00:00', 'Pagado'),
(65, '2026-10-07 12:15:00', 'Pagado'),
(66, '2026-10-08 09:45:00', 'Pagado'),
(67, '2026-10-08 10:30:00', 'Pagado'),
(68, '2026-10-08 12:00:00', 'Pagado'),
(69, '2026-10-09 10:00:00', 'Pagado'),
(70, '2026-10-09 10:45:00', 'Pagado'),
(71, '2026-10-09 12:30:00', 'Pagado'),
(72, '2026-10-12 09:30:00', 'Pagado'),
(73, '2026-10-12 11:00:00', 'Pagado'),
(74, '2026-10-12 12:15:00', 'Pagado'),
(75, '2026-10-13 09:45:00', 'Pagado'),
(76, '2026-10-13 10:30:00', 'Pagado'),
(77, '2026-10-13 12:00:00', 'Pagado'),
(78, '2026-10-14 10:00:00', 'Pagado'),
(79, '2026-10-14 10:45:00', 'Pagado'),
(80, '2026-10-14 12:30:00', 'Pagado'),
(81, '2026-10-15 09:30:00', 'Pagado'),
(82, '2026-10-15 11:00:00', 'Pagado'),
(83, '2026-10-15 12:15:00', 'Pagado'),
(84, '2026-10-16 09:45:00', 'Pagado'),
(85, '2026-10-16 10:30:00', 'Pagado'),
(86, '2026-10-16 12:00:00', 'Pagado'),
(87, '2026-10-19 10:00:00', 'Pagado'),
(88, '2026-10-19 10:45:00', 'Pagado'),
(89, '2026-10-19 12:30:00', 'Pagado'),
(90, '2026-10-20 09:30:00', 'Pagado'),
(91, '2026-10-20 11:00:00', 'Pagado'),
(92, '2026-10-20 12:15:00', 'Pagado'),
(93, '2026-10-21 09:45:00', 'Pagado'),
(94, '2026-10-21 10:30:00', 'Pagado'),
(95, '2026-10-21 12:00:00', 'Pagado'),
(96, '2026-10-22 10:00:00', 'Pagado'),
(97, '2026-10-22 10:45:00', 'Pagado'),
(98, '2026-10-22 12:30:00', 'Pagado'),
(99, '2026-10-23 09:30:00', 'Pagado'),
(100, '2026-10-23 11:00:00', 'Pagado'),
(101, '2026-10-26 09:30:00', 'Pagado'),
(102, '2026-10-26 11:00:00', 'Pagado'),
(103, '2026-10-26 12:30:00', 'Pagado'),
(104, '2026-10-27 09:45:00', 'Pagado'),
(105, '2026-10-27 11:15:00', 'Pendiente'),
(106, '2026-10-27 12:45:00', 'Pagado'),
(107, '2026-10-28 10:00:00', 'Pendiente'),
(108, '2026-10-28 11:30:00', 'Pagado'),
(109, '2026-10-28 15:30:00', 'Pendiente'),
(110, '2026-10-29 09:30:00', 'Pagado'),
(111, '2026-10-29 11:00:00', 'Pendiente'),
(112, '2026-10-29 12:30:00', 'Pagado'),
(113, '2026-10-30 09:45:00', 'Pendiente'),
(114, '2026-10-30 11:15:00', 'Pendiente'),
(115, '2026-10-30 12:45:00', 'Pendiente');
GO

-- Detalle de factura: una linea por tratamiento de la cita facturada
INSERT INTO facturacion.DetalleFactura (FacturaID, Concepto, Cantidad, PrecioUnitario)
SELECT f.FacturaID,
       LEFT(CONCAT('Tratamiento: ', d.Nombre_Diagnostico), 255),
       1,t.Costo
FROM facturacion.Facturacion f
JOIN clinico.Tratamientos t ON t.CitaID = f.CitaID
JOIN catalogo.Diagnosticos d ON d.DiagnosticoID = t.DiagnosticoID;
GO

-- Verificacion de carga (conteos esperados con los datos actuales)
SELECT 'catalogo.Especialidades' AS tabla, COUNT(*) AS filas FROM catalogo.Especialidades UNION ALL
SELECT 'catalogo.Diagnosticos', COUNT(*) FROM catalogo.Diagnosticos   UNION ALL
SELECT 'clinico.Pacientes', COUNT(*) FROM clinico.Pacientes UNION ALL
SELECT 'clinico.Medicos', COUNT(*) FROM clinico.Medicos UNION ALL
SELECT 'clinico.Citas', COUNT(*) FROM clinico.Citas UNION ALL
SELECT 'clinico.Tratamientos', COUNT(*) FROM clinico.Tratamientos UNION ALL
SELECT 'facturacion.Facturacion', COUNT(*) FROM facturacion.Facturacion UNION ALL
SELECT 'facturacion.DetalleFactura', COUNT(*) FROM facturacion.DetalleFactura;
GO

--Vistas para el POWER bi
CREATE VIEW reportes.vw_Citas
AS
SELECT c.CitaID,
       c.FechaHora,
       CAST(c.FechaHora AS DATE) AS Fecha,
       YEAR(c.FechaHora) AS Anio,
       MONTH(c.FechaHora) AS Mes,
       c.Estado,
       m.MedicoID,
       CONCAT(m.Nombre_Medico, ' ', m.Apellido_Medico) AS Medico,
       e.Nombre AS Especialidad,
       p.PacienteID,
       DATEDIFF(YEAR, p.FechaNacimiento, c.FechaHora) AS EdadPaciente
FROM clinico.Citas c
JOIN clinico.Medicos m ON m.MedicoID = c.MedicoID
JOIN catalogo.Especialidades e  ON e.EspecialidadID = m.EspecialidadID
JOIN clinico.Pacientes p ON p.PacienteID = c.PacienteID;
GO

CREATE VIEW reportes.vw_Facturacion
AS
SELECT f.FacturaID,
       f.CitaID,
       f.FechaEmision,
       f.EstadoPago,
       ISNULL(SUM(d.Subtotal), 0)             AS MontoTotal,
       m.MedicoID,
       CONCAT(m.Nombre_Medico, ' ', m.Apellido_Medico) AS Medico,
       e.Nombre                               AS Especialidad
FROM facturacion.Facturacion f
JOIN clinico.Citas c ON c.CitaID = f.CitaID
JOIN clinico.Medicos m ON m.MedicoID = c.MedicoID
JOIN catalogo.Especialidades e ON e.EspecialidadID = m.EspecialidadID
LEFT JOIN facturacion.DetalleFactura d ON d.FacturaID = f.FacturaID
GROUP BY f.FacturaID, f.CitaID, f.FechaEmision, f.EstadoPago,
         m.MedicoID, m.Nombre_Medico, m.Apellido_Medico, e.Nombre;
GO

CREATE VIEW reportes.vw_Tratamientos
AS
SELECT t.TratamientoID,
       t.CitaID,
       dg.Nombre_Diagnostico AS Diagnostico,
       t.Costo,
       c.FechaHora,
       e.Nombre AS Especialidad
FROM clinico.Tratamientos t
JOIN catalogo.Diagnosticos dg ON dg.DiagnosticoID = t.DiagnosticoID
JOIN clinico.Citas c ON c.CitaID = t.CitaID
JOIN clinico.Medicos m ON m.MedicoID = c.MedicoID
JOIN catalogo.Especialidades e ON e.EspecialidadID = m.EspecialidadID;
GO




/* =====================================================================
   2. CARGA DE VOLUMEN 
   Objetivo: llevar las tablas a un volumen realista (decenas de miles de
   filas) para que los indices, los planes de ejecucion, el
   dimensionamiento y los backups sean medibles
   ===================================================================== */
USE HospitalDB;
GO
SET NOCOUNT ON;
SET DATEFORMAT ymd;
GO

DECLARE @NuevosPacientes INT      = 5000;
DECLARE @NuevasCitas     INT      = 60000;
DECLARE @FechaIni        DATETIME = '2023-01-01';
DECLARE @FechaFin        DATETIME = '2026-09-01';   -- exclusivo

IF EXISTS (SELECT 1 FROM clinico.Pacientes WHERE Email LIKE 'paciente%@carga.hospital.com')
BEGIN
    PRINT 'La carga de volumen ya fue ejecutada: se omite.';
END
ELSE
BEGIN
    DECLARE @MaxCitaAntes    INT = (SELECT MAX(CitaID)       FROM clinico.Citas);
    DECLARE @MaxFacturaAntes INT = (SELECT MAX(FacturaID)    FROM facturacion.Facturacion);
    DECLARE @MaxMedico       INT = (SELECT MAX(MedicoID)     FROM clinico.Medicos);
    DECLARE @MaxDiag         INT = (SELECT MAX(DiagnosticoID) FROM catalogo.Diagnosticos);
    DECLARE @MaxPaciente     INT;

    -- 1) Pacientes adicionales
    INSERT INTO clinico.Pacientes (Nombre_Paciente, Apellido_Paciente, FechaNacimiento, Telefono, Email, FechaRegistro)
    SELECT CHOOSE(1 + (CHECKSUM(g.value, 1) & 2147483647) % 20, 'Carlos','Maria','Jose','Ana','Luis','Sofia','Pedro','Lucia','Miguel','Elena','Jorge','Carmen','Diego','Paula','Mario','Rosa','Oscar','Marta','Hugo','Irene'),
           CHOOSE(1 + (CHECKSUM(g.value, 2) & 2147483647) % 20, 'Martinez','Hernandez','Lopez','Rodriguez','Sanchez','Gomez','Perez','Jimenez','Ruiz','Alvarez','Moreno','Munoz','Alonso','Romero','Navarro','Torres','Dominguez','Vazquez','Ramos','Gil'),
           DATEADD(DAY, (CHECKSUM(g.value, 3) & 2147483647) % 30000, CAST('1940-01-01' AS DATE)),
           CONCAT('7', (CHECKSUM(g.value, 4) & 2147483647) % 900 + 100, '-', (CHECKSUM(g.value, 5) & 2147483647) % 9000 + 1000),
           CONCAT('paciente', g.value, '@carga.hospital.com'),
           DATEADD(DAY, -((CHECKSUM(g.value, 6) & 2147483647) % 900), @FechaIni)
    FROM GENERATE_SERIES(1, @NuevosPacientes) AS g;

    SET @MaxPaciente = (SELECT MAX(PacienteID) FROM clinico.Pacientes);

    -- 2) Citas historicas (85% completadas, 15% canceladas)
    INSERT INTO clinico.Citas (PacienteID, MedicoID, FechaHora, Estado)
    SELECT x.PacienteID, x.MedicoID, x.FechaHora, x.Estado
    FROM GENERATE_SERIES(1, @NuevasCitas) AS g
    CROSS APPLY (SELECT
        PacienteID = 1 + (CHECKSUM(g.value, 21) & 2147483647) % @MaxPaciente,
        MedicoID   = 1 + (CHECKSUM(g.value, 22) & 2147483647) % @MaxMedico,
        FechaHora  = DATEADD(MINUTE, 15 * ((CHECKSUM(g.value, 25) & 2147483647) % 4),
                     DATEADD(HOUR, 8 + ((CHECKSUM(g.value, 24) & 2147483647) % 10),
                     DATEADD(DAY, (CHECKSUM(g.value, 23) & 2147483647) % DATEDIFF(DAY, @FechaIni, @FechaFin), @FechaIni))),
        Estado     = CASE WHEN (CHECKSUM(g.value, 26) & 2147483647) % 100 < 85 THEN 'Completada' ELSE 'Cancelada' END
    ) AS x
    ORDER BY x.FechaHora;

    -- 3) Un tratamiento por cada cita completada nueva
    INSERT INTO clinico.Tratamientos (CitaID, DiagnosticoID, Indicaciones, Costo)
    SELECT c.CitaID,
           1 + (CHECKSUM(c.CitaID, 31) & 2147483647) % @MaxDiag,
           CHOOSE(1 + (CHECKSUM(c.CitaID, 33) & 2147483647) % 5,
                  'Control en 30 dias y medicacion segun receta.',
                  'Reposo relativo, hidratacion y seguimiento.',
                  'Examenes de laboratorio y cita de control.',
                  'Dieta indicada y actividad fisica moderada.',
                  'Terapia de mantenimiento y evaluacion periodica.'),
           CAST(40 + 5 * ((CHECKSUM(c.CitaID, 32) & 2147483647) % 33) AS DECIMAL(10,2))
    FROM clinico.Citas c
    WHERE c.CitaID > @MaxCitaAntes AND c.Estado = 'Completada';

    -- 4) Una factura por cita completada (90% pagadas)
    INSERT INTO facturacion.Facturacion (CitaID, FechaEmision, EstadoPago)
    SELECT c.CitaID,
           DATEADD(MINUTE, 60 + (CHECKSUM(c.CitaID, 41) & 2147483647) % 120, c.FechaHora),
           CASE WHEN (CHECKSUM(c.CitaID, 42) & 2147483647) % 100 < 90 THEN 'Pagado' ELSE 'Pendiente' END
    FROM clinico.Citas c
    WHERE c.CitaID > @MaxCitaAntes AND c.Estado = 'Completada'
    ORDER BY c.CitaID;

    -- 5) Detalle: linea de tratamiento + (30% de facturas) linea de insumos
    INSERT INTO facturacion.DetalleFactura (FacturaID, Concepto, Cantidad, PrecioUnitario)
    SELECT f.FacturaID,
           LEFT(CONCAT('Tratamiento: ', d.Nombre_Diagnostico), 255),
           1,
           t.Costo
    FROM facturacion.Facturacion f
    JOIN clinico.Tratamientos  t ON t.CitaID = f.CitaID
    JOIN catalogo.Diagnosticos d ON d.DiagnosticoID = t.DiagnosticoID
    WHERE f.FacturaID > @MaxFacturaAntes;

    INSERT INTO facturacion.DetalleFactura (FacturaID, Concepto, Cantidad, PrecioUnitario)
    SELECT f.FacturaID,
           'Insumos y medicamentos',
           1 + (CHECKSUM(f.FacturaID, 51) & 2147483647) % 3,
           CAST(5 + 5 * ((CHECKSUM(f.FacturaID, 52) & 2147483647) % 8) AS DECIMAL(10,2))
    FROM facturacion.Facturacion f
    WHERE f.FacturaID > @MaxFacturaAntes
      AND (CHECKSUM(f.FacturaID, 53) & 2147483647) % 100 < 30;

    PRINT 'Carga de volumen completada.';
END
GO

-- Estadisticas completas despues de la carga (planes de ejecucion fiables)
UPDATE STATISTICS clinico.Pacientes       WITH FULLSCAN;
UPDATE STATISTICS clinico.Citas           WITH FULLSCAN;
UPDATE STATISTICS clinico.Tratamientos    WITH FULLSCAN;
UPDATE STATISTICS facturacion.Facturacion WITH FULLSCAN;
UPDATE STATISTICS facturacion.DetalleFactura WITH FULLSCAN;
GO

-- Evidencia de la carga: conteos y distribucion
SELECT 'catalogo.Especialidades' AS tabla, COUNT(*) AS filas FROM catalogo.Especialidades UNION ALL
SELECT 'catalogo.Diagnosticos',      COUNT(*) FROM catalogo.Diagnosticos      UNION ALL
SELECT 'clinico.Pacientes',          COUNT(*) FROM clinico.Pacientes          UNION ALL
SELECT 'clinico.Medicos',            COUNT(*) FROM clinico.Medicos            UNION ALL
SELECT 'clinico.Citas',              COUNT(*) FROM clinico.Citas              UNION ALL
SELECT 'clinico.Tratamientos',       COUNT(*) FROM clinico.Tratamientos       UNION ALL
SELECT 'facturacion.Facturacion',    COUNT(*) FROM facturacion.Facturacion    UNION ALL
SELECT 'facturacion.DetalleFactura', COUNT(*) FROM facturacion.DetalleFactura;
GO
SELECT YEAR(FechaHora) AS Anio, Estado, COUNT(*) AS Citas
FROM clinico.Citas GROUP BY YEAR(FechaHora), Estado ORDER BY Anio, Estado;
GO

/* =====================================================================
   3. SEGURIDAD: LOGINS, USUARIOS, ROLES Y PERMISOS

   Reglas aplicadas:
     - Permisos SOLO a roles, nunca a usuarios sueltos.
     - Minimo privilegio: todo esta denegado por defecto hasta un GRANT.
     - Defensa en profundidad: DENY explicito de DELETE y ALTER.
     - CHECK_POLICY = ON siempre; CHECK_EXPIRATION = ON para personas y
       OFF para la cuenta de servicio (Power BI).


   ===================================================================== */
USE HospitalDB;
GO

-- Limpieza para poder repetir este archivo sin repetir el 01
IF DATABASE_PRINCIPAL_ID('u_recepcion')    IS NOT NULL DROP USER u_recepcion;
IF DATABASE_PRINCIPAL_ID('u_medico')       IS NOT NULL DROP USER u_medico;
IF DATABASE_PRINCIPAL_ID('u_contabilidad') IS NOT NULL DROP USER u_contabilidad;
IF DATABASE_PRINCIPAL_ID('u_powerbi')      IS NOT NULL DROP USER u_powerbi;
IF DATABASE_PRINCIPAL_ID('Rol_Recepcionista') IS NOT NULL DROP ROLE Rol_Recepcionista;
IF DATABASE_PRINCIPAL_ID('Rol_Medico')        IS NOT NULL DROP ROLE Rol_Medico;
IF DATABASE_PRINCIPAL_ID('Rol_Contabilidad')  IS NOT NULL DROP ROLE Rol_Contabilidad;
IF DATABASE_PRINCIPAL_ID('Rol_Reportes')      IS NOT NULL DROP ROLE Rol_Reportes;
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_recepcion')    DROP LOGIN lg_recepcion;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_medico')       DROP LOGIN lg_medico;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_contabilidad') DROP LOGIN lg_contabilidad;
IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'lg_powerbi')      DROP LOGIN lg_powerbi;
GO
USE HospitalDB;
GO

-- Paso 1 (Ejercicio 1): principals existentes y contexto de la sesion
SELECT principal_id, name, type_desc, is_disabled
FROM master.sys.server_principals
WHERE type_desc IN ('SQL_LOGIN', 'WINDOWS_LOGIN')
ORDER BY principal_id;

SELECT principal_id, name, type_desc
FROM sys.database_principals
WHERE type_desc IN ('SQL_USER', 'DATABASE_ROLE')
ORDER BY principal_id;

SELECT ORIGINAL_LOGIN() AS login_con_que_me_conecte,
       USER_NAME()      AS usuario_activo_en_esta_bd;   -- sa / dbo
GO

-- Paso 2 (Ejercicios 2 y 3): LOGINS a nivel de servidor (en master)
-- Personas: CHECK_EXPIRATION = ON. Cuenta de servicio (Power BI): OFF.
USE [master];
GO
CREATE LOGIN [lg_recepcion]    WITH PASSWORD = N'Recep#2026Hosp', CHECK_POLICY = ON, CHECK_EXPIRATION = ON,  DEFAULT_DATABASE = HospitalDB;
CREATE LOGIN [lg_medico]       WITH PASSWORD = N'Medic#2026Hosp', CHECK_POLICY = ON, CHECK_EXPIRATION = ON,  DEFAULT_DATABASE = HospitalDB;
CREATE LOGIN [lg_contabilidad] WITH PASSWORD = N'Conta#2026Hosp', CHECK_POLICY = ON, CHECK_EXPIRATION = ON,  DEFAULT_DATABASE = HospitalDB;
CREATE LOGIN [lg_powerbi]      WITH PASSWORD = N'PBI#2026Hosp',   CHECK_POLICY = ON, CHECK_EXPIRATION = OFF, DEFAULT_DATABASE = HospitalDB;
GO

-- USUARIOS dentro de HospitalDB, enlazados al login por SID
USE HospitalDB;
GO
CREATE USER [u_recepcion]    FOR LOGIN [lg_recepcion];
CREATE USER [u_medico]       FOR LOGIN [lg_medico];
CREATE USER [u_contabilidad] FOR LOGIN [lg_contabilidad];
CREATE USER [u_powerbi]      FOR LOGIN [lg_powerbi];
GO

-- Comprobacion del vinculo por SID (los SID deben ser identicos)
SELECT s.name AS login_servidor, u.name AS usuario_bd, s.sid AS sid_servidor, u.sid AS sid_usuario
FROM master.sys.server_principals s
JOIN HospitalDB.sys.database_principals u ON s.sid = u.sid
WHERE s.name LIKE 'lg[_]%';

-- Politicas de contrasena: personas con expiracion (1), servicio sin expiracion (0)
SELECT name, is_policy_checked, is_expiration_checked
FROM master.sys.sql_logins
WHERE name LIKE 'lg[_]%';
GO

-- Paso 3 DENEGADO POR DEFECTO.
-- El usuario existe pero aun no tiene permisos: se espera el Error 229.
EXECUTE AS USER = 'u_recepcion';
BEGIN TRY
    SELECT * FROM clinico.Pacientes;
END TRY
BEGIN CATCH
    PRINT 'Denegado por defecto -> Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10)) + ' (esperado 229): ' + ERROR_MESSAGE();
END CATCH
REVERT;
SELECT USER_NAME() AS usuario_restaurado;   -- debe volver a dbo
GO

-- Paso 4 ROLES por funcion y membresias (ALTER ROLE ... ADD MEMBER)
CREATE ROLE Rol_Recepcionista;
CREATE ROLE Rol_Medico;
CREATE ROLE Rol_Contabilidad;
CREATE ROLE Rol_Reportes;
GO
ALTER ROLE Rol_Recepcionista ADD MEMBER u_recepcion;
ALTER ROLE Rol_Medico        ADD MEMBER u_medico;
ALTER ROLE Rol_Contabilidad  ADD MEMBER u_contabilidad;
ALTER ROLE Rol_Reportes      ADD MEMBER u_powerbi;
GO

-- Membresias activas en el catalogo de seguridad
SELECT r.name AS nombre_rol, m.name AS miembro_usuario, r.type_desc AS tipo_rol, m.type_desc AS tipo_miembro
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id
WHERE r.name LIKE 'Rol[_]%'
ORDER BY r.name;
GO

-- Paso 5 : PERMISOS asignados a los ROLES (GRANT y DENY)
-- Recepcionista: gestiona pacientes y agenda; consulta medicos y especialidades
GRANT SELECT, INSERT, UPDATE ON clinico.Pacientes       TO Rol_Recepcionista;
GRANT SELECT, INSERT, UPDATE ON clinico.Citas           TO Rol_Recepcionista;
GRANT SELECT                 ON clinico.Medicos         TO Rol_Recepcionista;
GRANT SELECT                 ON catalogo.Especialidades TO Rol_Recepcionista;
DENY  SELECT                 ON clinico.Tratamientos    TO Rol_Recepcionista;  -- diagnosticos confidenciales
DENY  SELECT, INSERT, UPDATE ON SCHEMA::facturacion     TO Rol_Recepcionista;

-- Medico: lee pacientes y agenda, registra tratamientos, solo cambia el Estado de la cita
GRANT SELECT                 ON clinico.Pacientes       TO Rol_Medico;
GRANT SELECT                 ON clinico.Medicos         TO Rol_Medico;
GRANT SELECT                 ON clinico.Citas           TO Rol_Medico;
GRANT UPDATE (Estado)        ON clinico.Citas           TO Rol_Medico;          -- permiso a nivel de columna
GRANT SELECT, INSERT, UPDATE ON clinico.Tratamientos    TO Rol_Medico;
GRANT SELECT, INSERT         ON catalogo.Diagnosticos   TO Rol_Medico;
GRANT SELECT                 ON catalogo.Especialidades TO Rol_Medico;
DENY  SELECT, INSERT, UPDATE ON SCHEMA::facturacion     TO Rol_Medico;

-- Contabilidad: gestiona facturacion; solo lee citas, tratamientos y diagnosticos
GRANT SELECT, INSERT, UPDATE ON SCHEMA::facturacion     TO Rol_Contabilidad;
GRANT SELECT                 ON clinico.Citas           TO Rol_Contabilidad;
GRANT SELECT                 ON clinico.Tratamientos    TO Rol_Contabilidad;
GRANT SELECT                 ON catalogo.Diagnosticos   TO Rol_Contabilidad;

-- Reportes (Power BI): solo lectura de las vistas del esquema reportes
GRANT SELECT ON SCHEMA::reportes TO Rol_Reportes;
DENY  INSERT, UPDATE, DELETE, ALTER ON SCHEMA::reportes TO Rol_Reportes;

-- Defensa en profundidad (guia): nadie borra registros ni altera estructuras
DENY DELETE, ALTER ON SCHEMA::clinico     TO Rol_Recepcionista, Rol_Medico, Rol_Contabilidad, Rol_Reportes;
DENY DELETE, ALTER ON SCHEMA::facturacion TO Rol_Recepcionista, Rol_Medico, Rol_Contabilidad, Rol_Reportes;
DENY DELETE, ALTER ON SCHEMA::catalogo    TO Rol_Recepcionista, Rol_Medico, Rol_Contabilidad, Rol_Reportes;
GO

-- Permisos otorgados y denegados a cada rol (evidencia)
SELECT pr.name AS receptor_del_permiso,
       pe.permission_name AS permiso,
       pe.state_desc AS estado,
       pe.class_desc AS ambito_del_permiso,
       CASE pe.class WHEN 3 THEN 'SCHEMA::' + SCHEMA_NAME(pe.major_id)
                     WHEN 1 THEN OBJECT_SCHEMA_NAME(pe.major_id) + '.' + OBJECT_NAME(pe.major_id) END AS objeto_especifico,
       CASE WHEN pe.class = 1 AND pe.minor_id > 0 THEN COL_NAME(pe.major_id, pe.minor_id) END AS columna
FROM sys.database_permissions pe
JOIN sys.database_principals pr ON pe.grantee_principal_id = pr.principal_id
WHERE pr.name LIKE 'Rol[_]%'
ORDER BY pr.name, objeto_especifico, pe.permission_name;
GO


/* =====================================================================
   4. ORGANIZACION EN ESQUEMAS 
   ===================================================================== */

USE HospitalDB;
GO
-- Objetos de cada esquema
SELECT SCHEMA_NAME(o.schema_id) AS Esquema, o.name AS Objeto, o.type_desc AS Tipo
FROM sys.objects o
WHERE o.is_ms_shipped = 0 AND o.type IN ('U', 'V', 'P')
ORDER BY Esquema, Tipo, Objeto;

-- Propietario de cada esquema
SELECT name AS Esquema, USER_NAME(principal_id) AS Propietario
FROM sys.schemas
WHERE name IN (N'catalogo', N'clinico', N'facturacion', N'reportes', N'auditoria');
GO

-- Un permiso sobre el esquema cubre objetos futuros (guia): se crea una vista nueva
-- y u_powerbi la lee sin ningun GRANT adicional; u_recepcion no (denegado por defecto).
CREATE VIEW reportes.vw_PruebaEsquema AS SELECT 1 AS prueba;
GO
EXECUTE AS USER = 'u_powerbi';
SELECT * FROM reportes.vw_PruebaEsquema;      -- funciona
REVERT;
GO
EXECUTE AS USER = 'u_recepcion';
BEGIN TRY
    SELECT * FROM reportes.vw_PruebaEsquema;  -- Error 229 esperado
END TRY
BEGIN CATCH
    PRINT 'u_recepcion -> reportes.vw_PruebaEsquema DENEGADO, Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
END CATCH
REVERT;
GO
DROP VIEW reportes.vw_PruebaEsquema;
GO



/* =====================================================================
   5. CONSULTAS CON FUNCIONES VENTANA E INDICES (guia: Indices)
   Tres consultas con funciones ventana: RANK() (ranking de medicos por mes),
   SUM() OVER (ingresos acumulados por especialidad) y LAG() (dias entre citas
   consecutivas de un paciente).
   ===================================================================== */
USE HospitalDB;
GO
SET DATEFORMAT ymd;   -- los filtros de fecha no dependen del idioma del login
GO
-- Estado inicial: sin indices de optimizacion
DROP INDEX IF EXISTS IX_Citas_Estado_Fecha     ON clinico.Citas;
DROP INDEX IF EXISTS IX_Citas_Paciente_Fecha   ON clinico.Citas;
DROP INDEX IF EXISTS IX_Facturacion_EstadoPago ON facturacion.Facturacion;
DROP INDEX IF EXISTS IX_DetalleFactura_Factura ON facturacion.DetalleFactura;
GO
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ########## ANTES: sin indices ##########
--CONSULTA 1 DIN INDI
WITH CitasMes AS (
    SELECT c.MedicoID, YEAR(c.FechaHora) AS Anio, MONTH(c.FechaHora) AS Mes, COUNT(*) AS Citas
    FROM clinico.Citas c
    WHERE c.Estado = 'Completada'
      AND c.FechaHora >= '2026-01-01' AND c.FechaHora < '2027-01-01'
    GROUP BY c.MedicoID, YEAR(c.FechaHora), MONTH(c.FechaHora)
)
SELECT cm.Anio, cm.Mes,
       CONCAT(m.Nombre_Medico, ' ', m.Apellido_Medico) AS Medico,
       cm.Citas,
       RANK() OVER (PARTITION BY cm.Anio, cm.Mes ORDER BY cm.Citas DESC) AS Posicion
FROM CitasMes cm
JOIN clinico.Medicos m ON m.MedicoID = cm.MedicoID;
GO
--CONSULTA 2 SIN INDICE
WITH IngresosMes AS (
    SELECT e.Nombre AS Especialidad,
           YEAR(f.FechaEmision) AS Anio, MONTH(f.FechaEmision) AS Mes,
           SUM(d.Subtotal) AS Ingreso
    FROM facturacion.Facturacion f
    JOIN facturacion.DetalleFactura d ON d.FacturaID = f.FacturaID
    JOIN clinico.Citas c              ON c.CitaID = f.CitaID
    JOIN clinico.Medicos m            ON m.MedicoID = c.MedicoID
    JOIN catalogo.Especialidades e    ON e.EspecialidadID = m.EspecialidadID
    WHERE f.EstadoPago = 'Pagado'
    GROUP BY e.Nombre, YEAR(f.FechaEmision), MONTH(f.FechaEmision)
)
SELECT *,
       SUM(Ingreso) OVER (PARTITION BY Especialidad ORDER BY Anio, Mes
                          ROWS UNBOUNDED PRECEDING) AS IngresoAcumulado
FROM IngresosMes;
GO
--CONSULTA 3 SIN INDICE
SELECT PacienteID, CitaID, FechaHora,
       LAG(FechaHora) OVER (PARTITION BY PacienteID ORDER BY FechaHora) AS CitaAnterior,
       DATEDIFF(DAY,
                LAG(FechaHora) OVER (PARTITION BY PacienteID ORDER BY FechaHora),
                FechaHora) AS DiasDesdeAnterior
FROM clinico.Citas
WHERE Estado = 'Completada';
GO

-- ########## Creacion de los indices ##########
-- Consulta 1
CREATE NONCLUSTERED INDEX IX_Citas_Estado_Fecha
    ON clinico.Citas (Estado, FechaHora) INCLUDE (MedicoID);
GO
-- Consulta 2
CREATE NONCLUSTERED INDEX IX_Facturacion_EstadoPago
    ON facturacion.Facturacion (EstadoPago) INCLUDE (FechaEmision, CitaID);
GO
-- Consulta 2
CREATE NONCLUSTERED INDEX IX_DetalleFactura_Factura
    ON facturacion.DetalleFactura (FacturaID) INCLUDE (Subtotal);
GO
-- Consulta 3
CREATE NONCLUSTERED INDEX IX_Citas_Paciente_Fecha
    ON clinico.Citas (PacienteID, FechaHora) INCLUDE (Estado);
GO

-- ########## DESPUES: con indices ##########
--CONSULTA 1 CON INDICE
WITH CitasMes AS (
    SELECT c.MedicoID, YEAR(c.FechaHora) AS Anio, MONTH(c.FechaHora) AS Mes, COUNT(*) AS Citas
    FROM clinico.Citas c
    WHERE c.Estado = 'Completada'
      AND c.FechaHora >= '2026-01-01' AND c.FechaHora < '2027-01-01'
    GROUP BY c.MedicoID, YEAR(c.FechaHora), MONTH(c.FechaHora)
)
SELECT cm.Anio, cm.Mes,
       CONCAT(m.Nombre_Medico, ' ', m.Apellido_Medico) AS Medico,
       cm.Citas,
       RANK() OVER (PARTITION BY cm.Anio, cm.Mes ORDER BY cm.Citas DESC) AS Posicion
FROM CitasMes cm
JOIN clinico.Medicos m ON m.MedicoID = cm.MedicoID;
GO
-- CONSULTA 2 CON INDICE
WITH IngresosMes AS (
    SELECT e.Nombre AS Especialidad,
           YEAR(f.FechaEmision) AS Anio, MONTH(f.FechaEmision) AS Mes,
           SUM(d.Subtotal) AS Ingreso
    FROM facturacion.Facturacion f
    JOIN facturacion.DetalleFactura d ON d.FacturaID = f.FacturaID
    JOIN clinico.Citas c              ON c.CitaID = f.CitaID
    JOIN clinico.Medicos m            ON m.MedicoID = c.MedicoID
    JOIN catalogo.Especialidades e    ON e.EspecialidadID = m.EspecialidadID
    WHERE f.EstadoPago = 'Pagado'
    GROUP BY e.Nombre, YEAR(f.FechaEmision), MONTH(f.FechaEmision)
)
SELECT *,
       SUM(Ingreso) OVER (PARTITION BY Especialidad ORDER BY Anio, Mes
                          ROWS UNBOUNDED PRECEDING) AS IngresoAcumulado
FROM IngresosMes;
GO
-- CONSULTA 3 CON INDICE
SELECT PacienteID, CitaID, FechaHora,
       LAG(FechaHora) OVER (PARTITION BY PacienteID ORDER BY FechaHora) AS CitaAnterior,
       DATEDIFF(DAY,
                LAG(FechaHora) OVER (PARTITION BY PacienteID ORDER BY FechaHora),
                FechaHora) AS DiasDesdeAnterior
FROM clinico.Citas
WHERE Estado = 'Completada';
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- Mantenimiento de indices (guia): listar, medir fragmentacion, reorganizar / reconstruir
SELECT name AS Indice, type_desc AS Tipo
FROM sys.indexes
WHERE object_id = OBJECT_ID(N'clinico.Citas') AND name IS NOT NULL;
GO
SELECT i.name AS Indice, p.page_count AS Paginas, p.avg_fragmentation_in_percent AS Fragmentacion
FROM sys.dm_db_index_physical_stats (DB_ID(), OBJECT_ID(N'clinico.Citas'), NULL, NULL, 'LIMITED') AS p
JOIN sys.indexes AS i ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE p.index_level = 0;
GO
-- Referencia de la clase: REORGANIZE si la fragmentacion es menor a 30 %, REBUILD si es mayor.
ALTER INDEX IX_Citas_Paciente_Fecha ON clinico.Citas REORGANIZE;
GO
-- ALTER INDEX IX_Citas_Paciente_Fecha ON clinico.Citas REBUILD;
-- GO


/* =====================================================================
   6. AUDITORIA 
   ===================================================================== */
USE HospitalDB;
GO
IF EXISTS (SELECT 1 FROM sys.database_audit_specifications WHERE name = 'AuditoriaHospitalDB')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB;
END
GO
USE master;
GO
IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = 'AuditoriaHospital')
BEGIN
    ALTER SERVER AUDIT AuditoriaHospital WITH (STATE = OFF);
    DROP SERVER AUDIT AuditoriaHospital;
END
GO

-- El objeto de servidor define donde quedaran los eventos
CREATE SERVER AUDIT AuditoriaHospital
TO FILE (
    FILEPATH = N'/audit/HospitalDB/',
    MAXSIZE = 10 MB,
    MAX_ROLLOVER_FILES = 10
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO
ALTER SERVER AUDIT AuditoriaHospital WITH (STATE = ON);
GO

USE HospitalDB;
GO
-- La especificacion elige las acciones sobre los objetos sensibles
CREATE DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB
FOR SERVER AUDIT AuditoriaHospital
    ADD (SELECT, INSERT, DELETE ON SCHEMA::facturacion BY public),
    ADD (SELECT, INSERT, DELETE ON OBJECT::clinico.Tratamientos BY public),
    ADD (SELECT, INSERT, DELETE ON OBJECT::clinico.Pacientes BY public)
WITH (STATE = ON);
GO

-- Comprobar que la auditoria arranco: status_desc = STARTED y un archivo .sqlaudit
-- (TARGET_CREATION_FAILED = la carpeta /audit/HospitalDB no existe o no se puede escribir)
SELECT name, status_desc, audit_file_path FROM sys.dm_server_audit_status;
GO

-- Generar acciones con distintos usuarios (incluido un acceso DENEGADO)
EXECUTE AS USER = 'u_contabilidad';
SELECT TOP (5) FacturaID, CitaID, EstadoPago FROM facturacion.Facturacion ORDER BY FacturaID;
REVERT;
GO
EXECUTE AS USER = 'u_recepcion';
BEGIN TRY
    SELECT TOP (5) FacturaID FROM facturacion.Facturacion;   -- denegado, tambien queda auditado
END TRY
BEGIN CATCH
    PRINT 'Acceso denegado (esperado): Error ' + CAST(ERROR_NUMBER() AS VARCHAR(10));
END CATCH
REVERT;
GO
EXECUTE AS USER = 'u_medico';
SELECT TOP (5) TratamientoID, CitaID, Costo FROM clinico.Tratamientos ORDER BY TratamientoID;
REVERT;
GO
-- INSERT y DELETE de un paciente de prueba (el WHERE selecciona solo ese registro)
INSERT INTO clinico.Pacientes (Nombre_Paciente, Apellido_Paciente, FechaNacimiento, Email)
VALUES ('Auditoria', 'Prueba', '1990-01-01', 'auditoria.prueba@email.com');
SELECT PacienteID, Email FROM clinico.Pacientes WHERE Email = 'auditoria.prueba@email.com';
DELETE FROM clinico.Pacientes WHERE Email = 'auditoria.prueba@email.com';
GO

-- Ampliar la auditoria : las acciones solo se cambian con la especificacion
-- desactivada (activa da el error 33229). Se agrega UPDATE y se vacia la cache de permisos.
ALTER DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB WITH (STATE = OFF);
GO
ALTER DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB
    ADD (UPDATE ON SCHEMA::facturacion BY public),
    ADD (UPDATE ON OBJECT::clinico.Tratamientos BY public),
    ADD (UPDATE ON OBJECT::clinico.Pacientes BY public);
GO
ALTER DATABASE AUDIT SPECIFICATION AuditoriaHospitalDB WITH (STATE = ON);
GO
DBCC FREESYSTEMCACHE ('TokenAndPermUserStore');
GO
-- Acciones que registra ahora la especificacion
SELECT audit_action_name, class_desc,
       CASE class_desc WHEN 'SCHEMA' THEN SCHEMA_NAME(major_id)
                       WHEN 'OBJECT_OR_COLUMN' THEN OBJECT_NAME(major_id) END AS objeto
FROM sys.database_audit_specification_details
ORDER BY objeto, audit_action_name;
GO
-- Acciones UPDATE (deben quedar registradas)
EXECUTE AS USER = 'u_contabilidad';
UPDATE facturacion.Facturacion SET EstadoPago = EstadoPago WHERE FacturaID = 1;
REVERT;
GO
EXECUTE AS USER = 'u_recepcion';
UPDATE clinico.Pacientes SET Telefono = Telefono WHERE PacienteID = 1;
REVERT;
GO

-- Leer la evidencia: sys.fn_get_audit_file abre los .sqlaudit como filas.
-- action_id: SL = SELECT, IN = INSERT, DL = DELETE, UP = UPDATE.
-- event_time esta en UTC (El Salvador = UTC - 6 h). succeeded indica el resultado
-- de la comprobacion de permisos (0 = denegado); no dice cuantas filas cambiaron.
-- Un DELETE aparece como DL y como SL porque su WHERE tambien lee la tabla.
USE master;
GO
WAITFOR DELAY '00:00:03';   -- QUEUE_DELAY de la auditoria
GO
SELECT event_time, DATEADD(HOUR, -6, event_time) AS hora_El_Salvador,
       action_id, succeeded, server_principal_name, database_principal_name,
       database_name, schema_name, object_name, statement
FROM sys.fn_get_audit_file(N'/audit/HospitalDB/*.sqlaudit', DEFAULT, DEFAULT)
WHERE database_name = N'HospitalDB'
  AND schema_name IN (N'facturacion', N'clinico')
ORDER BY event_time DESC;
GO
USE HospitalDB;
GO

/* =====================================================================
   7. DICCIONARIO DE DATOS
   ===================================================================== */
USE HospitalDB;
GO
CREATE OR ALTER PROCEDURE auditoria.usp_DescribirObjeto
    @Esquema     SYSNAME,
    @Tabla       SYSNAME,
    @Columna     SYSNAME = NULL,
    @Descripcion NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;
    IF @Columna IS NULL
    BEGIN
        BEGIN TRY
            EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = @Descripcion,
                 @level0type = N'SCHEMA', @level0name = @Esquema,
                 @level1type = N'TABLE',  @level1name = @Tabla;
        END TRY
        BEGIN CATCH
            EXEC sys.sp_updateextendedproperty @name = N'MS_Description', @value = @Descripcion,
                 @level0type = N'SCHEMA', @level0name = @Esquema,
                 @level1type = N'TABLE',  @level1name = @Tabla;
        END CATCH
    END
    ELSE
    BEGIN
        BEGIN TRY
            EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = @Descripcion,
                 @level0type = N'SCHEMA', @level0name = @Esquema,
                 @level1type = N'TABLE',  @level1name = @Tabla,
                 @level2type = N'COLUMN', @level2name = @Columna;
        END TRY
        BEGIN CATCH
            EXEC sys.sp_updateextendedproperty @name = N'MS_Description', @value = @Descripcion,
                 @level0type = N'SCHEMA', @level0name = @Esquema,
                 @level1type = N'TABLE',  @level1name = @Tabla,
                 @level2type = N'COLUMN', @level2name = @Columna;
        END CATCH
    END
END
GO

EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Especialidades', NULL, N'Catálogo de especialidades médicas del hospital.';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Diagnosticos', NULL, N'Catálogo de diagnósticos clínicos reutilizables en los tratamientos.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', NULL, N'Pacientes registrados en el hospital (datos personales sensibles).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', NULL, N'Personal médico con su especialidad y licencia profesional.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', NULL, N'Citas médicas entre un paciente y un médico, con su estado.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', NULL, N'Tratamiento aplicado en una cita atendida, con su diagnóstico y costo.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'Facturacion', NULL, N'Cabecera de factura: una factura por cita atendida.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', NULL, N'Líneas (conceptos) de cada factura; el total se obtiene sumando Subtotal.';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Especialidades', N'EspecialidadID', N'Identificador único de la especialidad (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Especialidades', N'Nombre', N'Nombre de la especialidad. Único.';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Especialidades', N'Descripcion', N'Descripción opcional de la especialidad.';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Diagnosticos', N'DiagnosticoID', N'Identificador único del diagnóstico (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Diagnosticos', N'Nombre_Diagnostico', N'Nombre del diagnóstico. Único.';
EXEC auditoria.usp_DescribirObjeto N'catalogo', N'Diagnosticos', N'Descripcion', N'Descripción clínica opcional del diagnóstico.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'PacienteID', N'Identificador único del paciente (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'Nombre_Paciente', N'Nombres del paciente.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'Apellido_Paciente', N'Apellidos del paciente.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'FechaNacimiento', N'Fecha de nacimiento; permite calcular la edad.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'Telefono', N'Teléfono de contacto (opcional).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'Email', N'Correo electrónico (opcional). Único.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Pacientes', N'FechaRegistro', N'Fecha y hora de alta del paciente. Por defecto GETDATE().';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'MedicoID', N'Identificador único del médico (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'Nombre_Medico', N'Nombres del médico.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'Apellido_Medico', N'Apellidos del médico.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'EspecialidadID', N'Especialidad del médico (FK a catalogo.Especialidades).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'LicenciaMedica', N'Número de licencia profesional. Único.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Medicos', N'Email', N'Correo institucional (opcional). Único.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', N'CitaID', N'Identificador único de la cita (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', N'PacienteID', N'Paciente atendido (FK a clinico.Pacientes).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', N'MedicoID', N'Médico que atiende (FK a clinico.Medicos).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', N'FechaHora', N'Fecha y hora programada de la cita.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Citas', N'Estado', N'Estado de la cita: Pendiente, Completada o Cancelada. Por defecto Pendiente.';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', N'TratamientoID', N'Identificador único del tratamiento (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', N'CitaID', N'Cita en la que se indicó el tratamiento (FK a clinico.Citas).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', N'DiagnosticoID', N'Diagnóstico asociado (FK a catalogo.Diagnosticos).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', N'Indicaciones', N'Indicaciones médicas al paciente (opcional).';
EXEC auditoria.usp_DescribirObjeto N'clinico', N'Tratamientos', N'Costo', N'Costo del tratamiento. Debe ser mayor o igual a 0.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'Facturacion', N'FacturaID', N'Identificador único de la factura (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'Facturacion', N'CitaID', N'Cita facturada (FK a clinico.Citas). Única: una factura por cita.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'Facturacion', N'FechaEmision', N'Fecha y hora de emisión. Por defecto GETDATE().';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'Facturacion', N'EstadoPago', N'Estado de pago: Pendiente o Pagado. Por defecto Pendiente.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'DetalleFacturaID', N'Identificador único de la línea (PK, autonumérico).';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'FacturaID', N'Factura a la que pertenece la línea (FK a facturacion.Facturacion).';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'Concepto', N'Descripción del concepto facturado.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'Cantidad', N'Cantidad facturada. Debe ser mayor que 0.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'PrecioUnitario', N'Precio por unidad. Debe ser mayor o igual a 0.';
EXEC auditoria.usp_DescribirObjeto N'facturacion', N'DetalleFactura', N'Subtotal', N'Columna calculada y persistida: Cantidad x PrecioUnitario.';
GO

-- F.1 Diccionario de columnas
SELECT s.name AS Esquema, t.name AS Tabla, c.column_id AS Orden, c.name AS Columna,
       CASE WHEN ty.name IN ('varchar','char','varbinary','binary')
                 THEN ty.name + '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length AS VARCHAR(10)) END + ')'
            WHEN ty.name IN ('nvarchar','nchar')
                 THEN ty.name + '(' + CASE WHEN c.max_length = -1 THEN 'MAX' ELSE CAST(c.max_length / 2 AS VARCHAR(10)) END + ')'
            WHEN ty.name IN ('decimal','numeric')
                 THEN ty.name + '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
            ELSE ty.name END AS TipoDato,
       CASE WHEN c.is_nullable = 1 THEN 'SI' ELSE 'NO' END AS PermiteNulo,
       CASE WHEN EXISTS (SELECT 1 FROM sys.indexes i
                         JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                         WHERE i.object_id = c.object_id AND i.is_primary_key = 1 AND ic.column_id = c.column_id)
            THEN 'PK' ELSE '' END AS Llave,
       ISNULL(fk.Ref, '') AS FK_Referencia,
       CASE WHEN EXISTS (SELECT 1 FROM sys.indexes i
                         JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
                         WHERE i.object_id = c.object_id AND i.is_unique_constraint = 1 AND ic.column_id = c.column_id)
            THEN 'UNIQUE' ELSE '' END AS Unico,
       CONCAT(CASE WHEN c.is_identity = 1 THEN 'IDENTITY ' ELSE '' END,
              CASE WHEN c.is_computed = 1 THEN 'CALCULADA: ' + cc.definition + ' ' ELSE '' END,
              CASE WHEN dc.definition IS NOT NULL THEN 'DEFAULT ' + dc.definition ELSE '' END) AS Otros,
       CAST(ep.value AS NVARCHAR(500)) AS Descripcion
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
LEFT JOIN sys.default_constraints dc ON dc.parent_object_id = c.object_id AND dc.parent_column_id = c.column_id
LEFT JOIN sys.computed_columns cc ON cc.object_id = c.object_id AND cc.column_id = c.column_id
OUTER APPLY (SELECT TOP (1) Ref = SCHEMA_NAME(rt.schema_id) + '.' + rt.name + '(' + rc.name + ')'
             FROM sys.foreign_key_columns fkc
             JOIN sys.tables rt  ON rt.object_id = fkc.referenced_object_id
             JOIN sys.columns rc ON rc.object_id = fkc.referenced_object_id AND rc.column_id = fkc.referenced_column_id
             WHERE fkc.parent_object_id = c.object_id AND fkc.parent_column_id = c.column_id) fk
LEFT JOIN sys.extended_properties ep ON ep.class = 1 AND ep.major_id = c.object_id
                                     AND ep.minor_id = c.column_id AND ep.name = N'MS_Description'
WHERE s.name IN ('catalogo','clinico','facturacion')
ORDER BY s.name, t.name, c.column_id;
GO

-- F.2 Restricciones CHECK
SELECT s.name AS Esquema, t.name AS Tabla, cc.name AS Restriccion, cc.definition AS Regla
FROM sys.check_constraints cc
JOIN sys.tables t  ON t.object_id = cc.parent_object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
ORDER BY s.name, t.name, cc.name;
GO

-- F.3 Relaciones (llaves foraneas) para el diagrama y las cardinalidades
SELECT fk.name AS FK,
       OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS TablaHija,
       COL_NAME(fkc.parent_object_id, fkc.parent_column_id) AS ColumnaHija,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS TablaPadre,
       COL_NAME(fkc.referenced_object_id, fkc.referenced_column_id) AS ColumnaPadre,
       fk.delete_referential_action_desc AS AlBorrar
FROM sys.foreign_keys fk
JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id = fk.object_id
ORDER BY TablaHija, fk.name;
GO



/* =====================================================================
   8. DIMENSIONAMIENTO DE LA BASE DE DATOS
   ===================================================================== */
USE HospitalDB;
GO
SET NOCOUNT ON;

DECLARE @CitasPorMes   INT          = 1500;   -- supuesto de crecimiento
DECLARE @FactorLog     DECIMAL(4,2) = 0.30;   -- log = 30% de (datos + indices)
DECLARE @FactorTempdb  DECIMAL(4,2) = 0.20;   -- tempdb (sorts de funciones ventana) = 20%
DECLARE @FactorIdx     DECIMAL(6,3);
DECLARE @CitasHoy      BIGINT;

-- 1) Parametros por tabla (tamanos fijos segun el DDL; variables medidos)
IF OBJECT_ID('tempdb..#dim') IS NOT NULL DROP TABLE #dim;
CREATE TABLE #dim (Esquema SYSNAME, Tabla SYSNAME, ColsTotal INT, ColsVar INT,
                   BytesFijos INT, BytesVarProm DECIMAL(10,2), Crece BIT);

INSERT INTO #dim (Esquema, Tabla, ColsTotal, ColsVar, BytesFijos, BytesVarProm, Crece)
SELECT 'catalogo','Especialidades', 3, 2, 4,
       (SELECT ISNULL(AVG(1.0 * (ISNULL(DATALENGTH(Nombre),0) + ISNULL(DATALENGTH(Descripcion),0))), 0) FROM catalogo.Especialidades), 0
UNION ALL
SELECT 'catalogo','Diagnosticos', 3, 2, 4,
       (SELECT ISNULL(AVG(1.0 * (ISNULL(DATALENGTH(Nombre_Diagnostico),0) + ISNULL(DATALENGTH(Descripcion),0))), 0) FROM catalogo.Diagnosticos), 0
UNION ALL
SELECT 'clinico','Pacientes', 7, 4, 15,   -- INT 4 + DATE 3 + DATETIME 8
       (SELECT ISNULL(AVG(1.0 * (ISNULL(DATALENGTH(Nombre_Paciente),0) + ISNULL(DATALENGTH(Apellido_Paciente),0)
                               + ISNULL(DATALENGTH(Telefono),0) + ISNULL(DATALENGTH(Email),0))), 0) FROM clinico.Pacientes), 1
UNION ALL
SELECT 'clinico','Medicos', 6, 4, 8,      -- INT 4 + INT 4
       (SELECT ISNULL(AVG(1.0 * (ISNULL(DATALENGTH(Nombre_Medico),0) + ISNULL(DATALENGTH(Apellido_Medico),0)
                               + ISNULL(DATALENGTH(LicenciaMedica),0) + ISNULL(DATALENGTH(Email),0))), 0) FROM clinico.Medicos), 0
UNION ALL
SELECT 'clinico','Citas', 5, 1, 20,       -- 3 INT (12) + DATETIME 8
       (SELECT ISNULL(AVG(1.0 * ISNULL(DATALENGTH(Estado),0)), 0) FROM clinico.Citas), 1
UNION ALL
SELECT 'clinico','Tratamientos', 5, 1, 21,-- 3 INT (12) + DECIMAL(10,2) 9
       (SELECT ISNULL(AVG(1.0 * ISNULL(DATALENGTH(Indicaciones),0)), 0) FROM clinico.Tratamientos), 1
UNION ALL
SELECT 'facturacion','Facturacion', 4, 1, 16, -- 2 INT (8) + DATETIME 8
       (SELECT ISNULL(AVG(1.0 * ISNULL(DATALENGTH(EstadoPago),0)), 0) FROM facturacion.Facturacion), 1
UNION ALL
SELECT 'facturacion','DetalleFactura', 6, 1, 30, -- 3 INT (12) + 2 DECIMAL(10,2) (18)
       (SELECT ISNULL(AVG(1.0 * ISNULL(DATALENGTH(Concepto),0)), 0) FROM facturacion.DetalleFactura), 1;

-- 2) Calculo por tabla
IF OBJECT_ID('tempdb..#res') IS NOT NULL DROP TABLE #res;
SELECT d.Esquema, d.Tabla, d.Crece,
       Filas     = ISNULL(st.Filas, 0),
       BytesFila = CAST(d.BytesFijos + (2 + 2 * d.ColsVar + d.BytesVarProm) + (2 + (d.ColsTotal + 7) / 8) + 4 AS DECIMAL(10,2)),
       FPP       = f.FPP,
       Paginas   = CAST(CEILING(CASE WHEN ISNULL(st.Filas, 0) = 0 THEN 0 ELSE st.Filas / f.FPP END) AS BIGINT),
       PaginasReales = rl.Pag
INTO #res
FROM #dim d
OUTER APPLY (SELECT Filas = SUM(ps.row_count)
             FROM sys.dm_db_partition_stats ps
             WHERE ps.object_id = OBJECT_ID(QUOTENAME(d.Esquema) + '.' + QUOTENAME(d.Tabla)) AND ps.index_id IN (0,1)) st
CROSS APPLY (SELECT FPP = FLOOR(8096.0 / (d.BytesFijos + (2 + 2 * d.ColsVar + d.BytesVarProm) + (2 + (d.ColsTotal + 7) / 8) + 4 + 2))) f
OUTER APPLY (SELECT Pag = SUM(ps.used_page_count)
             FROM sys.dm_db_partition_stats ps
             WHERE ps.object_id = OBJECT_ID(QUOTENAME(d.Esquema) + '.' + QUOTENAME(d.Tabla)) AND ps.index_id IN (0,1)) rl;

-- 3) Factor de indices medido
SELECT @FactorIdx = CAST(
           SUM(CASE WHEN ps.index_id > 1 THEN ps.used_page_count ELSE 0 END) * 1.0
         / NULLIF(SUM(CASE WHEN ps.index_id IN (0,1) THEN ps.used_page_count ELSE 0 END), 0) AS DECIMAL(6,3))
FROM sys.dm_db_partition_stats ps
JOIN sys.tables t  ON t.object_id = ps.object_id
JOIN sys.schemas s ON s.schema_id = t.schema_id
WHERE s.name IN ('catalogo','clinico','facturacion');
SET @FactorIdx = ISNULL(@FactorIdx, 0.40);
SET @CitasHoy  = (SELECT Filas FROM #res WHERE Tabla = 'Citas');

-- G.1 Dimensionamiento por tabla: estimado vs real
SELECT Esquema, Tabla, Filas, BytesFila AS Bytes_por_fila, CAST(FPP AS INT) AS Filas_por_pagina,
       Paginas AS Paginas_estimadas,
       CAST(Paginas * 8 / 1024.0 AS DECIMAL(10,2))        AS MB_estimado,
       CAST(PaginasReales * 8 / 1024.0 AS DECIMAL(10,2))  AS MB_real
FROM #res
ORDER BY Esquema, Tabla;

-- G.2 Totales y factor de indices
SELECT CAST(SUM(Paginas) * 8 / 1024.0 AS DECIMAL(10,2))       AS MB_datos_estimado,
       CAST(SUM(PaginasReales) * 8 / 1024.0 AS DECIMAL(10,2)) AS MB_datos_real,
       @FactorIdx                                             AS Factor_indices_medido,
       CAST(SUM(Paginas) * 8 / 1024.0 * (1 + @FactorIdx) AS DECIMAL(10,2)) AS MB_datos_mas_indices
FROM #res;

-- G.3 Proyeccion (0 = hoy, 1 y 3 anos) con indices, log y tempdb
SELECT a.Anios AS Anios_proyeccion,
       CAST(SUM(x.MB) AS DECIMAL(12,2))                                         AS MB_datos,
       CAST(SUM(x.MB) * @FactorIdx AS DECIMAL(12,2))                            AS MB_indices,
       CAST(SUM(x.MB) * (1 + @FactorIdx) * @FactorLog AS DECIMAL(12,2))         AS MB_log,
       CAST(SUM(x.MB) * (1 + @FactorIdx) * (1 + @FactorLog) AS DECIMAL(12,2))   AS MB_total_base,
       CAST(SUM(x.MB) * (1 + @FactorIdx) * @FactorTempdb AS DECIMAL(12,2))      AS MB_tempdb_aparte
FROM (VALUES (0), (1), (3)) AS a(Anios)
CROSS JOIN #res r
CROSS APPLY (SELECT FilasProy = r.Filas + CASE WHEN r.Crece = 1
                                                THEN r.Filas * 1.0 / @CitasHoy * @CitasPorMes * 12 * a.Anios
                                                ELSE 0 END) fp
CROSS APPLY (SELECT MB = CEILING(fp.FilasProy / r.FPP) * 8 / 1024.0) x
GROUP BY a.Anios
ORDER BY a.Anios;
GO

-- G.4 Comparacion con el tamano real de la base y de las tablas
EXEC sp_spaceused;
EXEC sp_spaceused 'clinico.Citas';
EXEC sp_spaceused 'facturacion.DetalleFactura';
SELECT name AS archivo, type_desc, CAST(size * 8 / 1024.0 AS DECIMAL(10,2)) AS MB_asignado
FROM sys.database_files;
GO
/* =====================================================================
   9. COPIAS DE SEGURIDAD, SQL AGENT Y RESTAURACION 

   OBJETIVOS DE RECUPERACION (hospital)
     RPO = 15 minutos : maxima perdida de datos tolerable (backup de log cada 15 min)
     RTO = 60 minutos : tiempo maximo para restaurar (se mide en el simulacro)
     WRT / MTD        : tiempo para verificar y reabrir el sistema / tiempo maximo
                        sin servicio; se consideran dentro del margen del RTO.

   ANALISIS =. Falla el jueves 4:30 p. m.
   hora El Salvador; Completo domingo 0:00, Diferencial diario 0:00, Log cada 15 min:
     Estrategia unica      | Ultimo respaldo     | RPO (horas perdidas) | RTO (respaldos a restaurar)
     Solo completo         | Domingo 0:00        | 112.5                | 1
     Completo+Diferencial  | Jueves 0:00         | 16.5                 | 2
     Completo+Dif.+Log     | Jueves 4:15 p. m.   | 0.25 (15 min)        | 67 (1 completo + 1 dif. + 65 logs)
   El log (el "incremental" de SQL Server) da el RPO mas bajo pero alarga el RTO:
   por eso se combina con el diferencial diario, que limita la cadena de logs a
   un maximo de 95 por dia. BACKUP LOG exige el modelo de recuperacion FULL
   (en SIMPLE falla con el error 4208); la base ya se creo en FULL.

   CALENDARIO (SQL Agent usa el reloj del servidor, que en el contenedor es UTC;
   las 06:00 UTC son las 00:00 de El Salvador):
     FULL         Domingo 00:00 (06:00 UTC)             Base de la cadena de restauracion
     DIFERENCIAL  Lunes a sabado 00:00 (06:00 UTC)      Acorta la cadena y cuida el RTO
     LOG          Cada 15 minutos todos los dias        Cumple el RPO
   Los archivos llevan fecha y hora en el nombre para conservar toda la cadena
   (un nombre fijo con INIT sobrescribiria los logs). Retencion: 2 semanas.
   Los jobs notifican a operador_dba si fallan (@notify_level_email = 2); 
   ===================================================================== */
USE msdb;
GO

-- Limpieza para poder re-ejecutar (guia: limpieza opcional)
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'HospitalDB - Backup FULL') EXEC dbo.sp_delete_job @job_name = N'HospitalDB - Backup FULL', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'HospitalDB - Backup DIFF') EXEC dbo.sp_delete_job @job_name = N'HospitalDB - Backup DIFF', @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name = N'HospitalDB - Backup LOG')  EXEC dbo.sp_delete_job @job_name = N'HospitalDB - Backup LOG',  @delete_unused_schedule = 1;
IF EXISTS (SELECT 1 FROM dbo.sysoperators WHERE name = N'operador_dba')        EXEC dbo.sp_delete_operator @name = N'operador_dba';
GO

-- Operador que recibe la notificacion cuando un job falla
EXEC dbo.sp_add_operator @name = N'operador_dba', @email_address = N'dba@hospital.local';
GO

DECLARE @cmd NVARCHAR(MAX);

-- ===== JOB 1: FULL (domingos 00:00 hora El Salvador) =====
EXEC dbo.sp_add_job
     @job_name = N'HospitalDB - Backup FULL',
     @description = N'Respaldo completo semanal. Base de la cadena de restauracion.',
     @notify_level_email = 2,
     @notify_email_operator_name = N'operador_dba';
SET @cmd = N'
DECLARE @f NVARCHAR(260) = N''/backup/HospitalDB/HospitalDB_FULL_'' + CONVERT(NVARCHAR(8), GETDATE(), 112) + N''_'' + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), N'':'', N'''') + N''.bak'';
BACKUP DATABASE HospitalDB TO DISK = @f WITH INIT, COMPRESSION, NAME = N''Respaldo completo HospitalDB'';';
EXEC dbo.sp_add_jobstep
     @job_name = N'HospitalDB - Backup FULL', @step_name = N'Respaldo completo',
     @subsystem = N'TSQL', @database_name = N'master', @command = @cmd;
EXEC dbo.sp_add_schedule
     @schedule_name = N'Domingo 00:00 SV (06:00 UTC)',
     @freq_type = 8, @freq_interval = 1, @freq_recurrence_factor = 1, @active_start_time = 060000;
EXEC dbo.sp_attach_schedule
     @job_name = N'HospitalDB - Backup FULL', @schedule_name = N'Domingo 00:00 SV (06:00 UTC)';
EXEC dbo.sp_add_jobserver @job_name = N'HospitalDB - Backup FULL';

-- ===== JOB 2: DIFERENCIAL (lunes a sabado 00:00; interval 126 = 2+4+8+16+32+64) =====
EXEC dbo.sp_add_job
     @job_name = N'HospitalDB - Backup DIFF',
     @description = N'Respaldo diferencial diario. Reduce el RTO.',
     @notify_level_email = 2,
     @notify_email_operator_name = N'operador_dba';
SET @cmd = N'
DECLARE @f NVARCHAR(260) = N''/backup/HospitalDB/HospitalDB_DIFF_'' + CONVERT(NVARCHAR(8), GETDATE(), 112) + N''_'' + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), N'':'', N'''') + N''.bak'';
BACKUP DATABASE HospitalDB TO DISK = @f WITH DIFFERENTIAL, INIT, COMPRESSION, NAME = N''Respaldo diferencial HospitalDB'';';
EXEC dbo.sp_add_jobstep
     @job_name = N'HospitalDB - Backup DIFF', @step_name = N'Respaldo diferencial',
     @subsystem = N'TSQL', @database_name = N'master', @command = @cmd;
EXEC dbo.sp_add_schedule
     @schedule_name = N'Lunes a Sabado 00:00 SV (06:00 UTC)',
     @freq_type = 8, @freq_interval = 126, @freq_recurrence_factor = 1, @active_start_time = 060000;
EXEC dbo.sp_attach_schedule
     @job_name = N'HospitalDB - Backup DIFF', @schedule_name = N'Lunes a Sabado 00:00 SV (06:00 UTC)';
EXEC dbo.sp_add_jobserver @job_name = N'HospitalDB - Backup DIFF';

-- ===== JOB 3: LOG (cada 15 minutos, todos los dias) =====
EXEC dbo.sp_add_job
     @job_name = N'HospitalDB - Backup LOG',
     @description = N'Respaldo del log de transacciones cada 15 min. Cumple el RPO.',
     @notify_level_email = 2,
     @notify_email_operator_name = N'operador_dba';
SET @cmd = N'
DECLARE @f NVARCHAR(260) = N''/backup/HospitalDB/HospitalDB_LOG_'' + CONVERT(NVARCHAR(8), GETDATE(), 112) + N''_'' + REPLACE(CONVERT(NVARCHAR(8), GETDATE(), 108), N'':'', N'''') + N''.trn'';
BACKUP LOG HospitalDB TO DISK = @f WITH INIT, COMPRESSION, NAME = N''Respaldo del log HospitalDB'';';
EXEC dbo.sp_add_jobstep
     @job_name = N'HospitalDB - Backup LOG', @step_name = N'Respaldo del log',
     @subsystem = N'TSQL', @database_name = N'master', @command = @cmd;
EXEC dbo.sp_add_schedule
     @schedule_name = N'Cada 15 minutos',
     @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 15,
     @active_start_time = 0, @active_end_time = 235959;
EXEC dbo.sp_attach_schedule
     @job_name = N'HospitalDB - Backup LOG', @schedule_name = N'Cada 15 minutos';
EXEC dbo.sp_add_jobserver @job_name = N'HospitalDB - Backup LOG';
GO

-- Ejecutar los jobs de inmediato, en orden, para tener evidencia sin esperar
BEGIN TRY
    EXEC msdb.dbo.sp_start_job @job_name = N'HospitalDB - Backup FULL';
    WAITFOR DELAY '00:00:20';
    EXEC msdb.dbo.sp_start_job @job_name = N'HospitalDB - Backup DIFF';
    WAITFOR DELAY '00:00:20';
    EXEC msdb.dbo.sp_start_job @job_name = N'HospitalDB - Backup LOG';
    WAITFOR DELAY '00:00:20';
END TRY
BEGIN CATCH
    PRINT 'No se pudo iniciar un job (verifique que SQL Server Agent este activo): ' + ERROR_MESSAGE();
END CATCH
GO

-- Evidencia 1: historial de ejecucion (run_status = 1 indica exito)
SELECT j.name AS job, h.step_name, h.run_status,
       CASE h.run_status WHEN 0 THEN 'Fallo' WHEN 1 THEN 'Exitoso' WHEN 2 THEN 'Reintento' WHEN 3 THEN 'Cancelado' END AS estado,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS inicio_utc, h.message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name LIKE N'HospitalDB%' AND h.step_id > 0
ORDER BY inicio_utc DESC;
GO
-- Evidencia 2: calendario de cada job
SELECT j.name AS job, sc.name AS horario, j.enabled AS activo,
       CASE sc.freq_type WHEN 4 THEN 'Diario' WHEN 8 THEN 'Semanal' END AS frecuencia,
       sc.freq_interval, sc.freq_subday_interval AS cada_n_minutos, sc.active_start_time AS hora_inicio_utc
FROM msdb.dbo.sysjobs j
JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
JOIN msdb.dbo.sysschedules sc ON sc.schedule_id = js.schedule_id
WHERE j.name LIKE N'HospitalDB%'
ORDER BY j.name;
GO
-- Evidencia 3: respaldos generados (tipo, tamano, archivo)
SELECT CASE bs.type WHEN 'D' THEN 'FULL' WHEN 'I' THEN 'DIFF' WHEN 'L' THEN 'LOG' END AS tipo,
       bs.backup_start_date AS inicio,
       DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS segundos,
       CAST(bs.backup_size / 1048576.0 AS DECIMAL(10,2)) AS MB,
       CAST(bs.compressed_backup_size / 1048576.0 AS DECIMAL(10,2)) AS MB_comprimido,
       bmf.physical_device_name AS archivo
FROM msdb.dbo.backupset bs
JOIN msdb.dbo.backupmediafamily bmf ON bmf.media_set_id = bs.media_set_id
WHERE bs.database_name = N'HospitalDB'
ORDER BY bs.backup_start_date DESC;
GO
-- Evidencia 4 (PowerShell): docker exec sqlserver-2025 ls -l /backup/HospitalDB
-- Evidencia 5 (SSMS): Agente SQL Server > Trabajos > clic derecho > Ver historial

USE HospitalDB;
GO
