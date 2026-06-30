/*
ED04 — Desempenho em Banco de Dados
SGBD: SQL Server
Cenário: Sistema Hospitalar
Objetivo: criar um banco de exemplo e demonstrar as 7 estratégias:
1) Análise de consultas SQL
2) Otimização de índices
3) Otimização de consultas
4) Estrutura e modelagem
5) Particionamento
6) Monitoramento e gargalos
7) Cache e escalabilidade
*/

/* 0. CRIAÇÃO DO BANCO */

IF DB_ID('ED04_Hospital_Performance') IS NOT NULL
BEGIN
    ALTER DATABASE ED04_Hospital_Performance SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ED04_Hospital_Performance;
END;
GO

CREATE DATABASE ED04_Hospital_Performance;
GO

USE ED04_Hospital_Performance;
GO

/* 1. MODELAGEM NORMALIZADA DO CENÁRIO HOSPITALAR */

CREATE TABLE dbo.Convenio (
    ConvenioID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Convenio PRIMARY KEY,
    Nome NVARCHAR(120) NOT NULL,
    Ativo BIT NOT NULL CONSTRAINT DF_Convenio_Ativo DEFAULT (1)
);
GO

CREATE TABLE dbo.Especialidade (
    EspecialidadeID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Especialidade PRIMARY KEY,
    Nome NVARCHAR(120) NOT NULL
);
GO

CREATE TABLE dbo.Medico (
    MedicoID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Medico PRIMARY KEY,
    Nome NVARCHAR(160) NOT NULL,
    CRM NVARCHAR(30) NOT NULL,
    EspecialidadeID INT NOT NULL,
    Ativo BIT NOT NULL CONSTRAINT DF_Medico_Ativo DEFAULT (1),
    CONSTRAINT FK_Medico_Especialidade FOREIGN KEY (EspecialidadeID) REFERENCES dbo.Especialidade(EspecialidadeID)
);
GO

CREATE TABLE dbo.Paciente (
    PacienteID INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Paciente PRIMARY KEY,
    Nome NVARCHAR(160) NOT NULL,
    CPF CHAR(11) NOT NULL,
    DataNascimento DATE NOT NULL,
    Sexo CHAR(1) NULL,
    ConvenioID INT NULL,
    DataCadastro DATETIME2(0) NOT NULL CONSTRAINT DF_Paciente_DataCadastro DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT UQ_Paciente_CPF UNIQUE (CPF),
    CONSTRAINT FK_Paciente_Convenio FOREIGN KEY (ConvenioID) REFERENCES dbo.Convenio(ConvenioID)
);
GO

CREATE TABLE dbo.Consulta (
    ConsultaID BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Consulta PRIMARY KEY,
    PacienteID INT NOT NULL,
    MedicoID INT NOT NULL,
    DataConsulta DATETIME2(0) NOT NULL,
    StatusConsulta VARCHAR(20) NOT NULL,
    Valor DECIMAL(12,2) NOT NULL,
    Observacao NVARCHAR(500) NULL,
    CONSTRAINT FK_Consulta_Paciente FOREIGN KEY (PacienteID) REFERENCES dbo.Paciente(PacienteID),
    CONSTRAINT FK_Consulta_Medico FOREIGN KEY (MedicoID) REFERENCES dbo.Medico(MedicoID),
    CONSTRAINT CK_Consulta_Status CHECK (StatusConsulta IN ('AGENDADA','REALIZADA','CANCELADA'))
);
GO

CREATE TABLE dbo.Exame (
    ExameID BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Exame PRIMARY KEY,
    ConsultaID BIGINT NOT NULL,
    TipoExame NVARCHAR(120) NOT NULL,
    DataSolicitacao DATETIME2(0) NOT NULL,
    DataResultado DATETIME2(0) NULL,
    StatusExame VARCHAR(20) NOT NULL,
    CONSTRAINT FK_Exame_Consulta FOREIGN KEY (ConsultaID) REFERENCES dbo.Consulta(ConsultaID),
    CONSTRAINT CK_Exame_Status CHECK (StatusExame IN ('SOLICITADO','COLETADO','FINALIZADO','CANCELADO'))
);
GO

