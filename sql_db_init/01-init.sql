IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'PppDb')
BEGIN
    CREATE DATABASE PppDb;
END
GO

USE PppDb;
GO

IF OBJECT_ID('dbo.Country', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Country
    (
        Id       INT IDENTITY(1,1) PRIMARY KEY,
        Iso2     CHAR(2) NOT NULL UNIQUE,
        Name     NVARCHAR(200) NOT NULL
    );
END
GO

IF OBJECT_ID('dbo.PppGdpPerCapita', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.PppGdpPerCapita
    (
        Id         INT IDENTITY(1,1) PRIMARY KEY,
        CountryId  INT NOT NULL,
        Year       INT NOT NULL,
        Value      DECIMAL(18, 2) NULL,
        Source     NVARCHAR(50) NOT NULL DEFAULT 'WorldBank',
        CONSTRAINT FK_PppGdpPerCapita_Country FOREIGN KEY (CountryId)
            REFERENCES dbo.Country(Id),
        CONSTRAINT UQ_PppGdpPerCapita_CountryYear UNIQUE (CountryId, Year)
    );
END
GO
