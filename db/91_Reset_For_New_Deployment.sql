/* =====================================================================
   91_Reset_For_New_Deployment.sql  -  HRMS: clear the company data
   ---------------------------------------------------------------------
   For a FRESH DEPLOYMENT: removes every company, employee, payroll,
   leave, asset and document record so the database holds only the
   structure and the shared set-up. The rows are really removed (not
   flagged as deleted) and the numbering starts again from 1.

   CLEARED (all rows)
     Core       Companies, Branches, Departments, Sections, Positions,
                Designations, Grades, Cost Centers, Locations
     Employee   every table (employees, payroll details, dependents,
                audit log, ...)
     Kuwait     employee compliance (civil ID, passport, work permit)
     Payroll    every company table: calendars, periods, pay components,
                pay items, payrolls, payslips, final settlements, bank
                files, journals, company bank accounts, policies ...
     Leave      settings, leave types, requests, balances; company
                public holidays
     Assets     assets and who held them
     Documents  employee documents, company (organization) documents

   KEPT (shared set-up, used by every company)
     Security   users (staff log-ins), roles, rights, log-in history
                - a user's link to a company / employee is emptied
                  (re-link them after the new companies are added)
     Core       screen labels (both languages), countries, currencies,
                governorates
     Payroll    Kuwait banks, PIFSS rates, indemnity rules, bank file
                formats
     Leave      public holidays that apply to ALL companies
     Documents  employee document types and sections, company document
                types, issuing authorities
     Kuwait     compliance document types
     Assets     asset types (Cars, Motor Bikes, ...)
     Employee   the date-alert settings

   Files uploaded to the server (photos, scans) are NOT removed - empty
   the DocumentStorage folder by hand if you want them gone.

   HOW TO RUN
     1. TAKE A FULL BACKUP FIRST. This cannot be undone.
     2. Run as it is: @Mode = 'PREVIEW' only lists what would be
        removed (table, rows) - nothing changes.
     3. Set @Mode = 'EXECUTE' below and run again. Everything happens
        in one transaction: any error and nothing is removed.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @Mode VARCHAR(10) = 'PREVIEW';      -- <-- 'PREVIEW' (list only) or 'EXECUTE' (remove)

/* ---------------------------------------------------------------------
   1. What is cleared: whole schemas, plus the organization tables of
      Core - minus the shared set-up that is kept.
   --------------------------------------------------------------------- */
DECLARE @ClearSchemas TABLE (SchemaName SYSNAME PRIMARY KEY);
INSERT INTO @ClearSchemas VALUES (N'Employee'), (N'Kuwait'), (N'Payroll'), (N'Leave'), (N'Assets'), (N'Documents');

DECLARE @ClearCore TABLE (TableName SYSNAME PRIMARY KEY);
INSERT INTO @ClearCore VALUES (N'Companies'), (N'Branches'), (N'Departments'), (N'Sections'), (N'Positions'),
                              (N'Designations'), (N'Grades'), (N'CostCenters'), (N'Locations');

DECLARE @Keep TABLE (SchemaName SYSNAME, TableName SYSNAME, PRIMARY KEY (SchemaName, TableName));
INSERT INTO @Keep VALUES
    (N'Payroll', N'Banks'), (N'Payroll', N'PifssContributionRates'),
    (N'Payroll', N'IndemnityRuleSets'), (N'Payroll', N'IndemnityServiceSlabs'), (N'Payroll', N'IndemnityEntitlementFactors'),
    (N'Payroll', N'BankFileFormats'), (N'Payroll', N'BankFileFormatFields'),
    (N'Documents', N'DocumentTypes'), (N'Documents', N'DocumentSections'),
    (N'Documents', N'OrganizationDocumentTypes'), (N'Documents', N'IssuingAuthorities'),
    (N'Kuwait', N'ComplianceDocumentTypes'),
    (N'Assets', N'AssetTypes'),
    (N'Employee', N'DateFieldAlerts'),
    (N'Leave', N'PublicHolidays');            -- only its company rows go (below)

DECLARE @Clear TABLE (ObjectId INT PRIMARY KEY, FullName NVARCHAR(300), RowsBefore BIGINT NULL);
INSERT INTO @Clear (ObjectId, FullName)
SELECT t.object_id, QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
FROM   sys.tables AS t
JOIN   sys.schemas AS s ON s.schema_id = t.schema_id
WHERE  t.is_ms_shipped = 0
  AND  t.name NOT LIKE N'%[_]Legacy'
  AND  (s.name IN (SELECT SchemaName FROM @ClearSchemas)
        OR (s.name = N'Core' AND t.name IN (SELECT TableName FROM @ClearCore)))
  AND  NOT EXISTS (SELECT 1 FROM @Keep AS k WHERE k.SchemaName = s.name AND k.TableName = t.name);