CREATE TABLE dbo.Pagamento (
    PagamentoID BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Pagamento PRIMARY KEY,
    ConsultaID BIGINT NOT NULL,
    DataPagamento DATETIME2(0) NOT NULL,
    ValorPago DECIMAL(12,2) NOT NULL,
    FormaPagamento VARCHAR(30) NOT NULL,
    CONSTRAINT FK_Pagamento_Consulta FOREIGN KEY (ConsultaID) REFERENCES dbo.Consulta(ConsultaID)
);
GO

/* 2. CARGA DE DADOS DE EXEMPLO */

INSERT INTO dbo.Convenio (Nome) VALUES
('Particular'), ('Unimed'), ('SulAmérica'), ('Bradesco Saúde'), ('Amil');
GO

INSERT INTO dbo.Especialidade (Nome) VALUES
('Clínica Geral'), ('Cardiologia'), ('Ortopedia'), ('Pediatria'), ('Dermatologia');
GO

INSERT INTO dbo.Medico (Nome, CRM, EspecialidadeID) VALUES
('Dra. Ana Martins', 'CRM1001', 1),
('Dr. Bruno Lima', 'CRM1002', 2),
('Dra. Carla Souza', 'CRM1003', 3),
('Dr. Diego Rocha', 'CRM1004', 4),
('Dra. Elisa Castro', 'CRM1005', 5);
GO

