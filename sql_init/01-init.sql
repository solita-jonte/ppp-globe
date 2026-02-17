-- Variables:
--   $(SQL_DB_NAME) is provided by sqlcmd -v SQL_DB_NAME="PppDb"

DECLARE @DbName sysname = '$(SQL_DB_NAME)';
DECLARE @DbNameQuoted nvarchar(260) = QUOTENAME(@DbName);

IF DB_NAME() = N'master'
BEGIN
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'PppDb')
    BEGIN
        DECLARE @CreateDbSql nvarchar(max) = 'CREATE DATABASE ' + @DbNameQuoted;
        EXEC(@CreateDbSql);
    END;
END;
GO
