/* =====================================================================
   Clear_Payroll_Attendance_Leave.sql  -  HRMS: remove the payroll,
   attendance and leave records, keep the employees and the set-up
   ---------------------------------------------------------------------
   For starting the payroll / attendance / leave over (e.g. after test
   runs) WITHOUT losing the companies, employees, users or roles. The
   rows are really removed (not flagged as deleted) and the numbering of
   the emptied tables starts again from 1.

   CLEARED (all rows) - @ClearSetup = 0, the default
     Payroll     payrolls (runs, lines, issues, history, funding),
                 payslips, pay items (allowances / deductions / one-time
                 items) and their history, collections, final
                 settlements, bank files and payments, journals and cost
                 allocations, period status history
     Attendance  imported files, days (clock in / out), mobile punches,
                 postings to the payroll
     Leave       requests, their history, the balance ledger (opening
                 balances and adjustments too)

   RESET
     Payroll periods   kept (they are the calendar), every one set back
                       to OPEN

   KEPT
     Core / Organization  companies, branches, departments, sections,
                          positions, designations, grades, cost centres,
                          locations, labels, countries, currencies
     Employee             employees and every employee table - salary
                          and bank details (Employee.EmployeePayroll),
                          dependents, documents, compliance, assets
     Security             users, roles, rights, log-in history
     Payroll set-up       pay components, payroll calendars + periods,
                          salary structures, deduction policies /
                          priorities, proration and overtime rules,
                          GL mappings, accounting defaults, approval
                          processes, company bank accounts, Kuwait banks,
                          PIFSS rates, indemnity rules, bank file formats
     Attendance set-up    patterns and their slabs, employee pattern
                          assignments, device IDs
     Leave set-up         leave types and pay bands, settings, public
                          holidays

   @ClearSetup = 1  also removes the payroll, attendance and leave
                    SET-UP above (components, calendars, periods, rules,
                    patterns, leave types, holidays ...). The Kuwait
                    reference data (banks, PIFSS rates, indemnity rules,
                    bank file formats) is always kept. An employee's
                    link to a removed calendar is emptied.

   NOT TOUCHED
     * An employee terminated by a final settlement stays terminated
       (only the settlement record goes).
     * Files uploaded to the server (leave documents) stay on disk.

   SAFETY
     * Nothing is ever deleted from a table that is kept. If a kept
       table has a REQUIRED link to a table being cleared, the script
       stops before changing anything and lists it.
     * Everything runs in one transaction: any error and nothing is
       removed.

   HOW TO RUN
     1. TAKE A FULL BACKUP FIRST. This cannot be undone.
     2. Run as it is: @Mode = 'PREVIEW' lists what would be removed
        (table, rows) - nothing changes.
     3. Set @Mode = 'EXECUTE' below and run again.
   ===================================================================== */
SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

DECLARE @Mode       VARCHAR(10) = 'PREVIEW';   -- <-- 'PREVIEW' (list only) or 'EXECUTE' (remove)
DECLARE @ClearSetup BIT         = 0;           -- <-- 0 = records only (recommended), 1 = the set-up too

/* ---------------------------------------------------------------------
   1. What is cleared: every table of these schemas, minus what is kept.
   --------------------------------------------------------------------- */
DECLARE @ClearSchemas TABLE (SchemaName SYSNAME PRIMARY KEY);
INSERT INTO @ClearSchemas VALUES (N'Payroll'), (N'Attendance'), (N'Leave'), (N'Overtime');

/* always kept: Kuwait reference data, the same for every company */
DECLARE @Keep TABLE (SchemaName SYSNAME, TableName SYSNAME, PRIMARY KEY (SchemaName, TableName));
INSERT INTO @Keep VALUES
    (N'Payroll', N'Banks'), (N'Payroll', N'PifssContributionRates'),
    (N'Payroll', N'IndemnityRuleSets'), (N'Payroll', N'IndemnityServiceSlabs'), (N'Payroll', N'IndemnityEntitlementFactors'),
    (N'Payroll', N'BankFileFormats'), (N'Payroll', N'BankFileFormatFields');