;WITH N AS (
    SELECT TOP (5000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Paciente (Nome, CPF, DataNascimento, Sexo, ConvenioID)
SELECT
    CONCAT('Paciente ', n),
    RIGHT(CONCAT('00000000000', n), 11),
    DATEADD(DAY, -1 * (7000 + n), CAST('2026-01-01' AS DATE)),
    CASE WHEN n % 2 = 0 THEN 'F' ELSE 'M' END,
    1 + (n % 5)
FROM N;
GO

;WITH N AS (
    SELECT TOP (80000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
)
INSERT INTO dbo.Consulta (PacienteID, MedicoID, DataConsulta, StatusConsulta, Valor, Observacao)
SELECT
    1 + (n % 5000),
    1 + (n % 5),
    DATEADD(MINUTE, n, CAST('2024-01-01T08:00:00' AS DATETIME2(0))),
    CASE WHEN n % 10 = 0 THEN 'CANCELADA' WHEN n % 3 = 0 THEN 'AGENDADA' ELSE 'REALIZADA' END,
    CAST(100 + (n % 900) AS DECIMAL(12,2)),
    CASE WHEN n % 20 = 0 THEN 'Retorno prioritário' ELSE NULL END
FROM N;
GO

INSERT INTO dbo.Exame (ConsultaID, TipoExame, DataSolicitacao, DataResultado, StatusExame)
SELECT TOP (25000)
    ConsultaID,
    CASE WHEN ConsultaID % 4 = 0 THEN 'Hemograma' WHEN ConsultaID % 4 = 1 THEN 'Raio-X' WHEN ConsultaID % 4 = 2 THEN 'Ultrassom' ELSE 'Eletrocardiograma' END,
    DataConsulta,
    CASE WHEN ConsultaID % 5 = 0 THEN NULL ELSE DATEADD(DAY, 2, DataConsulta) END,
    CASE WHEN ConsultaID % 5 = 0 THEN 'SOLICITADO' ELSE 'FINALIZADO' END
FROM dbo.Consulta
ORDER BY ConsultaID;
GO

INSERT INTO dbo.Pagamento (ConsultaID, DataPagamento, ValorPago, FormaPagamento)
SELECT ConsultaID, DATEADD(DAY, 1, DataConsulta), Valor,
       CASE WHEN ConsultaID % 3 = 0 THEN 'CARTAO' WHEN ConsultaID % 3 = 1 THEN 'PIX' ELSE 'DINHEIRO' END
FROM dbo.Consulta
WHERE StatusConsulta = 'REALIZADA';
GO

/* TÓPICO 1 — ANÁLISE DE CONSULTAS SQL */

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Consulta inicial a ser analisada: tende a ler muitos dados antes dos índices.
SELECT *
FROM dbo.Consulta
WHERE StatusConsulta = 'REALIZADA'
  AND DataConsulta >= '2025-01-01'
  AND DataConsulta <  '2026-01-01';
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* TÓPICO 2 — OTIMIZAÇÃO DE ÍNDICES */

CREATE INDEX IX_Consulta_Status_Data
ON dbo.Consulta (StatusConsulta, DataConsulta)
INCLUDE (PacienteID, MedicoID, Valor);
GO

CREATE INDEX IX_Consulta_Paciente_Data
ON dbo.Consulta (PacienteID, DataConsulta DESC)
INCLUDE (StatusConsulta, Valor, MedicoID);
GO

CREATE INDEX IX_Consulta_Medico_Data
ON dbo.Consulta (MedicoID, DataConsulta DESC)
INCLUDE (StatusConsulta, Valor, PacienteID);
GO

CREATE INDEX IX_Exame_Status_DataSolicitacao
ON dbo.Exame (StatusExame, DataSolicitacao)
INCLUDE (ConsultaID, TipoExame);
GO

CREATE INDEX IX_Pagamento_DataPagamento
ON dbo.Pagamento (DataPagamento)
INCLUDE (ConsultaID, ValorPago, FormaPagamento);
GO

/* TÓPICO 3 — OTIMIZAÇÃO DE CONSULTAS SQL */

-- Consulta pouco eficiente: SELECT *, função na coluna e filtro tardio.
SELECT *
FROM dbo.Consulta
WHERE YEAR(DataConsulta) = 2024
  AND StatusConsulta = 'REALIZADA';
GO

-- Consulta otimizada: colunas necessárias e intervalo sargable.
SELECT ConsultaID, PacienteID, MedicoID, DataConsulta, Valor
FROM dbo.Consulta
WHERE DataConsulta >= '2024-01-01'
  AND DataConsulta <  '2025-01-01'
  AND StatusConsulta = 'REALIZADA';
GO

-- Consulta com JOIN otimizado.
SELECT
    c.ConsultaID,
    p.Nome AS Paciente,
    m.Nome AS Medico,
    e.Nome AS Especialidade,
    c.DataConsulta,
    c.Valor
FROM dbo.Consulta c
INNER JOIN dbo.Paciente p ON p.PacienteID = c.PacienteID
INNER JOIN dbo.Medico m ON m.MedicoID = c.MedicoID
INNER JOIN dbo.Especialidade e ON e.EspecialidadeID = m.EspecialidadeID
WHERE c.DataConsulta >= '2024-01-01'
  AND c.DataConsulta <  '2025-01-01'
  AND c.StatusConsulta = 'REALIZADA';
GO

/* TÓPICO 4 — ESTRUTURA E MODELAGEM
   Exemplo de desnormalização controlada: resumo mensal para relatórios. */

CREATE TABLE dbo.ResumoConsultaMensal (
    AnoMes CHAR(7) NOT NULL,
    MedicoID INT NOT NULL,
    TotalConsultas INT NOT NULL,
    ValorTotal DECIMAL(14,2) NOT NULL,
    CONSTRAINT PK_ResumoConsultaMensal PRIMARY KEY (AnoMes, MedicoID),
    CONSTRAINT FK_ResumoConsultaMensal_Medico FOREIGN KEY (MedicoID) REFERENCES dbo.Medico(MedicoID)
);
GO

INSERT INTO dbo.ResumoConsultaMensal (AnoMes, MedicoID, TotalConsultas, ValorTotal)
SELECT
    CONVERT(CHAR(7), DataConsulta, 120) AS AnoMes,
    MedicoID,
    COUNT(*) AS TotalConsultas,
    SUM(Valor) AS ValorTotal
FROM dbo.Consulta
WHERE StatusConsulta = 'REALIZADA'
GROUP BY CONVERT(CHAR(7), DataConsulta, 120), MedicoID;
GO

SELECT *
FROM dbo.ResumoConsultaMensal
ORDER BY AnoMes, MedicoID;
GO

/* TÓPICO 5 — PARTICIONAMENTO DE DADOS
   Script conceitual/prático. Em ambientes reais, pode exigir filegroups. */

CREATE PARTITION FUNCTION pfConsultaAno (DATETIME2(0))
AS RANGE RIGHT FOR VALUES
('2024-01-01', '2025-01-01', '2026-01-01', '2027-01-01');
GO

CREATE PARTITION SCHEME psConsultaAno
AS PARTITION pfConsultaAno
ALL TO ([PRIMARY]);
GO

CREATE TABLE dbo.ConsultaParticionada (
    ConsultaID BIGINT NOT NULL,
    PacienteID INT NOT NULL,
    MedicoID INT NOT NULL,
    DataConsulta DATETIME2(0) NOT NULL,
    StatusConsulta VARCHAR(20) NOT NULL,
    Valor DECIMAL(12,2) NOT NULL,
    CONSTRAINT PK_ConsultaParticionada PRIMARY KEY CLUSTERED (DataConsulta, ConsultaID)
        ON psConsultaAno(DataConsulta)
) ON psConsultaAno(DataConsulta);
GO

INSERT INTO dbo.ConsultaParticionada (ConsultaID, PacienteID, MedicoID, DataConsulta, StatusConsulta, Valor)
SELECT ConsultaID, PacienteID, MedicoID, DataConsulta, StatusConsulta, Valor
FROM dbo.Consulta;
GO

SELECT
    $PARTITION.pfConsultaAno(DataConsulta) AS NumeroParticao,
    COUNT(*) AS TotalRegistros
FROM dbo.ConsultaParticionada
GROUP BY $PARTITION.pfConsultaAno(DataConsulta)
ORDER BY NumeroParticao;
GO

/* MONITORAMENTO E IDENTIFICAÇÃO DE GARGALOS */

-- Consultas mais custosas em cache no SQL Server.
SELECT TOP (10)
    qs.total_elapsed_time / NULLIF(qs.execution_count, 0) AS TempoMedio,
    qs.execution_count,
    qs.total_logical_reads,
    qs.total_worker_time,
    SUBSTRING(st.text, (qs.statement_start_offset / 2) + 1,
        ((CASE qs.statement_end_offset WHEN -1 THEN DATALENGTH(st.text) ELSE qs.statement_end_offset END
          - qs.statement_start_offset) / 2) + 1) AS ConsultaSQL
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
ORDER BY TempoMedio DESC;
GO

-- Sessões bloqueadas e bloqueadoras.
SELECT
    r.session_id,
    r.blocking_session_id,
    r.status,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.total_elapsed_time,
    DB_NAME(r.database_id) AS Banco
FROM sys.dm_exec_requests r
WHERE r.blocking_session_id <> 1;
GO

-- Fragmentação dos índices do banco.
SELECT
    OBJECT_NAME(ips.object_id) AS Tabela,
    i.name AS Indice,
    ips.avg_fragmentation_in_percent,
    ips.page_count
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.object_id = i.object_id
   AND ips.index_id = i.index_id
WHERE ips.page_count > 100
ORDER BY ips.avg_fragmentation_in_percent DESC;
GO

-- Recomendações de manutenção, se necessário:
-- ALTER INDEX ALL ON dbo.Consulta REORGANIZE;
-- ALTER INDEX ALL ON dbo.Consulta REBUILD;
-- UPDATE STATISTICS dbo.Consulta;

/* TÓPICO 7 — CACHE E ESCALABILIDADE */

-- Cache interno/materializado por tabela de resumo.
CREATE OR ALTER PROCEDURE dbo.sp_AtualizarResumoConsultaMensal
AS
BEGIN
    SET NOCOUNT ON;

    TRUNCATE TABLE dbo.ResumoConsultaMensal;

    INSERT INTO dbo.ResumoConsultaMensal (AnoMes, MedicoID, TotalConsultas, ValorTotal)
    SELECT
        CONVERT(CHAR(7), DataConsulta, 120) AS AnoMes,
        MedicoID,
        COUNT(*) AS TotalConsultas,
        SUM(Valor) AS ValorTotal
    FROM dbo.Consulta
    WHERE StatusConsulta = 'REALIZADA'
    GROUP BY CONVERT(CHAR(7), DataConsulta, 120), MedicoID;
END;
GO

EXEC dbo.sp_AtualizarResumoConsultaMensal;
GO

-- Exemplo de leitura rápida usando resumo em vez de varrer a tabela grande.
SELECT
    r.AnoMes,
    m.Nome AS Medico,
    r.TotalConsultas,
    r.ValorTotal
FROM dbo.ResumoConsultaMensal r
INNER JOIN dbo.Medico m ON m.MedicoID = r.MedicoID
ORDER BY r.AnoMes, m.Nome;
GO

/* QUERY STORE — RECURSO NATIVO PARA ANÁLISE DE PERFORMANCE */

ALTER DATABASE ED04_Hospital_Performance
SET QUERY_STORE = ON;
GO

ALTER DATABASE ED04_Hospital_Performance
SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 100
);
GO