DECLARE @sql NVARCHAR(MAX), @id INT, @name NVARCHAR(300), @n BIGINT;
DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT ObjectId, FullName FROM @Clear;
OPEN c; FETCH NEXT FROM c INTO @id, @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'SELECT @n = COUNT_BIG(*) FROM ' + @name + N';';
    EXEC sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @n OUTPUT;
    UPDATE @Clear SET RowsBefore = @n WHERE ObjectId = @id;
    FETCH NEXT FROM c INTO @id, @name;
END;
CLOSE c; DEALLOCATE c;

/* ---------------------------------------------------------------------
   2. Kept tables that point at a cleared one (a user's company /
      employee, a role's company, ...): the link is emptied - or, where
      it cannot be empty, the row goes (said below).
   --------------------------------------------------------------------- */
DECLARE @Links TABLE (FkName SYSNAME, KeptTable NVARCHAR(300), KeptObjectId INT, ColumnName SYSNAME, IsNullable BIT, ClearedTable NVARCHAR(300));
INSERT INTO @Links
SELECT  fk.name,
        QUOTENAME(ps.name) + N'.' + QUOTENAME(pt.name), pt.object_id,
        pc.name, pc.is_nullable,
        QUOTENAME(rs.name) + N'.' + QUOTENAME(rt.name)
FROM    sys.foreign_keys AS fk
JOIN    sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN    sys.tables  AS pt ON pt.object_id = fk.parent_object_id
JOIN    sys.schemas AS ps ON ps.schema_id = pt.schema_id
JOIN    sys.columns AS pc ON pc.object_id = pt.object_id AND pc.column_id = fkc.parent_column_id
JOIN    sys.tables  AS rt ON rt.object_id = fk.referenced_object_id
JOIN    sys.schemas AS rs ON rs.schema_id = rt.schema_id
WHERE   fk.referenced_object_id IN (SELECT ObjectId FROM @Clear)
  AND   fk.parent_object_id NOT IN (SELECT ObjectId FROM @Clear);

/* a user or a role that cannot lose its company: stop before anything changes */
IF EXISTS (SELECT 1 FROM @Links WHERE IsNullable = 0 AND KeptTable IN (N'[Security].[Users]', N'[Security].[Roles]'))
BEGIN
    SELECT KeptTable, ColumnName, ClearedTable FROM @Links WHERE IsNullable = 0 AND KeptTable IN (N'[Security].[Users]', N'[Security].[Roles]');
    RAISERROR (N'STOPPED - users or roles must keep a company (a required column, listed above). Nothing was changed - send this list to the developer.', 16, 1);
    RETURN;
END;

/* ---------------------------------------------------------------------
   PREVIEW: list only
   --------------------------------------------------------------------- */
IF @Mode <> 'EXECUTE'
BEGIN
    SELECT FullName AS [Table to clear], RowsBefore AS [Rows now]
    FROM   @Clear ORDER BY FullName;
    SELECT KeptTable AS [Kept table], ColumnName AS [Column],
           CASE WHEN KeptTable = N'[Leave].[PublicHolidays]' THEN N'company holidays removed, all-company holidays kept'
                WHEN IsNullable = 1 THEN N'emptied (set to NULL)' ELSE N'rows that point at cleared data are removed' END AS [What happens],
           ClearedTable AS [Points at]
    FROM   @Links ORDER BY KeptTable, ColumnName;
    PRINT N'PREVIEW only - nothing was changed. Take a backup, set @Mode = ''EXECUTE'' and run again.';
    RETURN;
END;

/* ---------------------------------------------------------------------
   EXECUTE
   --------------------------------------------------------------------- */