/* kept unless @ClearSetup = 1: the set-up */
IF @ClearSetup = 0
    INSERT INTO @Keep VALUES
        (N'Payroll', N'PayComponents'), (N'Payroll', N'PayrollCalendars'), (N'Payroll', N'PayrollPeriods'),
        (N'Payroll', N'SalaryStructures'), (N'Payroll', N'SalaryStructureComponents'),
        (N'Payroll', N'DeductionPolicies'), (N'Payroll', N'DeductionPriorities'),
        (N'Payroll', N'ProrationRules'), (N'Payroll', N'OvertimeRates'),
        (N'Payroll', N'GLMappings'), (N'Payroll', N'AccountingDefaults'),
        (N'Payroll', N'ApprovalProcesses'), (N'Payroll', N'CompanyBankAccounts'),
        (N'Attendance', N'Patterns'), (N'Attendance', N'PatternSlabs'),
        (N'Attendance', N'EmployeePatterns'), (N'Attendance', N'EmployeeSettings'),
        (N'Leave', N'LeaveTypes'), (N'Leave', N'LeaveTypeTiers'), (N'Leave', N'Settings'), (N'Leave', N'PublicHolidays');

DECLARE @Clear TABLE (ObjectId INT PRIMARY KEY, FullName NVARCHAR(300), RowsBefore BIGINT NULL);
INSERT INTO @Clear (ObjectId, FullName)
SELECT t.object_id, QUOTENAME(s.name) + N'.' + QUOTENAME(t.name)
FROM   sys.tables AS t
JOIN   sys.schemas AS s ON s.schema_id = t.schema_id
WHERE  t.is_ms_shipped = 0
  AND  t.name NOT LIKE N'%[_]Legacy'
  AND  s.name IN (SELECT SchemaName FROM @ClearSchemas)
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
   2. Kept tables that point at a cleared one (an employee's payroll
      calendar, a period's last run ...): the link is emptied. A
      REQUIRED link stops the script - no kept row is ever deleted.
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

IF EXISTS (SELECT 1 FROM @Links WHERE IsNullable = 0)
BEGIN
    SELECT KeptTable AS [Kept table], ColumnName AS [Required column], ClearedTable AS [Points at]
    FROM   @Links WHERE IsNullable = 0 ORDER BY KeptTable;
    RAISERROR (N'STOPPED - the kept tables listed above must point at a row of a table that would be cleared. Nothing was changed - send this list to the developer.', 16, 1);
    RETURN;
END;

/* ---------------------------------------------------------------------
   PREVIEW: list only
   --------------------------------------------------------------------- */
IF @Mode <> 'EXECUTE'
BEGIN
    SELECT FullName AS [Table to clear], RowsBefore AS [Rows now]
    FROM   @Clear ORDER BY FullName;

    SELECT KeptTable AS [Kept table], ColumnName AS [Column], N'emptied (set to NULL)' AS [What happens], ClearedTable AS [Points at]
    FROM   @Links ORDER BY KeptTable, ColumnName;

    IF @ClearSetup = 0 AND OBJECT_ID(N'[Payroll].[PayrollPeriods]', N'U') IS NOT NULL
        SELECT N'[Payroll].[PayrollPeriods]' AS [Kept table], COUNT(1) AS [Periods not OPEN - set back to OPEN]
        FROM   [Payroll].[PayrollPeriods] WHERE Status <> N'OPEN';

    SELECT N'KEPT' AS [Summary], (SELECT COUNT(1) FROM [Core].[Companies]) AS Companies,
           (SELECT COUNT(1) FROM [Employee].[Employees]) AS Employees,
           (SELECT COUNT(1) FROM [Security].[Users]) AS Users,
           (SELECT COUNT(1) FROM [Security].[Roles]) AS Roles;

    DECLARE @PTables INT = (SELECT COUNT(1) FROM @Clear), @PRows BIGINT = (SELECT ISNULL(SUM(RowsBefore), 0) FROM @Clear);
    PRINT CONCAT(N'PREVIEW only - nothing was changed. ', @PTables, N' tables, ',
                 @PRows, N' rows would be removed (@ClearSetup = ', @ClearSetup, N').');
    PRINT N'Take a backup, set @Mode = ''EXECUTE'' and run again.';
    RETURN;
END;

/* ---------------------------------------------------------------------
   EXECUTE
   --------------------------------------------------------------------- */
DECLARE @Companies INT = (SELECT COUNT(1) FROM [Core].[Companies]),
        @Employees INT = (SELECT COUNT(1) FROM [Employee].[Employees]),
        @Users     INT = (SELECT COUNT(1) FROM [Security].[Users]),
        @Roles     INT = (SELECT COUNT(1) FROM [Security].[Roles]);

BEGIN TRY
BEGIN TRANSACTION;

    /* a. the soft-delete guards (db/28) turn a DELETE into "flag as deleted": off for this run */
    DECLARE @Trg TABLE (TriggerName NVARCHAR(300), TableName NVARCHAR(300));
    INSERT INTO @Trg
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(tr.object_id)) + N'.' + QUOTENAME(tr.name), c2.FullName
    FROM   sys.triggers AS tr
    JOIN   @Clear AS c2 ON c2.ObjectId = tr.parent_id
    WHERE  tr.is_disabled = 0;

    SET @sql = N'';
    SELECT @sql += N'DISABLE TRIGGER ' + TriggerName + N' ON ' + TableName + N';' + CHAR(10) FROM @Trg;
    EXEC (@sql);

    /* b. the links from kept tables: emptied (all nullable - checked above) */
    DECLARE @k NVARCHAR(300), @col SYSNAME;
    DECLARE l CURSOR LOCAL FAST_FORWARD FOR SELECT DISTINCT KeptTable, ColumnName FROM @Links;
    OPEN l; FETCH NEXT FROM l INTO @k, @col;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = N'UPDATE ' + @k + N' SET ' + QUOTENAME(@col) + N' = NULL WHERE ' + QUOTENAME(@col) + N' IS NOT NULL;';
        EXEC (@sql);
        PRINT CONCAT(@k, N'.', @col, N': ', @@ROWCOUNT, N' links emptied');
        FETCH NEXT FROM l INTO @k, @col;
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

    /* f. the payroll periods that are kept: open again (their payrolls are gone) */
    IF @ClearSetup = 0 AND OBJECT_ID(N'[Payroll].[PayrollPeriods]', N'U') IS NOT NULL
    BEGIN
        SET @sql = N'UPDATE [Payroll].[PayrollPeriods] SET Status = N''OPEN'''
                 + CASE WHEN COL_LENGTH(N'Payroll.PayrollPeriods', N'StatusChangedBy') IS NOT NULL
                        THEN N', StatusChangedBy = NULL, StatusChangedDate = NULL' ELSE N'' END
                 + N' WHERE Status <> N''OPEN'';';
        EXEC (@sql);
        PRINT CONCAT(N'[Payroll].[PayrollPeriods]: ', @@ROWCOUNT, N' periods set back to OPEN');
    END;

    /* g. numbering from 1 again (tables that never had a row are left alone) */
    SET @sql = N'';
    SELECT @sql += N'DBCC CHECKIDENT (''' + REPLACE(c4.FullName, N'''', N'''''') + N''', RESEED, 0) WITH NO_INFOMSGS;' + CHAR(10)
    FROM   @Clear AS c4
    JOIN   sys.identity_columns AS ic ON ic.object_id = c4.ObjectId
    WHERE  ic.last_value IS NOT NULL;
    EXEC (@sql);

    /* h. last check: the employees, companies, users and roles are all still there */
    IF @Companies <> (SELECT COUNT(1) FROM [Core].[Companies])
       OR @Employees <> (SELECT COUNT(1) FROM [Employee].[Employees])
       OR @Users <> (SELECT COUNT(1) FROM [Security].[Users])
       OR @Roles <> (SELECT COUNT(1) FROM [Security].[Roles])
        RAISERROR (N'A kept table lost rows - undone.', 16, 1);

COMMIT TRANSACTION;

    SELECT FullName AS [Cleared table], RowsBefore AS [Rows removed] FROM @Clear WHERE RowsBefore > 0 ORDER BY FullName;
    DECLARE @Tables INT = (SELECT COUNT(1) FROM @Clear), @Removed BIGINT = (SELECT ISNULL(SUM(RowsBefore), 0) FROM @Clear);
    PRINT CONCAT(N'Done - ', @Tables, N' tables emptied, ', @Removed,
                 N' rows removed. Kept: ', @Companies, N' companies, ', @Employees, N' employees, ', @Users, N' users, ', @Roles, N' roles.');
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(2000) = CONCAT(N'Clear rolled back - nothing was removed. ', ERROR_MESSAGE());
    RAISERROR (@Err, 16, 1);
END CATCH;
GO