BEGIN TRY
BEGIN TRANSACTION;

    /* a. the soft-delete guards (db/28) turn a DELETE into "flag as deleted": off for this run */
    DECLARE @Trg TABLE (TriggerName NVARCHAR(300), TableName NVARCHAR(300));
    INSERT INTO @Trg
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(tr.object_id)) + N'.' + QUOTENAME(tr.name), c2.FullName
    FROM   sys.triggers AS tr
    JOIN   @Clear AS c2 ON c2.ObjectId = tr.parent_id
    WHERE  tr.is_disabled = 0;
    INSERT INTO @Trg
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(tr.object_id)) + N'.' + QUOTENAME(tr.name), l.KeptTable
    FROM   sys.triggers AS tr
    JOIN   (SELECT DISTINCT KeptObjectId, KeptTable FROM @Links) AS l ON l.KeptObjectId = tr.parent_id
    WHERE  tr.is_disabled = 0;

    SET @sql = N'';
    SELECT @sql += N'DISABLE TRIGGER ' + TriggerName + N' ON ' + TableName + N';' + CHAR(10) FROM @Trg;
    EXEC (@sql);

    /* b. the links from kept tables */
    DECLARE @k NVARCHAR(300), @col SYSNAME, @nul BIT, @ref NVARCHAR(300);
    DECLARE l CURSOR LOCAL FAST_FORWARD FOR SELECT KeptTable, ColumnName, IsNullable, ClearedTable FROM @Links;
    OPEN l; FETCH NEXT FROM l INTO @k, @col, @nul, @ref;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = CASE WHEN @k = N'[Leave].[PublicHolidays]' OR @nul = 0
                        THEN N'DELETE FROM ' + @k + N' WHERE ' + QUOTENAME(@col) + N' IS NOT NULL;'
                        ELSE N'UPDATE ' + @k + N' SET ' + QUOTENAME(@col) + N' = NULL WHERE ' + QUOTENAME(@col) + N' IS NOT NULL;' END;
        EXEC (@sql);
        PRINT CONCAT(@k, N'.', @col, N': ', @@ROWCOUNT, CASE WHEN @k = N'[Leave].[PublicHolidays]' OR @nul = 0 THEN N' rows removed' ELSE N' links emptied' END);
        FETCH NEXT FROM l INTO @k, @col, @nul, @ref;
    END;
    CLOSE l; DEALLOCATE l;

    /* c. the foreign keys among the cleared tables: off while they are emptied */
    DECLARE @Fk TABLE (FkName SYSNAME, TableName NVARCHAR(300));
    INSERT INTO @Fk
    SELECT QUOTENAME(fk.name), c3.FullName
    FROM   sys.foreign_keys AS fk
    JOIN   @Clear AS c3 ON c3.ObjectId = fk.parent_object_id
    WHERE  fk.is_disabled = 0;

    SET @sql = N'';
    SELECT @sql += N'ALTER TABLE ' + TableName + N' NOCHECK CONSTRAINT ' + FkName + N';' + CHAR(10) FROM @Fk;
    EXEC (@sql);

    /* d. empty the tables */
    SET @sql = N'';
    SELECT @sql += N'DELETE FROM ' + FullName + N';' + CHAR(10) FROM @Clear;
    EXEC (@sql);

    /* e. keys and guards back on (WITH CHECK: they stay trusted) */
    SET @sql = N'';
    SELECT @sql += N'ALTER TABLE ' + TableName + N' WITH CHECK CHECK CONSTRAINT ' + FkName + N';' + CHAR(10) FROM @Fk;
    EXEC (@sql);

    SET @sql = N'';
    SELECT @sql += N'ENABLE TRIGGER ' + TriggerName + N' ON ' + TableName + N';' + CHAR(10) FROM @Trg;
    EXEC (@sql);

    /* f. numbering from 1 again (tables that never had a row are left alone) */
    SET @sql = N'';
    SELECT @sql += N'DBCC CHECKIDENT (''' + REPLACE(c4.FullName, N'''', N'''''') + N''', RESEED, 0) WITH NO_INFOMSGS;' + CHAR(10)
    FROM   @Clear AS c4
    JOIN   sys.identity_columns AS ic ON ic.object_id = c4.ObjectId
    WHERE  ic.last_value IS NOT NULL;
    EXEC (@sql);

COMMIT TRANSACTION;

    SELECT FullName AS [Cleared table], RowsBefore AS [Rows removed] FROM @Clear WHERE RowsBefore > 0 ORDER BY FullName;
    PRINT CONCAT(N'Done - ', (SELECT COUNT(1) FROM @Clear), N' tables emptied, ', (SELECT ISNULL(SUM(RowsBefore), 0) FROM @Clear),
                 N' rows removed. Users kept: ', (SELECT COUNT(1) FROM [Security].[Users]),
                 N'. Next: add the companies (or run db/92), then link the users to their company.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(2000) = CONCAT(N'Reset rolled back - nothing was removed. ', ERROR_MESSAGE());
    RAISERROR (@Err, 16, 1);
END CATCH;
GO
